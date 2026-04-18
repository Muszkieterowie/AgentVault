// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vault} from "../src/Vault.sol";
import {Strategy} from "../src/Strategy.sol";
import {MockAavePool} from "../src/mocks/MockAavePool.sol";
import {MockAToken} from "../src/mocks/MockAToken.sol";
import {MockVariableDebtToken} from "../src/mocks/MockVariableDebtToken.sol";
import {YieldDripper} from "../src/mocks/YieldDripper.sol";

/// @dev Minimal 6-decimal ERC-20 standing in for USDC.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function decimals() public pure override returns (uint8) { return 6; }
}

/// @title E2E — agent-driven deposit + yield + auto-withdraw
/// @notice End-to-end scenario proving the full operational model:
///           - Admin configures the strategy: approveToken, whitelists
///             pool.supply as an allowed action, registers the value source,
///             sets an auto-withdraw config so users can always exit.
///           - Two users deposit into the vault — funds arrive at the
///             strategy as IDLE (no deposit config; agent controls timing).
///           - The AGENT (delegate EOA) calls executeAction(pool.supply, ...)
///             to deploy the strategy's idle asset into the mock Aave pool,
///             receiving aTokens. This is the "AI agent steers strategy"
///             flow that the whole role model was designed around.
///           - YieldDripper streams underlying into MockAToken — rebases
///             every aToken holder up pro-rata.
///           - One user redeems all shares: vault pulls from the strategy,
///             which has no idle, so its admin-configured withdraw config
///             fires pool.withdraw to liquidate aToken → asset → user.
///           - The redeeming user receives MORE than they deposited; the
///             remaining user's position value has also grown.
contract E2EYieldTest is Test {
    // ─── Actors ─────────────────────────────────────────────────────────────
    address internal admin = address(0xA11CE);
    address internal authority = address(0xAABBCC);
    address internal agent = address(0xDE1E6A7E);   // AI agent EOA / delegate
    address internal alice = address(0xA1);
    address internal bob = address(0xB0B);

    // ─── Contracts ──────────────────────────────────────────────────────────
    MockERC20 internal asset;
    Vault internal vault;
    Strategy internal strategy;
    MockAavePool internal pool;
    MockAToken internal aToken;
    MockVariableDebtToken internal debtToken;
    YieldDripper internal dripper;

    // ─── Sized for clean 6-decimal arithmetic ───────────────────────────────
    uint256 internal constant ALICE_DEPOSIT = 1_000e6; // 1,000 mUSDC
    uint256 internal constant BOB_DEPOSIT   = 2_000e6; // 2,000 mUSDC
    uint256 internal constant YIELD_AMOUNT  =   300e6; // 300 mUSDC yield drip

    function setUp() public {
        // ── Core token + vault ─────────────────────────────────────────────
        asset = new MockERC20();
        vault = new Vault(IERC20(address(asset)), admin, authority, "AgentVault USDC", "avUSDC");

        asset.mint(alice, ALICE_DEPOSIT);
        asset.mint(bob, BOB_DEPOSIT);

        // ── Aave V3 mock stack ─────────────────────────────────────────────
        pool = new MockAavePool(admin);
        aToken = new MockAToken("Mock aUSDC", "maUSDC", 6, IERC20(address(asset)), address(pool));
        debtToken = new MockVariableDebtToken("Mock debtUSDC", "mdUSDC", 6, address(pool));
        vm.prank(admin);
        pool.registerReserve(address(asset), aToken, debtToken);

        // ── Strategy: 100% weight so every deposit lands in the strategy ───
        // No deposit config is set — the agent decides when to deploy idle.
        vm.prank(admin);
        (, address strategyAddress) = vault.createStrategy(agent);
        strategy = Strategy(strategyAddress);
        vm.prank(admin);
        vault.setStrategyWeight(0, 10_000);

        // ── Admin setup #1a: mark the pool as a trusted spender ────────────
        // Trusted-spender allowlist is admin-only; it's the trust boundary
        // that lets us safely give the AGENT (delegate) permission to call
        // approveToken. Without this, even admin would fail (approveToken
        // requires spender ∈ trustedSpenders — uniform rule).
        vm.prank(admin);
        strategy.setTrustedSpender(address(pool), true);

        // ── Admin setup #1b: AGENT approves the pool ───────────────────────
        // The agent (delegate) calls approveToken — proving the full
        // operational flow: once the admin has set the trust boundary, the
        // agent can bump allowances on its own to interact with the
        // pre-vetted protocol without another admin signature.
        vm.prank(agent);
        strategy.approveToken(address(asset), address(pool), type(uint256).max);

        // ── Admin setup #2: whitelist the agent's allowed action ───────────
        // pool.supply(address asset, uint256 amount, address onBehalfOf, uint16 ref)
        // calldata layout (132 bytes total):
        //   [0..4)    selector
        //   [4..36)   asset
        //   [36..68)  amount
        //   [68..100) onBehalfOf   ← recipientOffset = 68; executeAction
        //                            will reject any calldata whose
        //                            onBehalfOf is not the strategy itself
        //   [100..132) referralCode
        vm.prank(admin);
        strategy.addAllowedAction(address(pool), pool.supply.selector, 68);

        // ── Admin setup #3: auto-withdraw config ───────────────────────────
        // User redemptions flow vault → strategy.pullFunds(); if idle is
        // short, pullFunds runs this pre-approved template as a plain .call.
        // pool.withdraw(address asset, uint256 amount, address to).
        //   [0..4)    selector
        //   [4..36)   asset
        //   [36..68)  amount       ← amountOffset = 36 (patched at runtime)
        //   [68..100) to           ← hardcoded to strategy so funds return
        //                            HERE (not to whoever triggered the user
        //                            withdrawal)
        bytes memory withdrawTemplate = abi.encodeWithSelector(
            pool.withdraw.selector,
            address(asset),
            uint256(0),
            address(strategy)
        );
        vm.prank(admin);
        strategy.setWithdrawConfig(address(pool), withdrawTemplate, 36);

        // ── Admin setup #4: value source = aToken.balanceOf(strategy) ──────
        // Makes the rebased aToken balance visible to vault.totalAssets()
        // so share price accurately reflects accrued yield.
        bytes memory balanceOfData = abi.encodeWithSelector(aToken.balanceOf.selector, address(strategy));
        vm.prank(admin);
        strategy.addValueSource(address(aToken), balanceOfData);

        // ── YieldDripper: streams 300 mUSDC into aToken after 1 hour ───────
        dripper = new YieldDripper(IERC20(address(asset)), aToken, YIELD_AMOUNT, 1 hours, admin);
        asset.mint(address(dripper), YIELD_AMOUNT);
    }

    /// @notice Full agent-driven E2E.
    function test_e2e_agentSuppliesYieldAccruesAliceExitsInProfit() public {
        // ── Step 1. Alice deposits 1,000 ───────────────────────────────────
        // No deposit config, so funds simply land in the strategy as idle.
        vm.startPrank(alice);
        asset.approve(address(vault), ALICE_DEPOSIT);
        uint256 aliceShares = vault.deposit(ALICE_DEPOSIT, alice);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(strategy)), ALICE_DEPOSIT, "alice deposit sits idle in strategy");
        assertEq(aToken.balanceOf(address(strategy)), 0, "no aToken until agent acts");
        assertEq(vault.totalAssets(), ALICE_DEPOSIT, "TVL reflects idle");
        assertGt(aliceShares, 0, "shares minted");

        // ── Step 2. Bob deposits 2,000 ─────────────────────────────────────
        vm.startPrank(bob);
        asset.approve(address(vault), BOB_DEPOSIT);
        uint256 bobShares = vault.deposit(BOB_DEPOSIT, bob);
        vm.stopPrank();

        assertEq(
            asset.balanceOf(address(strategy)),
            ALICE_DEPOSIT + BOB_DEPOSIT,
            "both deposits pooled as idle"
        );
        // Bob's 2x deposit → ~2x shares (tight tolerance because no yield yet).
        assertApproxEqRel(bobShares, aliceShares * 2, 1e15, "bob ~2x alice shares");

        // ── Step 3. AGENT deploys the idle stack into the mock Aave pool ───
        // This is the "AI agent steering the strategy" call: the delegate
        // EOA (agent) submits executeAction with a whitelisted selector.
        // Strategy:
        //   - checks caller is delegate/authority ✓
        //   - checks (pool, supply.selector) is whitelisted ✓
        //   - decodes onBehalfOf at offset 68, requires == strategy ✓
        //   - snapshots agent's asset balance (anti-theft) — agent receives
        //     no asset from the call, so the guard passes ✓
        //   - .call to pool.supply → pool pulls asset from strategy (thanks
        //     to the admin's approveToken) and mints aToken back here
        uint256 totalIdle = asset.balanceOf(address(strategy));
        bytes memory supplyData = abi.encodeWithSelector(
            pool.supply.selector,
            address(asset),
            totalIdle,
            address(strategy),    // onBehalfOf — must match strategy per recipientOffset=68
            uint16(0)
        );
        vm.prank(agent);
        strategy.executeAction(address(pool), supplyData);

        assertEq(asset.balanceOf(address(strategy)), 0, "agent drained idle into pool");
        assertEq(aToken.balanceOf(address(strategy)), totalIdle, "strategy holds aToken 1:1");
        assertEq(vault.totalAssets(), totalIdle, "TVL unchanged post-supply");

        // ── Step 4. Time passes; yield drips in ────────────────────────────
        vm.warp(block.timestamp + 1 hours + 1);
        assertTrue(dripper.isReady(), "dripper ready after interval");
        dripper.drip();

        assertEq(
            aToken.balanceOf(address(strategy)),
            ALICE_DEPOSIT + BOB_DEPOSIT + YIELD_AMOUNT,
            "aToken rebased up by full yield (strategy is only holder)"
        );
        assertEq(
            vault.totalAssets(),
            ALICE_DEPOSIT + BOB_DEPOSIT + YIELD_AMOUNT,
            "TVL captures yield via value source"
        );

        // ── Step 5. Alice redeems all her shares — must withdraw > 1,000 ──
        // Flow:
        //   1. vault.redeem burns Alice's shares
        //   2. _withdraw sees idle=0, calls _autoPullFromStrategies
        //   3. strategy.pullFunds has 0 idle, runs the withdraw config
        //      (admin-set pool.withdraw template, amountOffset=36)
        //   4. pool.withdraw burns strategy's aToken, transfers underlying
        //      back to strategy
        //   5. strategy transfers to vault, vault transfers to alice
        vm.prank(alice);
        uint256 aliceOut = vault.redeem(aliceShares, alice, alice);

        // CRITICAL: Alice got more than she put in.
        assertGt(aliceOut, ALICE_DEPOSIT, "ALICE GAINS: withdrew more than deposited");

        // Expected pro-rata share of the post-yield pot = 1/3 * 3,300 = 1,100.
        uint256 expectedAliceOut = (ALICE_DEPOSIT + BOB_DEPOSIT + YIELD_AMOUNT) * ALICE_DEPOSIT
            / (ALICE_DEPOSIT + BOB_DEPOSIT);
        assertApproxEqRel(aliceOut, expectedAliceOut, 1e16, "alice out ~1100"); // 1% tolerance

        assertEq(asset.balanceOf(alice), aliceOut, "alice wallet = withdrawn amount");

        // ── Step 6. Bob's remaining position also reflects yield ───────────
        // No one else deposited after yield, so the rest belongs to Bob.
        uint256 bobPosition = vault.convertToAssets(bobShares);
        assertGt(bobPosition, BOB_DEPOSIT, "BOB GAINS: position worth > deposit");

        uint256 expectedBobPosition = (ALICE_DEPOSIT + BOB_DEPOSIT + YIELD_AMOUNT) * BOB_DEPOSIT
            / (ALICE_DEPOSIT + BOB_DEPOSIT);
        assertApproxEqRel(bobPosition, expectedBobPosition, 1e16, "bob position ~2200");

        // System accounting still balances: remaining TVL ~= Bob's position.
        assertApproxEqRel(vault.totalAssets(), bobPosition, 1e16, "residual TVL ~ bob's position");
    }

    /// @notice Negative path: a non-delegate cannot drive the strategy even
    ///         through a whitelisted selector — proves the gate on
    ///         executeAction is independent of what the admin whitelisted.
    function test_e2e_outsiderCannotCallSupplyEvenIfWhitelisted() public {
        // Seed some idle first so a real call could theoretically succeed.
        vm.startPrank(alice);
        asset.approve(address(vault), ALICE_DEPOSIT);
        vault.deposit(ALICE_DEPOSIT, alice);
        vm.stopPrank();

        bytes memory supplyData = abi.encodeWithSelector(
            pool.supply.selector,
            address(asset),
            ALICE_DEPOSIT,
            address(strategy),
            uint16(0)
        );

        // Alice is not the delegate and holds no AUTHORITY_ROLE.
        vm.prank(alice);
        vm.expectRevert(); // NotDelegateNorAuthority(alice)
        strategy.executeAction(address(pool), supplyData);
    }

    /// @notice Negative path: the agent cannot grant allowance to an
    ///         untrusted address even though they CAN call approveToken —
    ///         the trustedSpenders allowlist (admin-only) is the guardrail.
    function test_e2e_agentCannotApproveUntrustedSpender() public {
        address evilSpender = address(0xDEADBEEF);
        vm.prank(agent);
        vm.expectRevert(); // SpenderNotTrusted(evilSpender)
        strategy.approveToken(address(asset), evilSpender, type(uint256).max);
    }

    /// @notice Negative path: if the agent tries to redirect the aToken
    ///         mint to their own address, recipientOffset blocks it before
    ///         the pool is even called.
    function test_e2e_agentCannotRedirectReceipts() public {
        vm.startPrank(alice);
        asset.approve(address(vault), ALICE_DEPOSIT);
        vault.deposit(ALICE_DEPOSIT, alice);
        vm.stopPrank();

        // onBehalfOf = agent (not strategy) → recipientOffset check reverts
        bytes memory attackData = abi.encodeWithSelector(
            pool.supply.selector,
            address(asset),
            ALICE_DEPOSIT,
            agent,            // WRONG — must equal strategy
            uint16(0)
        );
        vm.prank(agent);
        vm.expectRevert(); // RecipientMustBeVault(agent)
        strategy.executeAction(address(pool), attackData);
    }
}
