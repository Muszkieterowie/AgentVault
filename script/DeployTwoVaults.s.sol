// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vault} from "../src/Vault.sol";
import {Strategy} from "../src/Strategy.sol";
import {MockAavePool} from "../src/mocks/MockAavePool.sol";
import {MockAToken} from "../src/mocks/MockAToken.sol";
import {MockVariableDebtToken} from "../src/mocks/MockVariableDebtToken.sol";
import {YieldDripper} from "../src/mocks/YieldDripper.sol";

/// @dev 6-decimal demo asset. Shared by both event vaults — users hold a
///      single balance and choose which event they want to fund.
contract DemoUSDC is ERC20 {
    constructor() ERC20("AgentVault Demo USDC", "avDemoUSDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function decimals() public pure override returns (uint8) { return 6; }
}

/// @notice Deploys two target-date vaults sharing a single demo-USDC asset
///         and a single mock Aave stack:
///           - **ETHSilesia** — deadline = now + 30 days
///           - **ETHWarsaw**  — deadline = now + 60 days
///         Each vault gets its own Strategy clone pre-wired for the shared
///         pool (trusted spender, approval, whitelisted supply, withdraw
///         config, value source). Deployer holds admin/authority/agent on
///         both so the full agent flow can be driven from a single key.
contract DeployTwoVaults is Script {
    struct StackAddrs {
        address vault;
        address strategyImpl;
        address strategy;
    }

    function run() external {
        // Accept PRIVATE_KEY with or without the 0x prefix.
        string memory raw = vm.envString("PRIVATE_KEY");
        bytes memory rawBytes = bytes(raw);
        if (rawBytes.length >= 2 && rawBytes[0] != "0") {
            raw = string.concat("0x", raw);
        } else if (rawBytes.length >= 2 && rawBytes[1] != "x" && rawBytes[1] != "X") {
            raw = string.concat("0x", raw);
        }
        uint256 deployerKey = vm.parseUint(raw);
        address deployer = vm.addr(deployerKey);

        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);

        uint256 silesiaDeadline = block.timestamp + 30 days;
        uint256 warsawDeadline = block.timestamp + 60 days;

        vm.startBroadcast(deployerKey);

        // ── Shared infrastructure ─────────────────────────────────────────
        DemoUSDC asset = new DemoUSDC();
        MockAavePool pool = new MockAavePool(deployer);
        MockAToken aToken = new MockAToken(
            "Aave Demo USDC", "aDemoUSDC", 6, IERC20(address(asset)), address(pool)
        );
        MockVariableDebtToken debtToken = new MockVariableDebtToken(
            "Variable Debt Demo USDC", "vdDemoUSDC", 6, address(pool)
        );
        pool.registerReserve(address(asset), aToken, debtToken);

        // Single dripper feeding the shared aToken. Both vaults' strategies
        // hold aToken and will share yield pro-rata to their balance.
        YieldDripper dripper = new YieldDripper(
            IERC20(address(asset)), aToken, 100e6, 1 hours, deployer
        );

        // ── Vault #1 — ETHSilesia (30 day deadline) ───────────────────────
        StackAddrs memory silesia = _deployVaultStack(
            asset, pool, aToken, deployer,
            "AgentVault ETHSilesia", "avETHSilesia",
            silesiaDeadline
        );

        // ── Vault #2 — ETHWarsaw (60 day deadline) ────────────────────────
        StackAddrs memory warsaw = _deployVaultStack(
            asset, pool, aToken, deployer,
            "AgentVault ETHWarsaw", "avETHWarsaw",
            warsawDeadline
        );

        // ── Seed funds ─────────────────────────────────────────────────────
        // 20,000 to deployer so both vaults can be exercised; 5,000 seeds
        // the shared dripper (50 hours of 100-USDC drips).
        asset.mint(deployer, 20_000e6);
        asset.mint(address(dripper), 5_000e6);

        vm.stopBroadcast();

        // ── Log everything ────────────────────────────────────────────────
        console2.log("");
        console2.log("=== Shared infrastructure ===");
        console2.log("DemoUSDC (asset):        ", address(asset));
        console2.log("MockAavePool:            ", address(pool));
        console2.log("MockAToken:              ", address(aToken));
        console2.log("MockVariableDebtToken:   ", address(debtToken));
        console2.log("YieldDripper:            ", address(dripper));
        console2.log("");
        console2.log("=== Vault #1 - ETHSilesia (30d) ===");
        console2.log("Deadline (unix):         ", silesiaDeadline);
        console2.log("Vault:                   ", silesia.vault);
        console2.log("Strategy implementation: ", silesia.strategyImpl);
        console2.log("Strategy clone (id 0):   ", silesia.strategy);
        console2.log("");
        console2.log("=== Vault #2 - ETHWarsaw (60d) ===");
        console2.log("Deadline (unix):         ", warsawDeadline);
        console2.log("Vault:                   ", warsaw.vault);
        console2.log("Strategy implementation: ", warsaw.strategyImpl);
        console2.log("Strategy clone (id 0):   ", warsaw.strategy);
    }

    /// @dev Deploy a single vault, create its strategy, and wire up all
    ///      admin config so the agent-driven E2E flow works out-of-the-box.
    function _deployVaultStack(
        DemoUSDC asset,
        MockAavePool pool,
        MockAToken aToken,
        address deployer,
        string memory name_,
        string memory symbol_,
        uint256 deadline_
    ) internal returns (StackAddrs memory out) {
        Vault vault = new Vault(
            IERC20(address(asset)), deployer, deployer, name_, symbol_, deadline_
        );
        (, address strategyAddress) = vault.createStrategy(deployer);
        Strategy strategy = Strategy(strategyAddress);
        vault.setStrategyWeight(0, 10_000);

        strategy.setTrustedSpender(address(pool), true);
        strategy.approveToken(address(asset), address(pool), type(uint256).max);
        strategy.addAllowedAction(address(pool), pool.supply.selector, 68);

        bytes memory withdrawTemplate = abi.encodeWithSelector(
            pool.withdraw.selector, address(asset), uint256(0), address(strategy)
        );
        strategy.setWithdrawConfig(address(pool), withdrawTemplate, 36);

        bytes memory balanceOfData = abi.encodeWithSelector(
            aToken.balanceOf.selector, address(strategy)
        );
        strategy.addValueSource(address(aToken), balanceOfData);

        out = StackAddrs({
            vault: address(vault),
            strategyImpl: vault.STRATEGY_IMPLEMENTATION(),
            strategy: strategyAddress
        });
    }
}
