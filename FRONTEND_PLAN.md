# AgentVault Frontend — Feature Catalog

Status: the frontend scaffolded in this plan has shipped. This document
reflects **all frontend features currently implemented** in [frontend/](frontend/),
organized for auditability. See [frontend/DECISIONS.md](frontend/DECISIONS.md)
for the autonomous-build decisions made along the way.

## Scope

The UI is a **multi-vault** Next.js + wagmi v2 + viem + RainbowKit dashboard
bound to the AgentVault contracts (router [Vault.sol](src/Vault.sol) + per-strategy
[Strategy.sol](src/Strategy.sol) clones + value-source helpers under
[src/valueSources/](src/valueSources/)). It covers:

- **Public users**: deposit / mint / withdraw / redeem against any listed vault
  (ERC-4626), with allowance pre-flight, live NAV / share-price display, and
  positions across multiple vaults simultaneously.
- **Admins**: strategy create, weight slider, allowed-action whitelist, auto
  deposit/withdraw config templates, value-source registration, delegate
  rotation, current-config viewer.
- **Authority**: manual `rebalance(strategyId, delta)` push/pull UI.
- **Observability**: allocation pie, per-strategy NAV, activity feed built
  from contract events.

Target chains wired: **Base mainnet**, **Base Sepolia**, **Mainnet**, **Foundry
(anvil)**. Each vault is always qualified by `chainId` so the same address
on different chains is treated as distinct.

## Stack actually used

- **Next.js 14 App Router** + TypeScript strict.
- **wagmi v2 + viem** for reads / writes / event watching.
- **RainbowKit** for wallet connect (`ConnectButton`, SSR off).
- **TanStack Query** (bundled with wagmi v2) for cache / refetch.
- **Tailwind + shadcn-style primitives** (inlined under [frontend/components/ui/](frontend/components/ui/),
  no `shadcn` CLI dependency).
- **Recharts** for the allocation pie chart.
- **ABIs** imported from Foundry `out/` (see [frontend/lib/abis.ts](frontend/lib/abis.ts)).
- **All JSON-RPC** is routed through a Next.js server-side proxy
  ([frontend/app/api/rpc/[chain]/route.ts](frontend/app/api/rpc/[chain]/route.ts))
  to sidestep Alchemy CORS and keep API keys server-only.

## Directory layout (actual)

```
frontend/
  app/
    layout.tsx                                   # global layout (Providers + Header)
    providers.tsx                                # wagmi + RainbowKit + QueryClient
    globals.css                                  # Tailwind base + dark tokens
    icon.svg                                     # favicon
    page.tsx                                     # multi-vault landing (VaultList)
    api/rpc/[chain]/route.ts                     # server-side JSON-RPC proxy
    vault/[chainId]/[address]/page.tsx           # per-vault dashboard
    vault/[chainId]/[address]/admin/page.tsx     # role-gated admin panel
  config/
    vaults.ts                                    # registry (env + localStorage)
  components/
    Header.tsx                                   # sticky top bar + VaultSwitcher
    VaultList.tsx                                # landing table of all vaults
    VaultRow (inside VaultList.tsx)              # row with chain/role badges + stats
    VaultSwitcher.tsx                            # header popover to jump vaults
    AddCustomVaultDialog.tsx                     # paste address + chainId + validate
    PositionHeader.tsx                           # aggregate user position card
    VaultDashboard.tsx                           # per-vault page shell
    StrategyTable.tsx                            # table + allowed-actions popover
    AllocationPie.tsx                            # Recharts pie (idle + per-strategy)
    ActivityFeed.tsx                             # vault+strategy event log
    DepositForm.tsx                              # ERC-4626 deposit w/ allowance flow
    WithdrawForm.tsx                             # ERC-4626 withdraw
    AdminPanel.tsx                               # admin page shell + role banner
    admin/StrategyCreate.tsx                     # createStrategy(delegate)
    admin/WeightSlider.tsx                       # setStrategyWeight (save on click)
    admin/ActionWhitelist.tsx                    # add/removeAllowedAction + presets
    admin/ConfigEditor.tsx                       # set/removeDeposit|WithdrawConfig
    admin/ValueSourceEditor.tsx                  # addValueSource + presets
    admin/DelegateEditor.tsx                     # setDelegate (rotate AI agent)
    admin/CurrentConfigPanel.tsx                 # read-back deposit/withdraw/valueSources
    admin/AuthorityRebalance.tsx                 # rebalance(id, ±delta) push/pull
    ui/                                          # Button, Card, Badge, Dialog, Input,
                                                 # Label, Popover, Skeleton, Slider, Textarea
  hooks/
    useVaults.ts                                 # merged registry (env + localStorage)
    useVault.ts                                  # asset/decimals/TVL/supply/user pos
    useStrategy.ts                               # useStrategies(count) → id/addr/weight/
                                                 # totalValue/active/delegate
    useStrategyAllowedActionsLogs.ts             # event-log derived whitelist
    useRoles.ts                                  # hasRole(admin|authority, account)
    useAllowance.ts                              # ERC-20 allowance + refetch
  lib/
    wagmi.ts                                     # chains + RPC-proxy transports
    abis.ts                                      # vault/strategy/erc20 ABIs
    roles.ts                                     # DEFAULT_ADMIN_ROLE / AUTHORITY_ROLE
    format.ts                                    # bps↔pct, token-amount formatting
    selectors.ts                                 # sig→4-byte, preset registry,
                                                 # custom-sig memory
    configPresets.ts                             # deposit/withdraw + value-source presets
    utils.ts                                     # shortAddress, cn, misc
  next.config.js · tsconfig.json · tailwind.config.ts · postcss.config.js
  package.json · pnpm-lock.yaml
```

