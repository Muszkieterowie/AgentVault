# AISandbox

> Non-custodial ERC-4626 vaults where AI agents manage real capital inside a
> sandbox small enough that a compromised agent can't steal, drain, or
> misroute user funds.

AISandbox lets an autonomous agent (an EOA) actively manage DeFi positions on
behalf of many users. The agent can call only pre-approved protocol actions,
each strategy runs in its own isolated contract clone, and an anti-theft
balance-delta check guards every agent-initiated call. Read the full design
writeup in [OVERVIEW.md](OVERVIEW.md).

The first deployment uses **target-date event vaults** — a single fixed
deadline gates the two phases (deposits open / withdrawals open), so a
community can pool funds toward a specific event and redeem their
pro-rata share after it matures. Two such vaults are live on Base Sepolia:
**ETHSilesia** (30-day deadline) and **ETHWarsaw** (60-day deadline).

## Architecture at a glance

| Piece | Role |
| --- | --- |
| **Vault** — [src/Vault.sol](src/Vault.sol) | ERC-4626 share token, strategy factory + registry, fan-out rebalancer, AccessControl root. |
| **Strategy** — [src/Strategy.sol](src/Strategy.sol) | Per-strategy contract (EIP-1167 clone) that holds its own slice of assets + external positions. Runs agent actions through a whitelist + anti-theft check. |
| **Frontend** — [frontend/](frontend) | Next.js 16 + wagmi + RainbowKit. Dashboard, deposit / withdraw forms, per-vault admin panel with rebalance-to-weights helper. |
| **Deploy scripts** — [script/](script) | Foundry scripts for Base Sepolia (`DeployTwoVaults.s.sol`, `AddStrategies.s.sol`) and the single-vault demo (`DeployBaseSepolia.s.sol`). |

Three non-obvious invariants that any change must preserve:

1. **Strategies are physically isolated.** Every strategy is its own cloned
   contract; strategy A's delegate cannot reach strategy B's balances or
   approvals. No shared-ledger shortcuts.
2. **Whitelists are per-strategy.** `allowedActions[target][selector]` on
   strategy 0 does *not* authorize the same call on strategy 1.
3. **Every `executeAction` enforces a balance-delta check.** The caller's
   asset balance must not increase across the external call, with an
   optional `recipientOffset` pinning the decoded recipient to the strategy
   itself. Any new fund-movement path has to keep this invariant alive.

See [OVERVIEW.md §7](OVERVIEW.md) for the full `executeAction` validation
flowchart and [CLAUDE.md](CLAUDE.md) for the role model.

## Repo layout

```
src/              Solidity — Vault, Strategy, interfaces, mocks, value sources
test/             Foundry tests (Vault, Strategy, E2E yield)
script/           Foundry deploy/admin scripts
lib/              git submodules (forge-std, OpenZeppelin) — pulled by `forge install`
frontend/         Next.js app (deployed to Vercel)
deployments/      On-chain deployment manifests (base-sepolia.md is the live one)
broadcast/        Foundry broadcast receipts for each deployment run
OVERVIEW.md       Design writeup — read this to understand the trust model
CLAUDE.md         Build/test commands + invariants for AI assistants
```

## Quick start — contracts

Prereqs: [Foundry](https://getfoundry.sh/). On a fresh clone:

```bash
forge install                    # lib/forge-std + lib/openzeppelin-contracts
forge build
forge test                       # full unit + integration suite
forge test --match-path test/Strategy.t.sol -vvv
forge coverage
```

Local Aave-mock demo on anvil:

```bash
# Terminal 1
anvil --fork-url $BASE_RPC_URL --chain-id 8453 --host 127.0.0.1 --port 8545

# Terminal 2
source .env
forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
  --rpc-url http://127.0.0.1:8545 --broadcast
```

## Quick start — frontend

Requires Node 20.9+ (tested on 22) and `pnpm`.

```bash
cd frontend
cp .env.example .env.local       # fill NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL
pnpm install
pnpm dev                         # http://localhost:3000 (or 3001 if 3000 is busy)
pnpm build                       # production build (used by Vercel)
```

RPC traffic from the browser goes through `/api/rpc/[chain]` to avoid CORS;
the proxy accepts the standard `eth_*` / `net_*` / `web3_*` namespaces and
blocks any server-side signing methods. See [frontend/vercel.json](frontend/vercel.json)
for the Vercel build config.

## Live on Base Sepolia

Full address manifest + Basescan links: [deployments/base-sepolia.md](deployments/base-sepolia.md).

| Vault | Address | Deadline |
| --- | --- | --- |
| `avETHSilesia` | `0xBaCF3F8237BAbFF700B762561A3cCF474f6688A8` | 2026-05-18 14:05 UTC |
| `avETHWarsaw`  | `0x26E20946d273d6B3d17094744C9C3d648DE7F425` | 2026-06-17 14:05 UTC |

Both vaults share a single `DemoUSDC` (6 dec) asset, a `MockAavePool`, and a
`YieldDripper` that streams yield into the aToken reserve on demand. Source
is verified on Basescan.

## Target-date lifecycle

- **Before `DEADLINE`** — `deposit` / `mint` open; `withdraw` / `redeem`
  revert with `VaultNotMatured`. Agent `executeAction` + `approveToken` open.
- **At / after `DEADLINE`** — `deposit` / `mint` revert with `VaultMatured`;
  `withdraw` / `redeem` open. Agent `executeAction` + `approveToken`
  forbidden. Anyone can call `vault.drainAllStrategies()` to sweep funds
  back to idle in one tx.
- Authority `rebalance` stays open in both phases.

## License

AISandbox is licensed under the GNU General Public License v3.0 or later —
see [LICENSE](LICENSE) for the full text.
