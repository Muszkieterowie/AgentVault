# AgentVault Frontend — MVP Plan

A single-page Next.js dashboard bound to the AgentVault contracts on
**Base Sepolia**. Public users deposit and withdraw; admins configure
strategies; an authority can manually rebalance.

## Contract surface this UI binds to

| Contract | Path | Key functions the UI calls |
| --- | --- | --- |
| `Vault` (ERC-4626) | [src/Vault.sol](src/Vault.sol) | `deposit`, `mint`, `withdraw`, `redeem`, `createStrategy`, `setStrategyWeight`, `deactivateStrategy`, `rebalance`, `setAuthority`, `totalAssets`, `strategies`, `strategyWeights`, `strategyActive`, `strategyCount` |
| `Strategy` (clone) | [src/Strategy.sol](src/Strategy.sol) | `setDelegate`, `addAllowedAction`, `removeAllowedAction`, `setDepositConfig`, `setWithdrawConfig`, `removeDepositConfig`, `removeWithdrawConfig`, `addValueSource`, `removeValueSource`, `totalValue`, `depositConfig`, `withdrawConfig`, `valueSources` |
| `AaveV3LoopValue` | [src/valueSources/AaveV3LoopValue.sol](src/valueSources/AaveV3LoopValue.sol) | `valueOf(strategy)` — registered as a strategy value source |

Roles (OZ AccessControl, queried via `hasRole`):

- `DEFAULT_ADMIN_ROLE` — strategy config, weights, deactivation. Rotate via `grantRole`/`revokeRole`.
- `AUTHORITY_ROLE` — `rebalance(strategyId, ±delta)`. Rotate via `setAuthority`.

## Stack

- Next.js 14 (App Router) + TypeScript
- wagmi v2 + viem + RainbowKit
- Tailwind + shadcn-style primitives
- ABIs imported from Foundry `out/`

## Pages

**`/` — vault dashboard**

Single target vault (address set via `NEXT_PUBLIC_VAULT_ADDRESS`). Layout:

- Header: brand + RainbowKit `ConnectButton`, role badges (`admin` / `authority`) when applicable.
- Stats strip: `Asset`, `TVL` (`totalAssets`), `Share price`, `Your position`.
- Main column: strategy table → allocation pie → recent activity.
- Side column: deposit form → withdraw form.

**`/admin`**

Role-gated **by disabling, not hiding** — controls render for everyone (self-documenting), but write buttons are disabled unless the connected wallet holds the relevant role. Contains, per strategy:

- Create strategy (`createStrategy(delegate)`)
- Weight slider (`setStrategyWeight`, save-on-click so drags don't spam txs)
- Allowed-action whitelist editor (`addAllowedAction` / `removeAllowedAction`) with preset dropdown for Aave V3 `supply`/`withdraw`/`borrow`/`repay`
- Deposit/withdraw auto-config editor (`setDepositConfig` / `setWithdrawConfig` + remove)
- Value-source registration (`addValueSource` / `removeValueSource`), presets for `AaveV3LoopValue` and aToken balance reads
- Delegate rotation (`setDelegate`)
- Current-config viewer (reads `depositConfig`, `withdrawConfig`, iterates `valueSources`)
- Authority rebalance (`rebalance(id, ±delta)`) with a push/pull radio group

## Core user flows

**Deposit (ERC-4626)**

1. `parseUnits(amount, assetDecimals)` — validate.
2. Read ERC-20 `allowance(user, vault)`. If insufficient → primary button becomes `Approve` (calls `approve(vault, MaxUint256)`).
3. Call `vault.deposit(amount, user)`.
4. Vault auto-rebalances internally by `strategyWeights` — UI does not orchestrate.

**Withdraw** — mirror with `withdraw(amount, receiver, owner)`. Vault auto-pulls from strategies in registration order.

**Observability**

- **Allocation pie**: slices for `asset.balanceOf(vault)` (idle) + each active strategy's `totalValue()`.
- **Activity feed**: logs from the vault + each strategy address, capped at ~30 rows. Event-arg decoding is deferred — rows show event name, contract, block, tx hash.
- **Allowed-action popover**: every strategy row exposes a popover listing its whitelist (decoded from `AllowedActionAdded`/`AllowedActionRemoved` logs, since the mapping isn't enumerable).

## Environment

```
NEXT_PUBLIC_VAULT_ADDRESS           # target Vault on Base Sepolia
NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL    # server-side RPC (proxied)
NEXT_PUBLIC_LOCAL_RPC_URL           # anvil fork (local dev)
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID
NEXT_PUBLIC_LOG_LOOKBACK_BLOCKS=10  # Alchemy free-tier limit
```

All JSON-RPC is routed through a Next.js server route to keep keys off the
client and sidestep Alchemy CORS.

## Verification path

1. `forge build` — regenerate ABIs into `out/`.
2. `anvil --fork-url $NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL --chain-id 84532`
3. Deploy via `script/DeployDual.s.sol` (to be written).
4. Set `NEXT_PUBLIC_VAULT_ADDRESS` → `cd frontend && pnpm install && pnpm dev`.
5. Admin path: create strategy, set weight, whitelist `aavePool.supply` + `aavePool.withdraw`, register `AaveV3LoopValue` value source, set auto deposit/withdraw config.
6. User path: approve + deposit, watch the pie update, verify share price ≈ 1 on a fresh vault.
7. Warp time on the fork (`anvil_setNextBlockTimestamp`) → `totalAssets` ticks up → redeem and verify realized yield.
8. Authority path: `rebalance(id, -delta)` and confirm the pie shifts.

## Out of scope for MVP

- Multi-vault registry / vault switcher (one vault at a time for now).
- Historical APY / drawdown charts (needs an indexer).
- Fee / pause / circuit-breaker UI (contract features don't exist yet).
- Full event-arg decoding in the activity feed.
- Playwright wallet e2e — RainbowKit's handshake isn't headless-friendly.
- Sum-of-weights ≤ 10_000 bps enforcement (UI validates per-strategy only).