No Solidity changes were required for the MVP.

## Vault registry

The UI supports multiple vaults via a config-driven registry and will graduate
to an on-chain registry without UI rewrites once a `VaultFactory` lands.

- [frontend/config/vaults.ts](frontend/config/vaults.ts) exposes a typed
  `VaultEntry = { chainId, address, label, description?, assetSymbolHint? }`
  and helpers: `getBaseRegistry()`, `loadCustomVaults()`, `saveCustomVaults()`,
  `mergeRegistries()`, `vaultKey()`.
- **Build-time seed** — `NEXT_PUBLIC_VAULTS` (JSON array of `VaultEntry`).
  `DEV_FALLBACK_VAULTS` is intentionally empty → honest empty state.
- **Runtime add** — [AddCustomVaultDialog](frontend/components/AddCustomVaultDialog.tsx)
  lets users paste an address + label + chain. Validates on-chain by reading
  `asset()` and the asset's `symbol()`, then persists to `localStorage` under
  `agentvault:customVaults`. Merged at runtime with the base registry by
  [`useVaults`](frontend/hooks/useVaults.ts).
- Invalid / mis-chain entries render an **"unreachable" destructive badge**
  on the vault row rather than crashing the app.

## JSON-RPC proxy

[frontend/app/api/rpc/[chain]/route.ts](frontend/app/api/rpc/[chain]/route.ts)
is a server-side passthrough. wagmi transports point at `/api/rpc/base-mainnet`,
`/api/rpc/base-sepolia`, `/api/rpc/mainnet`, `/api/rpc/local`. This avoids
Alchemy CORS and keeps API keys off the client. The default log lookback is
`NEXT_PUBLIC_LOG_LOOKBACK_BLOCKS=10` because Alchemy's free tier rejects
`eth_getLogs` ranges > 10 blocks; a paid RPC can raise this freely.

## Pages

### `/` — multi-vault landing

Renders [`PositionHeader`](frontend/components/PositionHeader.tsx) + [`VaultList`](frontend/components/VaultList.tsx).

- **Aggregate position**: sums `userAssets` across every registered vault,
  broken out per asset symbol. Hidden until a wallet is connected.
- **Vault rows** (one per registered vault): chain badge, admin/authority
  badges (per-vault), unreachable badge, short address, and a 4-stat grid:
  `Asset`, `TVL`, `Share price`, `Your position`. Clicking the row deep-links
  to `/vault/[chainId]/[address]`.
- **Add vault** button in the list header and in the empty state.

### `/vault/[chainId]/[address]` — per-vault dashboard

[`VaultDashboard`](frontend/components/VaultDashboard.tsx).

- Header with back-link, vault label, chain badge, per-vault role badges,
  unreachable badge, short address, and an **Admin** button that appears only
  for admins.
- 4-stat card strip: `Asset`, `TVL`, `Share price`, `Your position`. Share price
  correctly accounts for ERC-4626 `_decimalsOffset = 6` so a fresh vault reads
  ≈ 1.0000.
