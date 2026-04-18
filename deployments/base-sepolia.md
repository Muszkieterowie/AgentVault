# AgentVault — Base Sepolia deployment

- **Network**: Base Sepolia
- **Chain ID**: 84532
- **Deployer / admin / authority / agent**: `0xf298dB641560E5b733C43181937207482ff79bC9`
- **Solc**: 0.8.30 (EVM version: prague)
- **Source commit**: see `git log` (this manifest is updated alongside any redeploy)

## Contracts

| Contract | Address | Basescan |
| --- | --- | --- |
| DemoUSDC (asset, 6 dec) | `0x6a3601942C2F17370E87a2834317BFC24E0e9E70` | [view](https://sepolia.basescan.org/address/0x6a3601942C2F17370E87a2834317BFC24E0e9E70) |
| Vault (ERC-4626) | `0x21c5b7a26a554748c1c557c50e78f5f178e5ba39` | [view](https://sepolia.basescan.org/address/0x21c5b7a26a554748c1c557c50e78f5f178e5ba39) |
| Strategy implementation | `0x11D310d30E32275b9F82e671a3b542a09B26c058` | [view](https://sepolia.basescan.org/address/0x11D310d30E32275b9F82e671a3b542a09B26c058) |
| Strategy clone (id 0) | `0xbdf36639462Cf6174Dc895514DEbA2116850992E` | [view](https://sepolia.basescan.org/address/0xbdf36639462Cf6174Dc895514DEbA2116850992E) |
| MockAavePool | `0x4CE0Ee1Ed18C2f0D9E5D45ed037380e482ba3C1A` | [view](https://sepolia.basescan.org/address/0x4CE0Ee1Ed18C2f0D9E5D45ed037380e482ba3C1A) |
| MockAToken (aDemoUSDC) | `0xEb6566A83ec76Ed023370bAefBE5c0bc402243e5` | [view](https://sepolia.basescan.org/address/0xEb6566A83ec76Ed023370bAefBE5c0bc402243e5) |
| MockVariableDebtToken | `0x8f6193f8737913216A6144B18a6E9B4AbDDf8d92` | [view](https://sepolia.basescan.org/address/0x8f6193f8737913216A6144B18a6E9B4AbDDf8d92) |
| YieldDripper | `0xC74119243E3cb9474171740d7707F470F989c194` | [view](https://sepolia.basescan.org/address/0xC74119243E3cb9474171740d7707F470F989c194) |

All contracts are source-verified on Basescan.

## Pre-wired configuration (set during deploy)

- `pool.registerReserve(asset, aToken, debtToken)`
- `vault.createStrategy(deployer)` → strategy id 0
- `vault.setStrategyWeight(0, 10_000)` — 100% of deposits go to strategy 0
- `strategy.setTrustedSpender(pool, true)`
- `strategy.approveToken(asset, pool, type(uint256).max)`
- `strategy.addAllowedAction(pool, supply.selector, recipientOffset=68)`
- `strategy.setWithdrawConfig(pool, withdraw(asset, <amount>, strategy), amountOffset=36)`
- `strategy.addValueSource(aToken, balanceOf(strategy))`
- `dripper`: 100 demo-USDC every 1 hour, seeded with 5,000 demo-USDC
- Deployer minted 10,000 demo-USDC for testing

## JSON

```json
{
  "chainId": 84532,
  "name": "base-sepolia",
  "deployer": "0xf298dB641560E5b733C43181937207482ff79bC9",
  "contracts": {
    "asset":                 "0x6a3601942C2F17370E87a2834317BFC24E0e9E70",
    "vault":                 "0x21c5b7a26a554748c1c557c50e78f5f178e5ba39",
    "strategyImplementation":"0x11D310d30E32275b9F82e671a3b542a09B26c058",
    "strategyId0":           "0xbdf36639462Cf6174Dc895514DEbA2116850992E",
    "pool":                  "0x4CE0Ee1Ed18C2f0D9E5D45ed037380e482ba3C1A",
    "aToken":                "0xEb6566A83ec76Ed023370bAefBE5c0bc402243e5",
    "debtToken":             "0x8f6193f8737913216A6144B18a6E9B4AbDDf8d92",
    "dripper":               "0xC74119243E3cb9474171740d7707F470F989c194"
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

Set environment first (`source .env`):

```bash
ASSET=0x6a3601942C2F17370E87a2834317BFC24E0e9E70
VAULT=0x21c5b7a26a554748c1c557c50e78f5f178e5ba39
STRATEGY=0xbdf36639462Cf6174Dc895514DEbA2116850992E
POOL=0x4CE0Ee1Ed18C2f0D9E5D45ed037380e482ba3C1A
DRIPPER=0xC74119243E3cb9474171740d7707F470F989c194
RPC=$BASE_SEPOLIA_RPC_URL
PK=0x$PRIVATE_KEY    # script accepts with or without 0x; cast wants 0x
YOU=0xf298dB641560E5b733C43181937207482ff79bC9
```

```bash
# 1. user deposits 1,000 demo-USDC
cast send $ASSET "approve(address,uint256)" $VAULT 1000000000 --rpc-url $RPC --private-key $PK
cast send $VAULT "deposit(uint256,address)" 1000000000 $YOU --rpc-url $RPC --private-key $PK

# 2. agent deploys idle into pool (deployer is also the agent)
cast send $STRATEGY "executeAction(address,bytes)" $POOL \
  $(cast calldata "supply(address,uint256,address,uint16)" $ASSET 1000000000 $STRATEGY 0) \
  --rpc-url $RPC --private-key $PK

# 3. wait ≥ 1h, then drip yield
cast send $DRIPPER "drip()" --rpc-url $RPC --private-key $PK

# 4. redeem in profit
SHARES=$(cast call $VAULT "balanceOf(address)(uint256)" $YOU --rpc-url $RPC)
cast send $VAULT "redeem(uint256,address,address)" $SHARES $YOU $YOU --rpc-url $RPC --private-key $PK
```
