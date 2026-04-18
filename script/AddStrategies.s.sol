// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vault} from "../src/Vault.sol";
import {Strategy} from "../src/Strategy.sol";
import {MockAavePool} from "../src/mocks/MockAavePool.sol";
import {MockAToken} from "../src/mocks/MockAToken.sol";

/// @notice Adds strategies to the already-deployed Base Sepolia vaults:
///         - ETHSilesia: one new strategy (id 1)
///         - ETHWarsaw:  two new strategies (ids 1 and 2)
///         Each new strategy is wired the same way as strategy 0 (trusted
///         spender, approve, allowed pool.supply, withdraw config, aToken
///         value source) so it's immediately usable. Weights are reshuffled
///         so each vault's active strategies sum to exactly 10_000 bps.
///         Addresses are taken from deployments/base-sepolia.md.
contract AddStrategies is Script {
    // ── Shared infrastructure (Base Sepolia) ────────────────────────────────
    address internal constant ASSET  = 0xEAE8C41253197440c84669982b84463cb3410E62;
    address internal constant POOL   = 0xA3269593C784Ae3cf068fEfBCe15851C0895e738;
    address internal constant ATOKEN = 0xda1439a46687b8494c42e4d91bF1d69364D65E4A;

    // ── Vault #1 - ETHSilesia ───────────────────────────────────────────────
    address internal constant VAULT_SILESIA = 0xBaCF3F8237BAbFF700B762561A3cCF474f6688A8;

    // ── Vault #2 - ETHWarsaw ────────────────────────────────────────────────
    address internal constant VAULT_WARSAW  = 0x26E20946d273d6B3d17094744C9C3d648DE7F425;

    function run() external {
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

        // ── ETHSilesia: add strategy id 1, split 60/40 ─────────────────────
        address silesiaStrat1 = _addAndWireStrategy(VAULT_SILESIA, deployer);
        Vault(VAULT_SILESIA).setStrategyWeight(0, 6_000);
        Vault(VAULT_SILESIA).setStrategyWeight(1, 4_000);

        // ── ETHWarsaw: add strategy ids 1 and 2, split 50/30/20 ────────────
        address warsawStrat1 = _addAndWireStrategy(VAULT_WARSAW, deployer);
        address warsawStrat2 = _addAndWireStrategy(VAULT_WARSAW, deployer);
        Vault(VAULT_WARSAW).setStrategyWeight(0, 5_000);
        Vault(VAULT_WARSAW).setStrategyWeight(1, 3_000);
        Vault(VAULT_WARSAW).setStrategyWeight(2, 2_000);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== ETHSilesia - new strategy ===");
        console2.log("Strategy id 1:           ", silesiaStrat1);
        console2.log("Weights: 0=6000, 1=4000  (sum=10000)");
        console2.log("");
        console2.log("=== ETHWarsaw  - new strategies ===");
        console2.log("Strategy id 1:           ", warsawStrat1);
        console2.log("Strategy id 2:           ", warsawStrat2);
        console2.log("Weights: 0=5000, 1=3000, 2=2000  (sum=10000)");
    }

    /// @dev Creates a new strategy on `vaultAddr` with `delegate_` as the
    ///      agent, then mirrors strategy 0's admin wiring: trusted spender,
    ///      max-approve the pool, whitelist pool.supply (recipientOffset=68),
    ///      set the auto-withdraw template (amountOffset=36), and register
    ///      aToken.balanceOf(strategy) as the value source.
    function _addAndWireStrategy(address vaultAddr, address delegate_)
        internal
        returns (address strategyAddress)
    {
        Vault vault = Vault(vaultAddr);
        MockAavePool pool = MockAavePool(POOL);
        MockAToken aToken = MockAToken(ATOKEN);

        (, strategyAddress) = vault.createStrategy(delegate_);
        Strategy strategy = Strategy(strategyAddress);

        strategy.setTrustedSpender(POOL, true);
        strategy.approveToken(ASSET, POOL, type(uint256).max);
        strategy.addAllowedAction(POOL, pool.supply.selector, 68);

        bytes memory withdrawTemplate = abi.encodeWithSelector(
            pool.withdraw.selector, ASSET, uint256(0), strategyAddress
        );
        strategy.setWithdrawConfig(POOL, withdrawTemplate, 36);

        bytes memory balanceOfData = abi.encodeWithSelector(
            aToken.balanceOf.selector, strategyAddress
        );
        strategy.addValueSource(ATOKEN, balanceOfData);
    }
}