- **Two-column layout** (`lg:grid-cols-[2fr_1fr]`): primary column holds
  `StrategyTable` → `AllocationPie` → `ActivityFeed`; side column holds
  `DepositForm` → `WithdrawForm`. Collapses to single column below `lg`.

### `/vault/[chainId]/[address]/admin` — admin panel

[`AdminPanel`](frontend/components/AdminPanel.tsx).

- Role gating **by disabling, not hiding** — everyone sees the controls
  (self-documenting), but write buttons are `disabled` when the connected
  wallet lacks the relevant role. A role banner explains the state
  (`Connect a wallet` / `Read-only view`).
- Top grid: [`StrategyCreate`](frontend/components/admin/StrategyCreate.tsx)
  +  "Strategy weights" card listing [`WeightSlider`](frontend/components/admin/WeightSlider.tsx)
  per strategy.
- **Per-strategy section** rendered for each strategy id: active badge +
  two-column grid of
  [`ActionWhitelist`](frontend/components/admin/ActionWhitelist.tsx),
  [`CurrentConfigPanel`](frontend/components/admin/CurrentConfigPanel.tsx),
  [`DelegateEditor`](frontend/components/admin/DelegateEditor.tsx),
  [`ConfigEditor`](frontend/components/admin/ConfigEditor.tsx),
  [`ValueSourceEditor`](frontend/components/admin/ValueSourceEditor.tsx),
  [`AuthorityRebalance`](frontend/components/admin/AuthorityRebalance.tsx).

## Public feature inventory

### Wallet + navigation

- [`Header`](frontend/components/Header.tsx): sticky top bar with the
  AgentVault brand, a **Vault switcher popover** (hidden below `sm` to avoid
  mobile overlap), and RainbowKit `ConnectButton`.
- [`VaultSwitcher`](frontend/components/VaultSwitcher.tsx): popover listing
  every registered vault with label, chain, and short address. Highlights the
  active vault inferred from the URL.

### Deposit (ERC-4626)

[`DepositForm`](frontend/components/DepositForm.tsx).

1. User enters an amount; `parseUnits` validates against `assetDecimals`.
2. `balance` button one-click fills the full wallet balance.
3. `useAllowance(asset, vault)` reads the allowance; if insufficient, the
   primary button becomes `Approve …` and calls `approve(vault, MaxUint256)`.
4. After approval, button switches to `Deposit` → calls
   `vault.deposit(amount, user)`.
5. Success toast (`Deposit confirmed.`) and error alert with truncated message.

Vault auto-rebalances internally per `strategyWeights`; the UI does not
orchestrate this.

### Withdraw (ERC-4626)

[`WithdrawForm`](frontend/components/WithdrawForm.tsx). Mirror flow with
`withdraw(amount, receiver, owner)`. Displays the user's current deposited
value; the contract auto-pulls from strategies in registration order.

### Strategy table + allowed-actions popover

[`StrategyTable`](frontend/components/StrategyTable.tsx). Rows show
`#id · address · weight · totalValue · [N allowed] button · active/inactive`.
The "N allowed" button opens a **popover** that lists every allowed
`(target, selector, recipientOffset)` tuple for that strategy, decoded from
event logs via [`useStrategyAllowedActionsLogs`](frontend/hooks/useStrategyAllowedActionsLogs.ts)
and rendered with human-readable signatures when known
(`signatureForSelector` in [lib/selectors.ts](frontend/lib/selectors.ts)).
This gives any user — not just admins — an at-a-glance view of what the
delegate can do, reinforcing the anti-theft model.

### Allocation pie

[`AllocationPie`](frontend/components/AllocationPie.tsx). Recharts donut with
slices for `Idle = asset.balanceOf(vault)` + each active strategy's
`totalValue()`. Dark-theme-tuned palette; accessible with `aria-labelledby`
figcaption; empty state renders `No funds allocated yet.` instead of a blank
chart. Legend underneath with per-slice percentages; tooltip shows absolute
token amount.

### Activity feed

[`ActivityFeed`](frontend/components/ActivityFeed.tsx). Reads logs from the
vault and each strategy address via `getPublicClient(config).getLogs`, sorts
by block number desc, caps at 30 rows. Each row shows event name (short
topic hash — full event-arg decoding is a follow-up), originating contract,
block, and tx hash. Empty-state CTA.

## Admin feature inventory

### Create strategy

[`StrategyCreate`](frontend/components/admin/StrategyCreate.tsx) —
`vault.createStrategy(delegate)`. Address validated with `isAddress`. Success
banner shows a shortened tx hash. Disabled without admin role.

