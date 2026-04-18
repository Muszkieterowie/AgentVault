# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

This repo currently contains only design docs — [OVERVIEW.md](OVERVIEW.md) and [CLAUDE_SETUP.md](CLAUDE_SETUP.md). The Solidity contracts (`src/`, `test/`, `script/`, `lib/`) and the Next.js frontend (`frontend/`) referenced throughout the docs **have not been committed yet**. When making structural claims, first verify the target actually exists — do not assume paths from OVERVIEW.md are present.

The `.claude/` directory is gitignored; see [CLAUDE_SETUP.md](CLAUDE_SETUP.md) for how to re-provision it on a fresh clone (plugin list, permission allowlist, `/grill-me` skill).

## What this project is

AISandbox is a non-custodial ERC-4626 vault that lets AI-agent EOAs manage DeFi positions on behalf of users without ever holding the funds. The architecture hinges on three non-obvious choices that must be preserved by any change:

1. **Each strategy is its own contract**, cloned via EIP-1167 from a single locked implementation. Strategy A's delegate cannot reach Strategy B's balances or approvals — the isolation is physical, not a ledger row.
2. **Whitelists are scoped per strategy**, not global. `allowedActions[target][selector]` on Strategy 0 does not authorize the same call on Strategy 1.
3. **Anti-theft check on every `executeAction`**: the caller's asset balance must not increase across the external call. Paired with an optional `recipientOffset` that pins the decoded recipient to the strategy itself. If you add a new fund-movement path, this invariant must still hold.

See [OVERVIEW.md §7](OVERVIEW.md) for the full `executeAction` validation flowchart — every branch is expected to have a matching revert test.

## Role model (do not blur)

| Role                                      | Holder       | Capability boundary                                                                                |
| ----------------------------------------- | ------------ | -------------------------------------------------------------------------------------------------- |
| `DEFAULT_ADMIN_ROLE`                      | multisig/DAO | Configures vault + strategies, manages whitelist. **Cannot move funds.**                           |
| `AUTHORITY_ROLE`                          | keeper EOA   | Rebalances vault↔strategies, can override agent via `executeAction`. **Cannot change whitelists.** |
| Delegate (per-strategy field, not a role) | AI-agent EOA | `executeAction` on its own strategy only. No token approvals.                                      |
| User                                      | anyone       | ERC-4626 `deposit`/`mint`/`withdraw`/`redeem`.                                                     |

Strategy **deactivation is permanent** by design — there is intentionally no reactivation path. Do not add one without an explicit design discussion.

## Build / test / run commands

Prerequisites are listed in [CLAUDE_SETUP.md §1](CLAUDE_SETUP.md). Foundry binaries live at `~/.foundry/bin/`; if `forge`/`anvil`/`cast` are not on `PATH` for a fresh shell, source `~/.bashrc` or export `PATH="$HOME/.foundry/bin:$PATH"`.

### Contracts (once `src/` + `foundry.toml` exist)

```bash
forge install                    # pulls lib/forge-std + lib/openzeppelin-contracts
forge build
forge test                       # full unit + integration suite
forge test --match-path test/unit/StrategyActionWhitelist.t.sol   # one file
forge test --match-test test_executeAction_revertsWhenRecipientIsNotStrategy -vvv   # one test, verbose trace
forge coverage
```

### Local fork + deploy (review loop)

```bash
# T1 — anvil forked against Base mainnet
anvil --fork-url $BASE_RPC_URL --chain-id 8453 --host 127.0.0.1 --port 8545

# T2 — deploy + seed
source .env
forge script script/DeployDual.s.sol:DeployDual     --rpc-url http://127.0.0.1:8545 --broadcast
forge script script/SeedStrategies.s.sol:SeedStrategies --rpc-url http://127.0.0.1:8545 --broadcast
```

The deploy script is expected to stand up two vaults (`avUSDC`, `avWETH`) against `MockAavePool` + rebasing `MockAToken`, with `YieldDripper` simulating interest accrual. On Base mainnet the same scripts take a real Aave V3 Pool address.

### Frontend (once `frontend/` exists)

```bash
cd frontend
cp .env.example .env.local       # fill NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID + RPC
pnpm install
pnpm dev                         # http://localhost:3000
```

Point `NEXT_PUBLIC_BASE_RPC_URL` at the local anvil (`http://127.0.0.1:8545`) so wagmi's `base` chain (id 8453) resolves locally. Frontend RPC goes through `/api/rpc/[chain]` to avoid CORS.

### Keeper

`cast call isReady()(bool)` inside [script/drip.sh](script/drip.sh) is the YieldDripper trigger check. If the keeper errors, verify `cast` is on `PATH`.

## NAV — why there is no `reportYield`

`Vault.totalAssets()` is a **live scan** over every active strategy at read time, not a cached snapshot:

```
totalAssets = idle(vault) + Σ strategy_i.totalValue()
strategy.totalValue() = idle + Σ valueSources[i]()   // admin-configured read-only calls
```

Rebasing aTokens (real or mocked via `YieldDripper`) therefore flow into share price automatically. Do not add a push-based yield-reporting path — it would desync share price from reality. If `totalValue()` needs a new source, add it via `addValueSource(target, data)` as a read-only call.

## Frontend review loop

UI changes are reviewed through **Playwright-MCP**, which drives the system's `google-chrome-stable` (not the `@playwright/test` dep in `frontend/package.json`). The loop: `browser_navigate` → `browser_snapshot` (DOM+ARIA) → `browser_take_screenshot` → `browser_console_messages` → edit → reload. Watch for hydration warnings and RPC failures in console output. `browser_resize` between desktop and mobile widths is required — mobile regressions have bitten this project before (see `frontend/DECISIONS.md` §Slice 1 when it exists).

**Known gotcha:** Playwright-MCP cannot complete the RainbowKit wallet handshake headlessly. E2E deposit tests are deferred pending a mock wagmi connector using viem's `privateKeyToAccount` with an anvil-funded key.

## When adding strategies or whitelisted calls

1. New `addAllowedAction(target, selector, recipientOffset)` entry — always ask whether the call has a recipient field. If yes, set `recipientOffset` so the anti-theft path pins it to the strategy. If no recipient, the balance-delta check is the only line of defense; weigh whether this target should really be whitelisted.
2. Add a value source for any position the call creates (aToken, LP receipt, etc.) so NAV stays honest.
3. Every revert branch of `executeAction` is expected to have a negative test. New whitelisting logic should come with its own reverts tests.

## Deferred items (see TODO.md when present)

Do not silently implement these — they're conscious omissions: VaultFactory / multi-vault registry, `PAUSER_ROLE` pause, per-action gas or loss caps, protocol/performance fees, swap-output token allowlist, strategy reactivation. If a task seems to require one, surface it before building.
