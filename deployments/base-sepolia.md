# AgentVault — Base Sepolia deployment

- **Network**: Base Sepolia
- **Chain ID**: 84532
- **Deployer / admin / authority / agent**: `0xf298dB641560E5b733C43181937207482ff79bC9`
- **Solc**: 0.8.30 (EVM version: prague)

This deployment ships **two target-date event vaults** that share a single
asset, mock Aave pool, and yield dripper.

## Shared infrastructure

| Contract | Address | Basescan |
| --- | --- | --- |
| DemoUSDC (asset, 6 dec) | `0xeae8c41253197440c84669982B84463cb3410E62` | [view](https://sepolia.basescan.org/address/0xeae8c41253197440c84669982B84463cb3410E62) |
| MockAavePool | `0x0D2dFFaFd9A1B0A8DCf2b37dE03eE6bC9DFC7fc3` | [view](https://sepolia.basescan.org/address/0x0D2dFFaFd9A1B0A8DCf2b37dE03eE6bC9DFC7fc3) |
| MockAToken (aDemoUSDC) | `0xE02ba4A93e60Fb14b54F4be96e3B84B6Ae77DD2c` | [view](https://sepolia.basescan.org/address/0xE02ba4A93e60Fb14b54F4be96e3B84B6Ae77DD2c) |
| MockVariableDebtToken | `0xc5e66419F10a26D66c4F76a7152EE92753A05029` | [view](https://sepolia.basescan.org/address/0xc5e66419F10a26D66c4F76a7152EE92753A05029) |
| YieldDripper | `0x44F3d81c3b21C57a820C3D2eFb168F7c4Fd5a517` | [view](https://sepolia.basescan.org/address/0x44F3d81c3b21C57a820C3D2eFb168F7c4Fd5a517) |

All contracts are source-verified on Basescan.

## Vault #1 — ETHSilesia (30-day deadline)

- **Deadline**: `1779105926` → **2026-05-18 14:05 UTC**
- **Share name / symbol**: `AgentVault ETHSilesia` / `avETHSilesia`

| Contract | Address | Basescan |
| --- | --- | --- |
| Vault | `0xBaCF3F8237BAbFF700B762561A3cCF474f6688A8` | [view](https://sepolia.basescan.org/address/0xBaCF3F8237BAbFF700B762561A3cCF474f6688A8) |
| Strategy implementation | `0xbE2c0aBdc927b37391865335A49227d439839441` | [view](https://sepolia.basescan.org/address/0xbE2c0aBdc927b37391865335A49227d439839441) |
| Strategy clone (id 0) | `0xDc728730E5bc238f845f96318C49A9F01e99C217` | [view](https://sepolia.basescan.org/address/0xDc728730E5bc238f845f96318C49A9F01e99C217) |

## Vault #2 — ETHWarsaw (60-day deadline)

- **Deadline**: `1781697926` → **2026-06-17 14:05 UTC**
- **Share name / symbol**: `AgentVault ETHWarsaw` / `avETHWarsaw`

| Contract | Address | Basescan |
| --- | --- | --- |
| Vault | `0x26E20946d273d6B3d17094744C9C3d648DE7F425` | [view](https://sepolia.basescan.org/address/0x26E20946d273d6B3d17094744C9C3d648DE7F425) |
| Strategy implementation | `0x56fF4C75bE854990E8a8708c21B75Aac2309cb77` | [view](https://sepolia.basescan.org/address/0x56fF4C75bE854990E8a8708c21B75Aac2309cb77) |
| Strategy clone (id 0) | `0xbf69d0cA0AcD1857C63047F3a75d3b0100869BEb` | [view](https://sepolia.basescan.org/address/0xbf69d0cA0AcD1857C63047F3a75d3b0100869BEb) |

## Pre-wired configuration (set during deploy, identical for both vaults)

- `pool.registerReserve(asset, aToken, debtToken)` — once, on the shared pool
- `vault.createStrategy(deployer)` → strategy id 0
- `vault.setStrategyWeight(0, 10_000)` — 100% of deposits fan out to strategy 0
- `strategy.setTrustedSpender(pool, true)`
- `strategy.approveToken(asset, pool, type(uint256).max)`
- `strategy.addAllowedAction(pool, supply.selector, recipientOffset=68)`
- `strategy.setWithdrawConfig(pool, withdraw(asset, <amount>, strategy), amountOffset=36)`
- `strategy.addValueSource(aToken, balanceOf(strategy))`
- `dripper`: 100 demo-USDC every 1 hour, seeded with 5,000 demo-USDC (50 hours of yield)
- Deployer minted 20,000 demo-USDC for testing both vaults

## Target-date behaviour (both vaults)

- **Before deadline**: `deposit` / `mint` open; `withdraw` / `redeem` revert with `VaultNotMatured`. Agent can call `executeAction` / `approveToken`.
- **At/after deadline**: `deposit` / `mint` revert with `VaultMatured`; `withdraw` / `redeem` open. Agent `executeAction` / `approveToken` **forbidden**. Anyone can call `vault.drainAllStrategies()` to sweep all funds from protocols back to idle in one transaction.
- Authority `rebalance` remains open in both phases.

## JSON

```json
{
  "chainId": 84532,
  "name": "base-sepolia",
  "deployer": "0xf298dB641560E5b733C43181937207482ff79bC9",
  "shared": {
    "asset":     "0xeae8c41253197440c84669982B84463cb3410E62",
    "pool":      "0x0D2dFFaFd9A1B0A8DCf2b37dE03eE6bC9DFC7fc3",
    "aToken":    "0xE02ba4A93e60Fb14b54F4be96e3B84B6Ae77DD2c",
    "debtToken": "0xc5e66419F10a26D66c4F76a7152EE92753A05029",
    "dripper":   "0x44F3d81c3b21C57a820C3D2eFb168F7c4Fd5a517"
  },
  "vaults": {
    "ETHSilesia": {
      "deadline": 1779105926,
      "deadlineUtc": "2026-05-18T14:05:00Z",
      "vault":                  "0xBaCF3F8237BAbFF700B762561A3cCF474f6688A8",
      "strategyImplementation": "0xbE2c0aBdc927b37391865335A49227d439839441",
      "strategy":               "0xDc728730E5bc238f845f96318C49A9F01e99C217",
      "shareSymbol": "avETHSilesia"
    },
    "ETHWarsaw": {
      "deadline": 1781697926,
      "deadlineUtc": "2026-06-17T14:05:00Z",
      "vault":                  "0x26E20946d273d6B3d17094744C9C3d648DE7F425",
      "strategyImplementation": "0x56fF4C75bE854990E8a8708c21B75Aac2309cb77",
      "strategy":               "0xbf69d0cA0AcD1857C63047F3a75d3b0100869BEb",
      "shareSymbol": "avETHWarsaw"
    }
  },
  "config": {
    "strategyWeightBps": 10000,
    "poolSupplySelectorOffsets": { "amount": 36, "recipient": 68 },
    "withdrawConfigAmountOffset": 36,
    "yieldDripper": { "amountPerDripUsdc6": 100000000, "intervalSeconds": 3600 }
  }
}
```

## Drive the E2E from the CLI

```bash
source .env
ASSET=0xeae8c41253197440c84669982B84463cb3410E62
POOL=0x0D2dFFaFd9A1B0A8DCf2b37dE03eE6bC9DFC7fc3
DRIPPER=0x44F3d81c3b21C57a820C3D2eFb168F7c4Fd5a517
RPC=$BASE_SEPOLIA_RPC_URL
PK=0x$PRIVATE_KEY
YOU=0xf298dB641560E5b733C43181937207482ff79bC9

# Pick a vault (ETHSilesia shown; swap the addresses for ETHWarsaw)
VAULT=0xBaCF3F8237BAbFF700B762561A3cCF474f6688A8
STRATEGY=0xDc728730E5bc238f845f96318C49A9F01e99C217

# 1. deposit 1,000 avDemoUSDC
cast send $ASSET "approve(address,uint256)" $VAULT 1000000000 --rpc-url $RPC --private-key $PK
cast send $VAULT "deposit(uint256,address)" 1000000000 $YOU --rpc-url $RPC --private-key $PK

# 2. agent deploys idle into the pool
cast send $STRATEGY "executeAction(address,bytes)" $POOL \
  $(cast calldata "supply(address,uint256,address,uint16)" $ASSET 1000000000 $STRATEGY 0) \
  --rpc-url $RPC --private-key $PK

# 3. wait ≥ 1h, then drip yield into the shared aToken
cast send $DRIPPER "drip()" --rpc-url $RPC --private-key $PK

# 4. after the vault's deadline: drain + redeem
cast send $VAULT "drainAllStrategies()" --rpc-url $RPC --private-key $PK
SHARES=$(cast call $VAULT "balanceOf(address)(uint256)" $YOU --rpc-url $RPC)
cast send $VAULT "redeem(uint256,address,address)" $SHARES $YOU $YOU --rpc-url $RPC --private-key $PK
```