### Weight slider

[`WeightSlider`](frontend/components/admin/WeightSlider.tsx) — a slider
(0 – 10 000 bps). **Commits on explicit Save**, not on drag, so a single
rebalance isn't triggered on every pixel of slider movement. Save button
enables only when the value differs from the current on-chain weight.
Individual strategies are bounded, but the **sum cap is not enforced** (open
design question per [TODO.md](TODO.md)).

### Allowed-action whitelist editor

[`ActionWhitelist`](frontend/components/admin/ActionWhitelist.tsx).

- **Preset dropdown** (from `ACTION_PRESETS` in [lib/selectors.ts](frontend/lib/selectors.ts)):
  e.g. Aave V3 `supply`/`withdraw`/`borrow`/`repay`, Uniswap V3
  `exactInputSingle`. Selecting a preset fills the form; it does **not** submit.
- Manual inputs: `target`, human-readable signature (e.g.
  `supply(address,uint256,address,uint16)`), `recipientOffset` (0–65534).
  The 4-byte selector is derived live via `viem/toFunctionSelector` and
  previewed.
- **Submit** → `strategy.addAllowedAction(target, selector, recipientOffset)`.
- **Current whitelist** listed below the form, rendered from
  `AllowedActionAdded` / `AllowedActionRemoved` event logs (the mapping is
  not enumerable). Each row has a remove button → `removeAllowedAction`.
  Human-readable signature (via `signatureForSelector`) preferred over raw
  hex when known; custom user-entered signatures are cached in memory via
  `rememberCustomActionSignature` so the UI keeps showing them.

### Auto deposit / withdraw config editor

[`ConfigEditor`](frontend/components/admin/ConfigEditor.tsx).

- One card with a **deposit / withdraw radio**.
- **Preset dropdown** from [lib/configPresets.ts](frontend/lib/configPresets.ts)
  (chain- and asset-filtered; e.g. Aave V3 supply with `amountOffset=36`).
- Manual inputs: `target`, calldata template (hex), `amountOffset`. Calls
  `setDepositConfig` or `setWithdrawConfig` on the strategy.

### Value-source registration

[`ValueSourceEditor`](frontend/components/admin/ValueSourceEditor.tsx).

- Preset dropdown (`VALUE_SOURCE_PRESETS`) filtered by chain + asset symbol.
  Presets include `AaveV3LoopValue` helpers and simple aToken balance reads,
  pre-encoded against the strategy address.
- Manual inputs: `target`, calldata that returns a single `uint256`.
- Submits `strategy.addValueSource(target, data)`.

### Current-config viewer

[`CurrentConfigPanel`](frontend/components/admin/CurrentConfigPanel.tsx).
Reads `depositConfig`, `withdrawConfig`, `valueSourceCount`, and iterates
`valueSources(i)` for each strategy. Shows per-row `target`, `amountOffset`,
and raw calldata. Detects strategies deployed **before** the read-only
getters existed and shows a "redeploy the vault" upgrade prompt instead of
crashing.

### Delegate rotation

[`DelegateEditor`](frontend/components/admin/DelegateEditor.tsx). Displays
the current delegate and submits `strategy.setDelegate(new)`. Rejects same-
address re-submits with a `Same as the current delegate.` hint. Lets admins
rotate the AI agent EOA without redeploying the strategy.

### Authority manual rebalance

[`AuthorityRebalance`](frontend/components/admin/AuthorityRebalance.tsx). A
**push / pull radio group** maps push→`+delta` and pull→`-delta` so the admin
never has to think about signed-int calldata. Calls
`vault.rebalance(strategyId, signedDelta)`. Gated independently on the
`AUTHORITY_ROLE` — an account can be admin without authority and vice-versa.

## Role gating

[`useRoles(chainId, vault)`](frontend/hooks/useRoles.ts) reads
`hasRole(DEFAULT_ADMIN_ROLE, account)` and `hasRole(AUTHORITY_ROLE, account)`
keyed by `(chainId, vault, account)` — never a global `isAdmin` flag.

- `VaultList` row shows an `admin` / `authority` badge next to each vault
  where the connected account holds the role.
- `VaultDashboard` header shows the same badges, plus a dedicated **Admin**
  button only when `roles.isAdmin`.
- `AdminPanel` uses a **disable-not-hide** pattern: controls always render so
  the UI is self-documenting about what exists; write buttons are `disabled`
  when either (a) no wallet is connected, or (b) the connected account lacks
  the relevant role. A `RoleBanner` explains the state.

