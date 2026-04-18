// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vault} from "../src/Vault.sol";
import {Strategy} from "../src/Strategy.sol";
import {IStrategy} from "../src/interfaces/IStrategy.sol";

/// @dev Minimal 6-decimal ERC-20 standing in for USDC. Public `mint` so
///      tests can pre-fund actors without a deployer helper.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function decimals() public pure override returns (uint8) { return 6; }
}

/// @dev Benign protocol stub that the tests whitelist as an executeAction
///      target. Exposes a plain two-arg `supply` call whose recipient slot
///      sits at calldata offset 36, exercising the recipientOffset check.
contract MockTarget {
    IERC20 public immutable ASSET;
    constructor(IERC20 asset_) { ASSET = asset_; }

    /// @dev Pulls `amount` from caller into this contract — the canonical
    ///      "deposit into a protocol" shape.
    function sink(uint256 amount) external {
        ASSET.transferFrom(msg.sender, address(this), amount);
    }

    /// @dev Sends `amount` from this contract to msg.sender (the strategy
    ///      when called via executeAction). Used to prove that the
    ///      anti-theft check only triggers on CALLER-balance increase, not
    ///      on strategy-balance increase.
    function steal(uint256 amount) external {
        ASSET.transfer(msg.sender, amount);
    }

    /// @dev Two-arg supply whose calldata layout is:
    ///        [0..4)   selector
    ///        [4..36)  amount
    ///        [36..68) recipient   → recipientOffset = 36
    ///      Used by test_executeAction_recipientOffsetEnforcesSelfAsRecipient.
    function supply(uint256 amount, address recipient) external {
        ASSET.transferFrom(msg.sender, recipient, amount);
    }
}

