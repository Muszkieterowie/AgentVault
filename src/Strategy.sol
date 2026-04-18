// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IStrategy} from "./interfaces/IStrategy.sol";

/// @title  Strategy — a single AgentVault strategy contract.
/// @notice One Strategy instance per strategy in the vault. Holds its own
///         slice of the asset and any external positions (aTokens, debt,
///         etc.). The AI agent (delegate) performs protocol actions through
///         {executeAction}; the vault moves funds via {pushFunds} and
///         {pullFunds} during deposits, withdrawals, and manual rebalancing.
///
///         Access control is delegated to the Vault contract's AccessControl:
///         - onlyVault : pushFunds, pullFunds (hardcoded immutable vault)
///         - onlyAdmin : whitelist, configs, value sources, approvals,
///                       setDelegate (Vault.DEFAULT_ADMIN_ROLE)
///         - onlyDelegateOrAuthority : executeAction (delegate address
///                       or Vault.AUTHORITY_ROLE)
contract Strategy is IStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant AUTHORITY_ROLE = keccak256("AUTHORITY_ROLE");

    // ─────────────────────────────────────────────────────────────────────────
    // Storage
    // ─────────────────────────────────────────────────────────────────────────
    //
    // NOTE: these were `immutable` in the original non-cloned design. With
    // EIP-1167 minimal proxies the implementation's constructor doesn't run
    // on the clone, so immutables would be zero in the proxy. They are now
    // regular storage set via {initialize}.

    address public vault;
    IERC20  public asset;

    /// @notice Once-set guard for {initialize}. Set to true on the
    ///         implementation contract by the constructor (locking it), and
    ///         set to true on each clone by {initialize}.
    bool public initialized;

    address public delegate;
    uint64  public actionCount;

    mapping(address => mapping(bytes4 => AllowedAction)) public allowedActions;
    ValueSource[] internal _valueSources;
    ActionConfig  internal _depositConfig;
    ActionConfig  internal _withdrawConfig;

    /// @notice Admin-curated allowlist of spenders that {approveToken} is
    ///         allowed to grant allowance to. Caps the blast radius of a
    ///         compromised delegate: even though the delegate can call
    ///         {approveToken} themselves, they can only approve trusted
    ///         protocols (Aave V3 Pool, etc.) that the admin pre-vetted.
    mapping(address => bool) public trustedSpenders;

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Restrict to calls coming from the parent Vault contract. Used
    ///      for `pushFunds` / `pullFunds`, the only fund-movement entrypoints.
    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault(msg.sender);
        _;
    }

    /// @dev Restrict to addresses that hold `DEFAULT_ADMIN_ROLE` on the Vault.
    ///      Strategy has no role storage of its own — auth is delegated up.
    modifier onlyAdmin() {
        if (!IAccessControl(vault).hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAdmin(msg.sender);
        }
        _;
    }

    /// @dev Restrict to either the strategy's delegate or any holder of
    ///      `DEFAULT_ADMIN_ROLE` on the Vault. Used for `approveToken` so
    ///      the agent can bump allowances on pre-vetted protocols without
    ///      round-tripping to the admin.
    modifier onlyAdminOrDelegate() {
        if (
            msg.sender != delegate &&
            !IAccessControl(vault).hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) {
            revert NotAdminNorDelegate(msg.sender);
        }
        _;
    }

    /// @dev Restrict to either the strategy's delegate (the AI agent EOA) or
    ///      any holder of `AUTHORITY_ROLE` on the Vault. Used for
    ///      `executeAction`.
    modifier onlyDelegateOrAuthority() {
        if (
            msg.sender != delegate &&
            !IAccessControl(vault).hasRole(AUTHORITY_ROLE, msg.sender)
        ) {
            revert NotDelegateNorAuthority(msg.sender);
        }
        _;
    }

    /// @dev Sanity guard: every public function that touches storage should
    ///      run after {initialize} has been called on this clone.
    modifier onlyInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor (locks the implementation only)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev The constructor only runs on the implementation contract (clones
    ///      don't execute it via delegatecall). We set `initialized = true`
    ///      so nobody can call {initialize} on the implementation directly
    ///      — it's only usable via cloning.
    constructor() {
        initialized = true;
    }

    /// @inheritdoc IStrategy
    function initialize(address vault_, IERC20 asset_, address delegate_) external {
        if (initialized) revert AlreadyInitialized();
        if (vault_ == address(0) || address(asset_) == address(0) || delegate_ == address(0)) {
            revert ZeroAddress();
        }
        initialized = true;
        vault = vault_;
        asset = asset_;
        delegate = delegate_;
        emit StrategyInitialized(vault_, address(asset_), delegate_);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IStrategy
    function totalValue() public view returns (uint256) {
        return idleBalance() + getExternalValue();
    }

    /// @inheritdoc IStrategy
    function idleBalance() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @inheritdoc IStrategy
    function getExternalValue() public view returns (uint256 total) {
        ValueSource[] storage sources = _valueSources;
        uint256 n = sources.length;
        for (uint256 i; i < n; ++i) {
            (bool ok, bytes memory ret) = sources[i].target.staticcall(sources[i].data);
            if (!ok || ret.length < 32) revert ValueSourceFailed(i);
            total += abi.decode(ret, (uint256));
        }
    }

    /// @inheritdoc IStrategy
    function valueSourceCount() external view returns (uint256) {
        return _valueSources.length;
    }

    /// @notice Returns the (target, data) tuple at index `i` in the value-source list.
    function valueSources(uint256 i) external view returns (ValueSource memory) {
        return _valueSources[i];
    }

    /// @notice Returns the current auto-deposit action config (empty if not set).
    function depositConfig() external view returns (ActionConfig memory) {
        return _depositConfig;
    }

    /// @notice Returns the current auto-withdraw action config (empty if not set).
    function withdrawConfig() external view returns (ActionConfig memory) {
        return _withdrawConfig;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IStrategy
    function setDelegate(address newDelegate) external onlyAdmin {
        if (newDelegate == address(0)) revert ZeroAddress();
        address old = delegate;
        delegate = newDelegate;
        emit DelegateUpdated(old, newDelegate);
    }

    /// @inheritdoc IStrategy
    function addAllowedAction(
        address target,
        bytes4 selector,
        uint16 recipientOffset
    ) external onlyAdmin {
        if (target == address(0)) revert ZeroAddress();
        if (target == address(asset)) revert TargetIsAsset();
        if (target == address(this)) revert TargetIsSelf();
        if (target == vault) revert TargetIsVault();
        AllowedAction storage cfg = allowedActions[target][selector];
        if (cfg.allowed) revert ActionAlreadyAllowed();
        cfg.allowed = true;
        cfg.recipientOffset = recipientOffset;
        emit AllowedActionAdded(target, selector, recipientOffset);
    }

    /// @inheritdoc IStrategy
    function removeAllowedAction(address target, bytes4 selector) external onlyAdmin {
        AllowedAction storage cfg = allowedActions[target][selector];
        if (!cfg.allowed) revert ActionAlreadyDisallowed();
        delete allowedActions[target][selector];
        emit AllowedActionRemoved(target, selector);
    }

    /// @inheritdoc IStrategy
    function setDepositConfig(
        address target,
        bytes calldata data,
        uint16 amountOffset
    ) external onlyAdmin {
        if (target == address(0)) revert ZeroAddress();
        if (target == address(this)) revert TargetIsSelf();
        if (target == vault) revert TargetIsVault();
        if (data.length < uint256(amountOffset) + 32) revert DataTooShort(data.length);
        _depositConfig = ActionConfig({target: target, data: data, amountOffset: amountOffset});
        emit DepositConfigSet(target);
    }

    /// @inheritdoc IStrategy
    function setWithdrawConfig(
        address target,
        bytes calldata data,
        uint16 amountOffset
    ) external onlyAdmin {
        if (target == address(0)) revert ZeroAddress();
        if (target == address(this)) revert TargetIsSelf();
        if (target == vault) revert TargetIsVault();
        if (data.length < uint256(amountOffset) + 32) revert DataTooShort(data.length);
        _withdrawConfig = ActionConfig({target: target, data: data, amountOffset: amountOffset});
        emit WithdrawConfigSet(target);
    }

    /// @inheritdoc IStrategy
    function removeDepositConfig() external onlyAdmin {
        delete _depositConfig;
        emit DepositConfigRemoved();
    }

    /// @inheritdoc IStrategy
    function removeWithdrawConfig() external onlyAdmin {
        delete _withdrawConfig;
        emit WithdrawConfigRemoved();
    }

    /// @inheritdoc IStrategy
    function addValueSource(address target, bytes calldata data) external onlyAdmin {
        if (target == address(0)) revert ZeroAddress();
        if (target == address(this)) revert TargetIsSelf();
        // sanity-call so misconfiguration fails loudly at admin time
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (!ok || ret.length < 32) revert ValueSourceFailed(_valueSources.length);
        _valueSources.push(ValueSource({target: target, data: data}));
        emit ValueSourceAdded(_valueSources.length - 1, target);
    }

    /// @inheritdoc IStrategy
    /// @dev Callable by admin OR delegate. Spender MUST be on the
    ///      admin-curated trustedSpenders allowlist — this is what contains
    ///      a compromised delegate: they can only ever hand the asset to a
    ///      protocol the admin has pre-vetted.
    ///      `forceApprove` handles non-standard tokens (USDT) that reject
    ///      allowance changes from a non-zero value.
    function approveToken(address token, address spender, uint256 amount) external onlyAdminOrDelegate {
        if (token == address(0) || spender == address(0)) revert ZeroAddress();
        if (spender == address(this)) revert TargetIsSelf();
        if (spender == vault) revert TargetIsVault();
        if (!trustedSpenders[spender]) revert SpenderNotTrusted(spender);
        IERC20(token).forceApprove(spender, amount);
        emit TokenApproved(token, spender, amount, msg.sender);
    }

    /// @inheritdoc IStrategy
    function setTrustedSpender(address spender, bool trusted) external onlyAdmin {
        if (spender == address(0)) revert ZeroAddress();
        if (spender == address(this)) revert TargetIsSelf();
        if (spender == vault) revert TargetIsVault();
        trustedSpenders[spender] = trusted;
        emit TrustedSpenderSet(spender, trusted);
    }

    /// @inheritdoc IStrategy
    function removeValueSource(uint256 index) external onlyAdmin {
        uint256 len = _valueSources.length;
        if (index >= len) revert ValueSourceIndexOutOfBounds(index);
        // shift left to preserve order
        for (uint256 i = index; i + 1 < len; ++i) {
            _valueSources[i] = _valueSources[i + 1];
        }
        _valueSources.pop();
        emit ValueSourceRemoved(index);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Vault-only
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IStrategy
    /// @dev The vault must transfer `amount` of asset to this contract BEFORE
    ///      calling pushFunds (the vault does this in its _autoDeploy / rebalance
    ///      helpers). If a deposit config is set, we run it to deploy the
    ///      freshly-arrived funds into the external protocol.
    function pushFunds(uint256 amount) external onlyVault nonReentrant {
        if (_depositConfig.target != address(0) && amount > 0) {
            bytes memory data = _patchAmount(_depositConfig.data, _depositConfig.amountOffset, amount);
            (bool ok, bytes memory ret) = _depositConfig.target.call(data);
            if (!ok) revert AutoDeployFailed(ret);
        }
        emit FundsPushed(amount);
    }

    /// @inheritdoc IStrategy
    function pullFunds(uint256 amount) external onlyVault nonReentrant returns (uint256 actual) {
        uint256 idle = asset.balanceOf(address(this));

        // If we don't have enough idle and a withdraw config is set, run it
        // to pull funds from the external protocol.
        if (idle < amount && _withdrawConfig.target != address(0)) {
            uint256 needed = amount - idle;
            uint256 external_ = getExternalValue();
            if (needed > external_) needed = external_;

            if (needed > 0) {
                bytes memory data = _patchAmount(
                    _withdrawConfig.data, _withdrawConfig.amountOffset, needed
                );
                (bool ok, bytes memory ret) = _withdrawConfig.target.call(data);
                if (!ok) revert AutoWithdrawFailed(ret);
                idle = asset.balanceOf(address(this));
            }
        }

        actual = idle < amount ? idle : amount;
        if (actual > 0) {
            asset.safeTransfer(vault, actual);
        }
        emit FundsPulled(amount, actual);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Delegate or Authority
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IStrategy
    /// @dev Validation chain mirrors the original Vault.executeStrategyAction:
    ///   1. caller is delegate or authority (via modifier)
    ///   2. data.length >= 4
    ///   3. selector whitelisted for this (target)
    ///   4. target is not asset, this, or vault
    ///   5. recipient check if recipientOffset != 0
    ///   6. snapshot caller's asset balance (anti-theft)
    ///   7. perform the call
    ///   8. caller's asset balance must not have increased
    function executeAction(
        address target,
        bytes calldata data
    ) external onlyDelegateOrAuthority nonReentrant returns (bytes memory result) {
        if (data.length < 4) revert DataTooShort(data.length);

        bytes4 selector = bytes4(data[0:4]);
        AllowedAction memory cfg = allowedActions[target][selector];
        if (!cfg.allowed) revert ActionNotAllowed(target, selector);

        if (target == address(asset)) revert TargetIsAsset();
        if (target == address(this)) revert TargetIsSelf();
        if (target == vault) revert TargetIsVault();

        if (cfg.recipientOffset != 0) {
            uint256 off = uint256(cfg.recipientOffset);
            if (data.length < off + 32) revert DataTooShort(data.length);
            address recipient = address(uint160(uint256(bytes32(data[off:off + 32]))));
            // Recipient must be the strategy itself — protocol receipts
            // (aTokens, shares, etc.) must accrue here, not to the delegate.
            if (recipient != address(this)) revert RecipientMustBeVault(recipient);
        }

        uint256 callerBefore = asset.balanceOf(msg.sender);

        bool ok;
        (ok, result) = target.call(data);
        if (!ok) revert CallFailed(result);

        uint256 callerAfter = asset.balanceOf(msg.sender);
        if (callerAfter > callerBefore) {
            revert AntiTheft(msg.sender, callerBefore, callerAfter);
        }

        unchecked {
            actionCount += 1;
        }
        emit ActionExecuted(target, selector, keccak256(data));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Copy a calldata template and overwrite the 32-byte word at
    ///      `offset` with `amount`. Used by pushFunds/pullFunds to patch
    ///      the amount into a pre-configured action template.
    function _patchAmount(
        bytes storage template,
        uint16 offset,
        uint256 amount
    ) internal pure returns (bytes memory data) {
        data = template; // copy to memory
        assembly {
            mstore(add(add(data, 0x20), offset), amount)
        }
    }
}