## Hooks — public surface

| Hook | Purpose |
| --- | --- |
| [`useVaults`](frontend/hooks/useVaults.ts) | Merged registry (base + custom). Returns `{ vaults, hydrated, addVault, removeVault }`. |
| [`useVault`](frontend/hooks/useVault.ts) | Per-vault summary: `asset`, `assetSymbol`, `assetDecimals`, `shareDecimals`, `totalAssets`, `totalSupply`, `strategyCount`, `userAssets`, loading/error. |
| [`useStrategy` / `useStrategies`](frontend/hooks/useStrategy.ts) | Strategy fan-out: `id`, `address`, `weightBps`, `totalValue`, `active`, `delegate`. |
| [`useStrategyAllowedActionsLogs`](frontend/hooks/useStrategyAllowedActionsLogs.ts) | Event-log replay of `AllowedActionAdded/Removed` with in-memory cache and custom-action memory for fresh writes. |
| [`useRoles`](frontend/hooks/useRoles.ts) | Per-vault `{ isAdmin, isAuthority, isLoading }`. |
| [`useAllowance`](frontend/hooks/useAllowance.ts) | ERC-20 `allowance(owner, vault)` with refetch on tx success. |

## Environment

- `NEXT_PUBLIC_VAULTS` — JSON array of `VaultEntry` for build-time seed.
- `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` — RainbowKit / WalletConnect.
- `NEXT_PUBLIC_BASE_RPC_URL`, `NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL`,
  `NEXT_PUBLIC_MAINNET_RPC_URL`, `NEXT_PUBLIC_LOCAL_RPC_URL` — consumed by
  the server-side RPC proxy.
- `NEXT_PUBLIC_LOG_LOOKBACK_BLOCKS` — default 10 (Alchemy free-tier limit).

## Verification

End-to-end against the Base fork (same RPC the Foundry tests hit):

1. `forge build` to regenerate ABIs.
2. `cd frontend && pnpm install && pnpm dev`.
3. Run `anvil --fork-url $BASE_RPC_URL --chain-id 8453 --host 127.0.0.1
   --port 8545` and deploy via
   [script/DeployDual.s.sol](script/DeployDual.s.sol) against the anvil fork.
4. Deploy **at least two vaults** (e.g. one USDC, one WETH) and seed them
   into `NEXT_PUBLIC_VAULTS`. Restart `pnpm dev`.
5. Multi-vault UI paths exercised:
   - Landing lists both with correct asset symbols, TVL, user balances.
   - Aggregate position sums both.
   - `VaultSwitcher` navigates between them without full reload.
   - `AddCustomVaultDialog` accepts a third and persists it across reloads
     via `localStorage`.
   - Role badges appear only on vaults where the account holds the role.
6. Per-vault journeys (mirror of [test/integration/AaveV3Base.t.sol](test/integration/AaveV3Base.t.sol)
   and [test/integration/AaveV3BaseLooping.t.sol](test/integration/AaveV3BaseLooping.t.sol)):
   - Admin: create strategy, set weight, whitelist `aavePool.supply` +
     `aavePool.withdraw`, add `AaveV3LoopValue` value source, set auto
     deposit/withdraw config.
   - User: approve + deposit, observe auto-rebalance in the pie, share
     price ≈ 1 initially.
   - Warp (`anvil_setNextBlockTimestamp`) → `totalAssets` ticks up → redeem
     and verify realized yield.
   - Authority: manual `rebalance(id, -delta)` and confirm pie updates.
7. Smoke on Base Sepolia (see [DEPLOYMENTS.md](DEPLOYMENTS.md) + the mock
   Aave + YieldDripper setup).

## Out of scope / deferred

- Off-chain `agent/` (separate TODO item).
- Historical APY / drawdown charts (requires an indexer).
- Fee / pause / circuit-breaker UI — gated on the corresponding contract
  features landing first (open design questions in [TODO.md](TODO.md)).
- Full event-arg decoding in `ActivityFeed` (currently short topic hashes).
- Connected-wallet e2e via Playwright — RainbowKit's handshake isn't
  headless-friendly. Tracked in [frontend/DECISIONS.md](frontend/DECISIONS.md).
- "Sum of active strategy weights ≤ 10 000 bps" enforcement — the UI
  validates each strategy independently; see [TODO.md](TODO.md).