/// @title Strategy — per-strategy behaviour tests
/// @notice Covers clone initialization + locking, delegate/admin gating on
///         the admin surface, allowed-action whitelist management, the full
///         executeAction validation chain (auth → whitelist → target guard →
///         recipient offset → anti-theft), and vault-only funds movement.
contract StrategyTest is Test {
    MockERC20 internal asset;
    Vault internal vault;
    Strategy internal strategy;
    MockTarget internal target;

    // Actors mirror the Vault test suite. `outsider` stands in for any
    // address that holds neither DEFAULT_ADMIN_ROLE nor AUTHORITY_ROLE and
    // is not the strategy's delegate — used for the negative-path gates.
    address internal admin = address(0xA11CE);
    address internal authority = address(0xAABBCC);
    address internal agent = address(0xDE1E6A7E);
    address internal outsider = address(0xBAD);

    function setUp() public {
        asset = new MockERC20();
        vault = new Vault(IERC20(address(asset)), admin, authority, "AgentVault USDC", "avUSDC");
        target = new MockTarget(IERC20(address(asset)));

        vm.prank(admin);
        (, address strategyAddress) = vault.createStrategy(agent);
        strategy = Strategy(strategyAddress);
    }

    // ─── Initialization ─────────────────────────────────────────────────────

    /// @dev The clone must come out of createStrategy already bound to
    ///      (vault, asset, delegate) — these are storage, not immutables,
    ///      because EIP-1167 clones don't run the implementation's
    ///      constructor.
    function test_initialize_bindsVaultAssetDelegate() public view {
        assertEq(strategy.vault(), address(vault));
        assertEq(address(strategy.asset()), address(asset));
        assertEq(strategy.delegate(), agent);
        assertTrue(strategy.initialized());
    }

    /// @dev initialize() is a one-shot. Re-calling it would let anyone
    ///      re-bind vault/delegate on a live strategy, so it must revert.
    function test_initialize_cannotBeCalledTwice() public {
        vm.expectRevert(IStrategy.AlreadyInitialized.selector);
        strategy.initialize(address(vault), IERC20(address(asset)), agent);
    }

    /// @dev The implementation contract is locked in its constructor
    ///      (initialized = true), so nobody can use it directly as a
    ///      strategy — it is only reachable via Clones.clone.
    function test_implementation_isLocked() public {
        Strategy implementation = Strategy(vault.STRATEGY_IMPLEMENTATION());
        vm.expectRevert(IStrategy.AlreadyInitialized.selector);
        implementation.initialize(address(vault), IERC20(address(asset)), agent);
    }

    // ─── Admin ──────────────────────────────────────────────────────────────

    /// @dev Admin can rotate the AI-agent EOA on a live strategy without
    ///      redeploying the clone — the delegate field is mutable.
    function test_setDelegate_rotatesDelegate() public {
        address newAgent = address(0xB0B);
        vm.prank(admin);
        strategy.setDelegate(newAgent);
        assertEq(strategy.delegate(), newAgent);
    }

    /// @dev Strategy has no local role storage; admin checks are proxied to
    ///      the vault's AccessControl. Non-admin must hit NotAdmin.
    function test_setDelegate_revertsForNonAdmin() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IStrategy.NotAdmin.selector, outsider));
        strategy.setDelegate(address(0x1));
    }

    /// @dev addAllowedAction stores the (target, selector) → (allowed,
    ///      recipientOffset) tuple that executeAction later reads.
    function test_addAllowedAction_recordsTuple() public {
        vm.prank(admin);
        strategy.addAllowedAction(address(target), target.sink.selector, 0);
        (bool allowed, uint16 recipientOffset) = strategy.allowedActions(address(target), target.sink.selector);
        assertTrue(allowed);
        assertEq(recipientOffset, 0);
    }

    /// @dev The asset token is explicitly disallowed as a whitelist target.
    ///      Otherwise a delegate could call asset.transfer and drain the
    ///      strategy in a single whitelisted hop.
    function test_addAllowedAction_rejectsAssetTarget() public {
        vm.prank(admin);
        vm.expectRevert(IStrategy.TargetIsAsset.selector);
        strategy.addAllowedAction(address(asset), bytes4(0x12345678), 0);
    }

    /// @dev The whitelist is idempotent-only on first write. Re-adding an
    ///      already-allowed tuple reverts so the admin can't accidentally
    ///      change recipientOffset with a silent overwrite.
    function test_addAllowedAction_rejectsDuplicate() public {
        vm.startPrank(admin);
        strategy.addAllowedAction(address(target), target.sink.selector, 0);
        vm.expectRevert(IStrategy.ActionAlreadyAllowed.selector);
        strategy.addAllowedAction(address(target), target.sink.selector, 0);
        vm.stopPrank();
    }

    /// @dev removeAllowedAction clears both the `allowed` flag and the
    ///      stored recipient offset.
    function test_removeAllowedAction_clearsTuple() public {
        vm.startPrank(admin);
        strategy.addAllowedAction(address(target), target.sink.selector, 0);
        strategy.removeAllowedAction(address(target), target.sink.selector);
        vm.stopPrank();
        (bool allowed,) = strategy.allowedActions(address(target), target.sink.selector);
        assertFalse(allowed);
    }

    // ─── executeAction gating ───────────────────────────────────────────────

    /// @dev Gate 1: only the strategy's delegate OR any holder of
    ///      AUTHORITY_ROLE may call executeAction. A plain outsider
    ///      must be rejected before any downstream check runs.
    function test_executeAction_revertsForNonDelegate() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IStrategy.NotDelegateNorAuthority.selector, outsider));
        strategy.executeAction(address(target), abi.encodeWithSelector(target.sink.selector, uint256(1)));
    }

    /// @dev The authority can call executeAction as a break-glass override.
    ///      We prove this indirectly: with no whitelist entries set, the
    ///      call must fail on ActionNotAllowed (the NEXT gate), not on
    ///      NotDelegateNorAuthority — meaning the auth gate was passed.
    function test_executeAction_authorityCanOverride() public {
        vm.prank(authority);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategy.ActionNotAllowed.selector, address(target), target.sink.selector)
        );
        strategy.executeAction(address(target), abi.encodeWithSelector(target.sink.selector, uint256(1)));
    }

    /// @dev Gate 2: (target, selector) must be whitelisted. A legitimate
    ///      delegate calling an unwhitelisted target must still revert.
    function test_executeAction_revertsWhenSelectorNotAllowed() public {
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategy.ActionNotAllowed.selector, address(target), target.sink.selector)
        );
        strategy.executeAction(address(target), abi.encodeWithSelector(target.sink.selector, uint256(1)));
    }

    /// @dev Calldata under 4 bytes cannot carry a selector, so we fail fast
    ///      with DataTooShort rather than slicing undefined memory.
    function test_executeAction_revertsIfDataTooShort() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(IStrategy.DataTooShort.selector, uint256(3)));
        strategy.executeAction(address(target), hex"112233");
    }

    // ─── executeAction: recipient + anti-theft ──────────────────────────────

    /// @dev Gate 3: when recipientOffset ≠ 0, the decoded recipient field
    ///      in the calldata MUST equal `address(this)` (the strategy). This
    ///      pins protocol receipts (aTokens, LP shares, etc.) to the
    ///      strategy and blocks the delegate from redirecting them.
    ///      Here we pass `outsider` as the recipient and expect a revert.
    function test_executeAction_recipientOffsetEnforcesSelfAsRecipient() public {
        vm.prank(admin);
        strategy.addAllowedAction(address(target), target.supply.selector, 36);

        bytes memory data = abi.encodeWithSelector(target.supply.selector, uint256(0), outsider);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(IStrategy.RecipientMustBeVault.selector, outsider));
        strategy.executeAction(address(target), data);
    }

    /// @dev Gate 4 (anti-theft): the caller's asset balance snapshot taken
    ///      around the external call must not increase. Here a MaliciousTarget
    ///      sends 10 units to tx.origin — which we force-equal to the agent
    ///      via the two-arg vm.prank form. The post-call balance grows, so
    ///      the guard must revert with AntiTheft(agent, 0, 10).
    function test_executeAction_antiTheftGuardTripsWhenAgentReceivesAsset() public {
        MaliciousTarget maliciousTarget = new MaliciousTarget(IERC20(address(asset)));
        asset.mint(address(maliciousTarget), 50e6);
        vm.prank(admin);
        strategy.addAllowedAction(address(maliciousTarget), maliciousTarget.stealToCaller.selector, 0);

        vm.prank(agent, agent); // msg.sender = tx.origin = agent
        vm.expectRevert(
            abi.encodeWithSelector(IStrategy.AntiTheft.selector, agent, uint256(0), uint256(10))
        );
        strategy.executeAction(
            address(maliciousTarget),
            abi.encodeWithSelector(maliciousTarget.stealToCaller.selector, uint256(10))
        );
    }

    // ─── pushFunds / pullFunds gated to vault ───────────────────────────────

    /// @dev pushFunds is the only way tokens enter the strategy's idle
    ///      accounting path, so only the vault may call it — any other
    ///      caller (including the delegate or admin) must revert.
    function test_pushFunds_revertsForNonVault() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IStrategy.NotVault.selector, outsider));
        strategy.pushFunds(1);
    }

    /// @dev Symmetric guard on the withdraw path. If non-vault callers could
    ///      trigger pullFunds they could drain the strategy back to the
    ///      vault without going through the ERC-4626 accounting.
    function test_pullFunds_revertsForNonVault() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(IStrategy.NotVault.selector, outsider));
        strategy.pullFunds(1);
    }
}

/// @dev Adversarial protocol stub: any call to stealToCaller forwards asset
///      to tx.origin. In the anti-theft test we prank tx.origin = agent,
///      which makes the agent's balance grow across the external call and
///      must trip the Strategy.executeAction guard.
contract MaliciousTarget {
    IERC20 public immutable ASSET;
    constructor(IERC20 asset_) { ASSET = asset_; }
    function stealToCaller(uint256 amount) external {
        ASSET.transfer(tx.origin, amount);
    }
}
