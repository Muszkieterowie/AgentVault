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

/// @dev Self-contained 6-decimal asset stand-in for the demo. Public mint
///      so the deployer can hand out testnet balances freely.
contract DemoUSDC is ERC20 {
    constructor() ERC20("AgentVault Demo USDC", "avDemoUSDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function decimals() public pure override returns (uint8) { return 6; }
}

/// @notice Deploys the full E2E stack to Base Sepolia and wires it up so
///         the agent-driven flow (executeAction → pool.supply → yield drip
///         → user withdraw) works out-of-the-box. Deployer EOA holds every
///         role (admin, authority, agent) for a single-key demo.
contract DeployBaseSepolia is Script {
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

        vm.startBroadcast(deployerKey);

        // ── Core asset + vault ─────────────────────────────────────────────
        // Target-date deadline: 30 days out so the demo can comfortably
        // exercise deposit → yield drip → (warp or wait) → redeem within a
        // testnet session. Override via `VAULT_DEADLINE` env var if needed.
        uint256 deadline = _deadlineFromEnvOrDefault(block.timestamp + 30 days);
        console2.log("Vault deadline (unix):  ", deadline);

        DemoUSDC asset = new DemoUSDC();
        Vault vault = new Vault(
            IERC20(address(asset)),
            deployer,           // admin
            deployer,           // authority
            "AgentVault Demo USDC",
            "avDemoUSDC",
            deadline
        );

        // ── Aave V3 mock stack ─────────────────────────────────────────────
        MockAavePool pool = new MockAavePool(deployer);
        MockAToken aToken = new MockAToken(
            "Aave Demo USDC", "aDemoUSDC", 6, IERC20(address(asset)), address(pool)
        );
        MockVariableDebtToken debtToken = new MockVariableDebtToken(
            "Variable Debt Demo USDC", "vdDemoUSDC", 6, address(pool)
        );
        pool.registerReserve(address(asset), aToken, debtToken);

        // ── Strategy: deployer is the agent (delegate) too ─────────────────
        (, address strategyAddress) = vault.createStrategy(deployer);
        Strategy strategy = Strategy(strategyAddress);
        vault.setStrategyWeight(0, 10_000);

        // ── Whitelist + trust + approve ───────────────────────────────────
        strategy.setTrustedSpender(address(pool), true);
        strategy.approveToken(address(asset), address(pool), type(uint256).max);
        strategy.addAllowedAction(address(pool), pool.supply.selector, 68);

        // ── Auto-withdraw config: pool.withdraw(asset, <amount>, strategy) ─
        bytes memory withdrawTemplate = abi.encodeWithSelector(
            pool.withdraw.selector,
            address(asset),
            uint256(0),
            address(strategy)
        );
        strategy.setWithdrawConfig(address(pool), withdrawTemplate, 36);

        // ── Value source: aToken.balanceOf(strategy) ───────────────────────
        bytes memory balanceOfData = abi.encodeWithSelector(
            aToken.balanceOf.selector, address(strategy)
        );
        strategy.addValueSource(address(aToken), balanceOfData);

        // ── YieldDripper: 100 demo-USDC every 1 hour ───────────────────────
        YieldDripper dripper = new YieldDripper(
            IERC20(address(asset)), aToken, 100e6, 1 hours, deployer
        );

        // ── Seed funds ─────────────────────────────────────────────────────
        // 10,000 to the deployer so they can experiment with deposits.
        // 5,000 to the dripper so it has 50 hours of yield to stream.
        asset.mint(deployer, 10_000e6);
        asset.mint(address(dripper), 5_000e6);

        vm.stopBroadcast();

        // ── Log everything for follow-up wiring + verification ─────────────
        address strategyImpl = vault.STRATEGY_IMPLEMENTATION();
        console2.log("");
        console2.log("=== AgentVault Base Sepolia deployment ===");
        console2.log("DemoUSDC (asset):       ", address(asset));
        console2.log("Vault:                  ", address(vault));
        console2.log("Strategy implementation:", strategyImpl);
        console2.log("Strategy clone (id 0):  ", strategyAddress);
        console2.log("MockAavePool:           ", address(pool));
        console2.log("MockAToken:             ", address(aToken));
        console2.log("MockVariableDebtToken:  ", address(debtToken));
        console2.log("YieldDripper:           ", address(dripper));
    }

    /// @dev Read an optional `VAULT_DEADLINE` env var; default if unset.
    function _deadlineFromEnvOrDefault(uint256 fallback_) internal view returns (uint256) {
        try vm.envUint("VAULT_DEADLINE") returns (uint256 v) { return v; }
        catch { return fallback_; }
    }
}
