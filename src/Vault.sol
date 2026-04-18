// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IVault} from "./interfaces/IVault.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {Strategy} from "./Strategy.sol";

/// @title  AgentVault — target-date ERC-4626 vault, factory, and router.
/// @notice The vault:
///         - is a TARGET-DATE fund: a fixed `DEADLINE` timestamp gates the
///           two phases. Before DEADLINE: deposits/mints accepted,
///           withdrawals/redemptions revert. From DEADLINE onward: no more
///           deposits, withdrawals unlocked for event-specific expenses.
///         - mints/burns shares in exchange for the underlying asset (ERC-4626)
///         - deploys Strategy contracts and keeps a weight-indexed registry
///         - auto-rebalances on deposit: each strategy receives its weight share
///         - auto-withdraws on redemption: pulls from strategies when idle < ask
///         - acts as the single AccessControl root for all strategies
///           (strategy contracts query `hasRole` back here)
///
///         Design invariants:
///         - Strategy contracts hold their own funds; the vault no longer tracks
///           per-strategy `allocatedAmount`. NAV is read live from
///           `strategy.totalValue()`.
///         - The delegate / AI agent CANNOT call the vault directly — they call
///           the strategy contract's {executeAction}. The vault's only
///           "execute" surface is {rebalance}, which is authority-gated and
///           remains open in BOTH phases so the authority can drain
///           strategies back to idle before users redeem.
///         - If a strategy's weight sums to less than 10_000, the residual
///           deposit share stays idle in the vault (liquidity buffer).
contract Vault is ERC4626, AccessControl, ReentrancyGuard, IVault {
    using SafeERC20 for IERC20;

    bytes32 public constant AUTHORITY_ROLE = keccak256("AUTHORITY_ROLE");

    /// @notice Implementation contract cloned on every {createStrategy} call.
    ///         Deployed once in the constructor; immutable thereafter.
    address public immutable STRATEGY_IMPLEMENTATION;

    /// @notice Unix timestamp at which the vault matures. Deposits are
    ///         blocked from this timestamp onward; withdrawals are blocked
    ///         until this timestamp is reached. Set once in the constructor.
    uint256 public immutable DEADLINE;

    // ─────────────────────────────────────────────────────────────────────────
    // Storage
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Convenience mirror of the current authority address.
    address public authority;

    /// @notice Total number of strategies ever created (active + deactivated).
    uint256 public strategyCount;

    /// @notice Strategy registry: id → Strategy contract address.
    mapping(uint256 => address) public strategies;

    /// @notice Target weight per strategy in basis points (0–10_000).
    mapping(uint256 => uint16) public strategyWeights;

    /// @notice Active flag per strategy. Deactivated strategies are skipped
    ///         by auto-rebalance and totalAssets() calculations.
    mapping(uint256 => bool) public strategyActive;

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deploy a new vault, grant `admin_` the admin role and
    ///         `authority_` the authority role, and deploy the singleton
    ///         Strategy implementation that all clones will delegate to.
    /// @param  asset_      Underlying ERC-20 the vault will hold and account in.
    /// @param  admin_      Initial holder of `DEFAULT_ADMIN_ROLE`.
    /// @param  authority_  Initial holder of `AUTHORITY_ROLE` (rebalancer).
    /// @param  name_       ERC-20 name of the share token (e.g. "AgentVault USDC").
    /// @param  symbol_     ERC-20 symbol of the share token (e.g. "avUSDC").
    /// @param  deadline_   Unix timestamp at which deposits close and
    ///                     withdrawals open. Must be strictly in the future.
    constructor(
        IERC20 asset_,
        address admin_,
        address authority_,
        string memory name_,
        string memory symbol_,
        uint256 deadline_
    ) ERC20(name_, symbol_) ERC4626(asset_) {
        if (admin_ == address(0) || authority_ == address(0)) revert ZeroAddress();
        if (deadline_ <= block.timestamp) revert DeadlineInPast(deadline_, block.timestamp);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(AUTHORITY_ROLE, authority_);
        authority = authority_;
        DEADLINE = deadline_;

        // Deploy the Strategy implementation once. Its constructor sets
        // `initialized = true` so nobody can initialize the implementation
        // directly — it's only usable via cloning.
        STRATEGY_IMPLEMENTATION = address(new Strategy());

        emit VaultInitialized(address(asset_), admin_, authority_, deadline_);
    }

    /// @inheritdoc IVault
    function isMatured() public view returns (bool) {
        return block.timestamp >= DEADLINE;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ERC-4626 overrides
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Offset 6 of virtual shares to blunt the donate-to-vault
    ///         inflation attack on a fresh vault. See OpenZeppelin
    ///         ERC-4626 inflation-attack docs.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    /// @notice Live NAV: idle balance + sum of every active strategy's totalValue.
    /// @dev    Each strategy's totalValue is its own (idle + valueSources).
    ///         Inactive strategies are skipped (should have 0 value anyway
    ///         since deactivation requires zero totalValue).
    function totalAssets() public view override returns (uint256) {
        uint256 acc = IERC20(asset()).balanceOf(address(this));
        uint256 n = strategyCount;
        for (uint256 i; i < n; ++i) {
            if (strategyActive[i]) {
                acc += IStrategy(strategies[i]).totalValue();
            }
        }
        return acc;
    }

    // ─── User-facing entry points (wrapped with nonReentrant) ───────────────

    /// @notice Deposit `assets` of the underlying and mint vault shares to
    ///         `receiver`. Triggers `_autoRebalanceIn`, which fans the
    ///         deposit out across active strategies by target weight.
    /// @return shares Number of shares minted (per ERC-4626 conversion).
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @notice Mint exactly `shares` of vault shares to `receiver` by pulling
    ///         the implied amount of underlying from the caller. Same
    ///         auto-rebalance path as {deposit}.
    /// @return assets Amount of underlying actually pulled from the caller.
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @notice Withdraw exactly `assets` of underlying to `receiver`, burning
    ///         the implied number of `owner`'s shares. If idle balance is
    ///         insufficient, pulls the deficit from active strategies in
    ///         registration order.
    /// @return shares Number of shares burned from `owner`.
    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    /// @notice Redeem `shares` of `owner`'s vault shares for underlying paid
    ///         to `receiver`. Same strategy-pull path as {withdraw}.
    /// @return assets Amount of underlying paid out.
    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }

    /// @dev After receiving user assets and minting shares, distribute the
    ///      deposit across active strategies by target weight. Strategies
    ///      without a deposit config (set on the strategy contract) just
    ///      receive idle asset that their delegate can later operate on.
    ///      BLOCKED once the vault has matured (target-date semantics).
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (block.timestamp >= DEADLINE) revert VaultMatured(DEADLINE);
        super._deposit(caller, receiver, assets, shares);
        _autoRebalanceIn(assets);
    }

    /// @dev Before paying out assets, top up the vault's idle balance from
    ///      strategies if needed. BLOCKED until the vault has matured.
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (block.timestamp < DEADLINE) revert VaultNotMatured(DEADLINE);
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (idle < assets) {
            _autoPullFromStrategies(assets - idle);
        }
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    // NOTE: we intentionally do NOT override maxDeposit/maxWithdraw. OZ's
    //       ERC-4626 checks those BEFORE `_deposit`/`_withdraw`, and a
    //       returned 0 would make OZ throw its own generic
    //       `ERC4626ExceededMax*` error before ours. Our explicit
    //       {VaultMatured} / {VaultNotMatured} reverts in the hooks above
    //       give better diagnostic information to callers. UIs should
    //       check {isMatured} directly to gate the deposit/withdraw UX.

    // ─────────────────────────────────────────────────────────────────────────
    // Roles
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Replace the address holding `AUTHORITY_ROLE` (the rebalancer)
    ///         and update the convenience mirror. Admin rotation is done via
    ///         OpenZeppelin AccessControl's `grantRole` / `revokeRole`.
    function setAuthority(address newAuthority) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAuthority == address(0)) revert ZeroAddress();
        address old = authority;
        if (old != address(0)) _revokeRole(AUTHORITY_ROLE, old);
        _grantRole(AUTHORITY_ROLE, newAuthority);
        authority = newAuthority;
        emit AuthoritySet(old, newAuthority);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Factory + registry
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deploy a new Strategy (EIP-1167 clone of the implementation)
    ///         and initialize it bound to this vault.
    /// @dev    Each clone is ~45 bytes; the full Strategy code lives only in
    ///         {STRATEGY_IMPLEMENTATION}. The clone's delegatecall-based
    ///         storage is initialized in `Strategy.initialize`.
    function createStrategy(address delegate)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 strategyId, address strategyAddress)
    {
        if (delegate == address(0)) revert ZeroAddress();
        strategyId = strategyCount;
        strategyAddress = Clones.clone(STRATEGY_IMPLEMENTATION);
        Strategy(strategyAddress).initialize(address(this), IERC20(asset()), delegate);
        strategies[strategyId] = strategyAddress;
        strategyActive[strategyId] = true;
        unchecked {
            strategyCount = strategyId + 1;
        }
        emit StrategyCreated(strategyId, strategyAddress, delegate);
    }

    /// @notice Set the per-strategy target weight in basis points (0–10_000).
    /// @dev    Weights are absolute, not normalized: each strategy receives
    ///         `deposit * weightBps / 10_000` on every deposit. The sum of
    ///         active weights is intentionally NOT capped at 10_000 today
    ///         (residual stays idle, overflow reverts mid-deposit). See
    ///         TODO.md for the open design question.
    function setStrategyWeight(uint256 strategyId, uint16 weightBps)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (weightBps > 10_000) revert WeightTooHigh(weightBps);
        _requireActive(strategyId);
        uint16 old = strategyWeights[strategyId];
        strategyWeights[strategyId] = weightBps;
        emit StrategyWeightSet(strategyId, old, weightBps);
    }

    /// @notice Permanently deactivate a strategy. The strategy must have
    ///         zero total value (idle + external positions) — drain it via
    ///         {rebalance} with negative delta first.
    function deactivateStrategy(uint256 strategyId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address strategyAddr = strategies[strategyId];
        if (strategyAddr == address(0)) revert StrategyDoesNotExist(strategyId);
        if (!strategyActive[strategyId]) revert StrategyAlreadyDeactivated(strategyId);
        uint256 remaining = IStrategy(strategyAddr).totalValue();
        if (remaining != 0) revert StrategyStillHoldsFunds(strategyId, remaining);
        strategyActive[strategyId] = false;
        strategyWeights[strategyId] = 0;
        emit StrategyDeactivated(strategyId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Authority: manual rebalance
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Manually move funds in or out of a strategy. Positive `delta`
    ///         pushes idle into the strategy (and runs its deposit config);
    ///         negative `delta` pulls from the strategy (and runs its
    ///         withdraw config if needed). Authority-only so users cannot
    ///         move other people's positions around.
    /// @param  strategyId  Index in the strategy registry.
    /// @param  delta       Signed amount: > 0 push, < 0 pull, == 0 no-op.
    /// @return actual      Amount actually moved (pull may return less than
    ///                     requested if the strategy can't liquidate enough).
    function rebalance(uint256 strategyId, int256 delta)
        external
        onlyRole(AUTHORITY_ROLE)
        nonReentrant
        returns (uint256 actual)
    {
        address strategyAddr = _requireActive(strategyId);

        if (delta > 0) {
            // casting is safe because delta > 0
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 amount = uint256(delta);
            uint256 idle = IERC20(asset()).balanceOf(address(this));
            if (amount > idle) revert InsufficientIdle(amount, idle);
            IERC20(asset()).safeTransfer(strategyAddr, amount);
            IStrategy(strategyAddr).pushFunds(amount);
            actual = amount;
        } else if (delta < 0) {
            // casting is safe because -delta > 0
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 amount = uint256(-delta);
            actual = IStrategy(strategyAddr).pullFunds(amount);
        }
        emit Rebalanced(strategyId, delta, actual);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Post-maturity: drain all strategies
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IVault
    /// @dev Permissionless once matured. Pulls every active strategy's full
    ///      reported value back to the vault's idle balance. The loop tops
    ///      out at each strategy's available liquidity, so a strategy that
    ///      cannot liquidate everything in one go will return what it can
    ///      (same semantics as `pullFunds`). Repeat calls eventually drain.
    function drainAllStrategies() external nonReentrant returns (uint256 totalPulled) {
        if (block.timestamp < DEADLINE) revert VaultNotMatured(DEADLINE);
        uint256 n = strategyCount;
        for (uint256 i; i < n; ++i) {
            if (!strategyActive[i]) continue;
            IStrategy strategy = IStrategy(strategies[i]);
            uint256 available = strategy.totalValue();
            if (available == 0) continue;
            totalPulled += strategy.pullFunds(available);
        }
        emit StrategiesDrained(totalPulled);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal: auto-rebalance on user deposit/withdrawal
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Distribute `amount` across active strategies by target weight.
    ///      Each strategy's share = amount * weight / 10_000 (absolute, not
    ///      proportional to qualifying weight). Residual (if total weights
    ///      < 10_000) stays idle — liquidity buffer.
    function _autoRebalanceIn(uint256 amount) internal {
        if (amount == 0) return;
        uint256 n = strategyCount;
        IERC20 assetToken = IERC20(asset());

        for (uint256 i; i < n; ++i) {
            if (!strategyActive[i]) continue;
            uint16 weight = strategyWeights[i];
            if (weight == 0) continue;

            uint256 share = (amount * uint256(weight)) / 10_000;
            if (share == 0) continue;

            address strategyAddr = strategies[i];
            assetToken.safeTransfer(strategyAddr, share);
            IStrategy(strategyAddr).pushFunds(share);
        }
    }

    /// @dev Cover a withdrawal deficit by pulling from active strategies.
    ///      Iterates in registration order. Each strategy returns up to
    ///      `request` of asset (running its withdraw config if configured).
    ///      Reverts if the full deficit cannot be covered.
    function _autoPullFromStrategies(uint256 deficit) internal {
        uint256 n = strategyCount;
        uint256 pulled;

        for (uint256 i; i < n && pulled < deficit; ++i) {
            if (!strategyActive[i]) continue;
            IStrategy strategy = IStrategy(strategies[i]);
            uint256 available = strategy.totalValue();
            if (available == 0) continue;
            uint256 request = deficit - pulled;
            if (request > available) request = available;

            uint256 actual = strategy.pullFunds(request);
            pulled += actual;
        }

        if (pulled < deficit) {
            revert InsufficientLiquidity(deficit, pulled);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Resolve a strategyId to its contract address while asserting
    ///      both that it has been registered and that it has not been
    ///      permanently deactivated. Returns the address so callers can
    ///      avoid a second mapping lookup.
    function _requireActive(uint256 strategyId) internal view returns (address strategyAddr) {
        strategyAddr = strategies[strategyId];
        if (strategyAddr == address(0)) revert StrategyDoesNotExist(strategyId);
        if (!strategyActive[strategyId]) revert StrategyInactive(strategyId);
    }
}
