// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Vault} from "../src/Vault.sol";
import {Strategy} from "../src/Strategy.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {IStrategy} from "../src/interfaces/IStrategy.sol";

/// @dev Minimal 6-decimal ERC-20 standing in for USDC. Public `mint` so
///      tests can pre-fund actors without a deployer helper.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function decimals() public pure override returns (uint8) { return 6; }
}

/// @title Vault — core behaviour tests
/// @notice Covers deployment invariants, the ERC-4626 entry points, the
///         strategy factory + registry, role gating, auto-rebalance fan-out
///         on deposit/withdraw, authority-driven rebalancing, and permanent
///         strategy deactivation. Each test is self-contained: setUp deploys
///         a fresh vault and funds Alice + Bob with 1 M mUSDC.
contract VaultTest is Test {
    MockERC20 internal asset;
    Vault internal vault;

    // Actors. `admin` holds DEFAULT_ADMIN_ROLE; `authority` holds AUTHORITY_ROLE;
    // `agent` stands in for an AI-agent EOA used as a strategy delegate;
    // Alice + Bob are public users.
    address internal admin = address(0xA11CE);
    address internal authority = address(0xAABBCC);
    address internal alice = address(0xA1);
    address internal bob = address(0xB0B);
    address internal agent = address(0xDE1E6A7E);

    /// @dev Per-user initial balance. 1 M with 6 decimals = 1e12 raw units.
    uint256 internal constant INITIAL_BALANCE = 1_000_000e6;

    function setUp() public {
        asset = new MockERC20();
        vault = new Vault(IERC20(address(asset)), admin, authority, "AgentVault USDC", "avUSDC");
        asset.mint(alice, INITIAL_BALANCE);
        asset.mint(bob, INITIAL_BALANCE);
    }

    // ─── Deployment ─────────────────────────────────────────────────────────

    /// @dev Constructor must grant DEFAULT_ADMIN_ROLE to `admin`, AUTHORITY_ROLE
    ///      to `authority`, mirror authority in the convenience field, and
    ///      wire `asset()` for ERC-4626 accounting.
    function test_constructor_grantsRolesAndSetsAuthority() public view {
        assertTrue(IAccessControl(address(vault)).hasRole(0x00, admin));
        assertTrue(IAccessControl(address(vault)).hasRole(vault.AUTHORITY_ROLE(), authority));
        assertEq(vault.authority(), authority);
        assertEq(vault.asset(), address(asset));
    }

    /// @dev The singleton Strategy implementation must be deployed in the
    ///      vault constructor and its `initialized` flag must be true so
    ///      nobody can call initialize() on the implementation directly —
    ///      it is only usable through EIP-1167 clones.
    function test_constructor_deploysStrategyImplementation() public view {
        assertTrue(vault.STRATEGY_IMPLEMENTATION() != address(0));
        assertTrue(Strategy(vault.STRATEGY_IMPLEMENTATION()).initialized());
    }

    /// @dev Guard rail: passing address(0) for admin would brick the vault
    ///      (nobody could ever configure strategies), so the constructor
    ///      must revert early.
    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert(IVault.ZeroAddress.selector);
        new Vault(IERC20(address(asset)), address(0), authority, "x", "x");
    }

    // ─── Deposit / withdraw ─────────────────────────────────────────────────

    /// @dev Happy path for an empty-strategy vault: deposit mints shares,
    ///      assets sit idle in the vault (no strategy weight set), and a
    ///      redeem of all shares returns the user to their original balance
    ///      with no dust loss.
    function test_deposit_mintsSharesAndRoundtrips() public {
        uint256 amount = 100e6;
        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, alice);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), amount);
        assertEq(asset.balanceOf(address(vault)), amount);

        vm.prank(alice);
        uint256 assetsOut = vault.redeem(shares, alice, alice);
        assertEq(assetsOut, amount);
        assertEq(asset.balanceOf(alice), INITIAL_BALANCE);
    }

    /// @dev `_decimalsOffset = 6` blunts the donate-to-vault inflation attack
    ///      but must not meaningfully shift share price on a fresh deposit:
    ///      converting the minted shares back to assets should yield the
    ///      original deposit (±1 wei of rounding).
    function test_sharePrice_freshVaultNearOne() public {
        vm.startPrank(alice);
        asset.approve(address(vault), 1e6);
        vault.deposit(1e6, alice);
        vm.stopPrank();
        assertApproxEqAbs(vault.convertToAssets(vault.balanceOf(alice)), 1e6, 1);
    }

    // ─── Factory + roles ────────────────────────────────────────────────────

    /// @dev createStrategy must assign a monotonic id, register the clone
    ///      address, flip the active flag, and initialize the clone with
    ///      this vault + the supplied delegate.
    function test_createStrategy_byAdminRegistersAndActivates() public {
        vm.prank(admin);
        (uint256 strategyId, address strategyAddress) = vault.createStrategy(agent);
        assertEq(strategyId, 0);
        assertEq(vault.strategies(0), strategyAddress);
        assertTrue(vault.strategyActive(0));
        assertEq(vault.strategyCount(), 1);
        assertEq(Strategy(strategyAddress).delegate(), agent);
        assertEq(Strategy(strategyAddress).vault(), address(vault));
    }

    /// @dev createStrategy is `onlyRole(DEFAULT_ADMIN_ROLE)` — any other
    ///      caller must be rejected by AccessControl.
    function test_createStrategy_revertsForNonAdmin() public {
        vm.prank(bob);
        vm.expectRevert();
        vault.createStrategy(agent);
    }

    /// @dev A zero delegate would permanently lock `executeAction` out of
    ///      the strategy, so we reject at creation time.
    function test_createStrategy_revertsOnZeroDelegate() public {
        vm.prank(admin);
        vm.expectRevert(IVault.ZeroAddress.selector);
        vault.createStrategy(address(0));
    }

    /// @dev Per-strategy weight is basis-points-bounded. Anything above
    ///      10_000 (= 100%) is nonsensical and must revert.
    function test_setStrategyWeight_revertsIfAboveTenThousand() public {
        vm.prank(admin);
        vault.createStrategy(agent);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IVault.WeightTooHigh.selector, uint16(10_001)));
        vault.setStrategyWeight(0, 10_001);
    }

    /// @dev Rotating the authority must grant the role to the new address
    ///      AND revoke it from the old one — AUTHORITY_ROLE is a single-
    ///      seat role by design.
    function test_setAuthority_rotatesAuthorityRole() public {
        address newAuthority = address(0xBEEF);
        vm.prank(admin);
        vault.setAuthority(newAuthority);
        assertEq(vault.authority(), newAuthority);
        assertTrue(IAccessControl(address(vault)).hasRole(vault.AUTHORITY_ROLE(), newAuthority));
        assertFalse(IAccessControl(address(vault)).hasRole(vault.AUTHORITY_ROLE(), authority));
    }

    // ─── Auto-rebalance on deposit ──────────────────────────────────────────

    /// @dev On deposit the vault fans assets out by absolute weight:
    ///      60% → strategy0, 30% → strategy1, 10% residual left idle.
    ///      Residual is the intentional liquidity buffer when Σweights < 10_000.
    function test_deposit_fansOutToStrategiesByWeight() public {
        vm.startPrank(admin);
        (, address strategy0) = vault.createStrategy(agent);
        (, address strategy1) = vault.createStrategy(agent);
        vault.setStrategyWeight(0, 6000);
        vault.setStrategyWeight(1, 3000);
        vm.stopPrank();

        uint256 amount = 1_000e6;
        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        vault.deposit(amount, alice);
        vm.stopPrank();

        assertEq(asset.balanceOf(strategy0), 600e6);
        assertEq(asset.balanceOf(strategy1), 300e6);
        assertEq(asset.balanceOf(address(vault)), 100e6);
        assertEq(vault.totalAssets(), amount);
    }

    /// @dev When a user withdraws more than is idle, the vault must pull the
    ///      deficit from active strategies (in registration order) to cover
    ///      the request. Here 100% was routed to strategy0, so the withdraw
    ///      path forces a strategy pull and must return Alice to her starting
    ///      balance.
    function test_withdraw_pullsFromStrategiesWhenIdleInsufficient() public {
        vm.startPrank(admin);
        (, address strategy0) = vault.createStrategy(agent);
        vault.setStrategyWeight(0, 10_000);
        vm.stopPrank();

        uint256 amount = 500e6;
        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        vault.deposit(amount, alice);
        vm.stopPrank();

        assertEq(asset.balanceOf(strategy0), amount);
        assertEq(asset.balanceOf(address(vault)), 0);

        vm.prank(alice);
        vault.withdraw(amount, alice, alice);
        assertEq(asset.balanceOf(alice), INITIAL_BALANCE);
    }

    // ─── Authority rebalance ────────────────────────────────────────────────

    /// @dev Positive delta = push from idle into the strategy. Weight is 0
    ///      here so the deposit stays idle; the authority then explicitly
    ///      moves 400 of the 1000 over to strategy0.
    function test_rebalance_positiveDeltaPushesFromIdle() public {
        vm.prank(admin);
        (, address strategy0) = vault.createStrategy(agent);
        vm.startPrank(alice);
        asset.approve(address(vault), 1_000e6);
        vault.deposit(1_000e6, alice);
        vm.stopPrank();

        vm.prank(authority);
        uint256 movedAmount = vault.rebalance(0, int256(400e6));
        assertEq(movedAmount, 400e6);
        assertEq(asset.balanceOf(strategy0), 400e6);
        assertEq(asset.balanceOf(address(vault)), 600e6);
    }

    /// @dev Negative delta = pull from strategy back to vault idle. Whole
    ///      deposit routed to strategy0 via weight=10_000; authority reclaims
    ///      300 and we verify both balances reconcile.
    function test_rebalance_negativeDeltaPullsFromStrategy() public {
        vm.startPrank(admin);
        (, address strategy0) = vault.createStrategy(agent);
        vault.setStrategyWeight(0, 10_000);
        vm.stopPrank();

        vm.startPrank(alice);
        asset.approve(address(vault), 1_000e6);
        vault.deposit(1_000e6, alice);
        vm.stopPrank();

        assertEq(asset.balanceOf(strategy0), 1_000e6);

        vm.prank(authority);
        uint256 movedAmount = vault.rebalance(0, -int256(300e6));
        assertEq(movedAmount, 300e6);
        assertEq(asset.balanceOf(strategy0), 700e6);
        assertEq(asset.balanceOf(address(vault)), 300e6);
    }

    /// @dev rebalance is `onlyRole(AUTHORITY_ROLE)`. Admin-only power to
    ///      *configure* strategies is deliberately separated from the
    ///      authority power to *move funds*.
    function test_rebalance_revertsForNonAuthority() public {
        vm.prank(admin);
        vault.createStrategy(agent);
        vm.prank(bob);
        vm.expectRevert();
        vault.rebalance(0, 1);
    }

    /// @dev Positive delta > idle balance must revert with the explicit
    ///      InsufficientIdle error rather than silently underflowing or
    ///      transferring a partial amount.
    function test_rebalance_revertsOnInsufficientIdle() public {
        vm.prank(admin);
        vault.createStrategy(agent);
        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(IVault.InsufficientIdle.selector, 1, 0));
        vault.rebalance(0, 1);
    }

    // ─── Deactivate ─────────────────────────────────────────────────────────

    /// @dev Deactivation is permanent — so the vault refuses while the
    ///      strategy still holds value. Operator must drain via
    ///      rebalance(id, -delta) first. Prevents stranding funds in a
    ///      disabled clone.
    function test_deactivateStrategy_revertsIfFundsRemain() public {
        vm.startPrank(admin);
        (, address strategy0) = vault.createStrategy(agent);
        vault.setStrategyWeight(0, 10_000);
        vm.stopPrank();

        vm.startPrank(alice);
        asset.approve(address(vault), 100e6);
        vault.deposit(100e6, alice);
        vm.stopPrank();

        assertEq(asset.balanceOf(strategy0), 100e6);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IVault.StrategyStillHoldsFunds.selector, uint256(0), uint256(100e6)));
        vault.deactivateStrategy(0);
    }

    /// @dev Empty strategy deactivates cleanly and flips the active flag
    ///      off. There is intentionally no reactivation path.
    function test_deactivateStrategy_succeedsWhenDrained() public {
        vm.prank(admin);
        vault.createStrategy(agent);
        vm.prank(admin);
        vault.deactivateStrategy(0);
        assertFalse(vault.strategyActive(0));
    }
}
