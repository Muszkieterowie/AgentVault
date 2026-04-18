# AISandbox — High-Level Overview

> **One line:** a non-custodial ERC-4626 vault where AI agents manage real
> capital inside a sandbox small enough that a compromised agent can't steal,
> drain, or misroute user funds.

---

## 1. The problem

You want an **autonomous AI agent** to actively manage DeFi positions —
lend into Aave, borrow, swap, loop, rebalance — **on behalf of many users**.

Three things that make this hard:

| Concern              | What can go wrong                                                           |
| -------------------- | --------------------------------------------------------------------------- |
| **Custody**          | Agent keys get phished → the agent drains the vault.                        |
| **Silent misuse**    | Agent makes an innocent-looking tx that quietly sends funds to an attacker. |
| **Spread of damage** | One bad strategy shouldn't hurt users who chose a different strategy.       |

AISandbox answers all three: **the agent never holds user funds, can
only call pre-approved protocol actions, and each strategy lives in its
own separate contract.**

---

## 2. The design in one picture

```mermaid
flowchart LR
    subgraph UsersSide["Users"]
        U1[User A]
        U2[User B]
    end

    subgraph VaultSide["Vault (ERC-4626)"]
        V[Vault<br/>- mints/burns shares<br/>- auto-rebalance<br/>- factory + AccessControl root]
    end

    subgraph Strategies["Strategies (EIP-1167 clones)"]
        S0[Strategy 0<br/>60% weight]
        S1[Strategy 1<br/>40% weight]
    end

    subgraph Protocols["External DeFi"]
        A[Aave V3 Pool]
        UNI[Uniswap V3]
        M[Morpho]
    end

    subgraph Offchain["Off-chain"]
        D0((Delegate 0<br/>AI agent EOA))
        D1((Delegate 1<br/>AI agent EOA))
        ADM((Admin))
        AUTH((Authority))
    end

    U1 -- deposit assets --> V
    U2 -- deposit assets --> V
    V -- weighted push --> S0
    V -- weighted push --> S1

    D0 -. executeAction .-> S0
    D1 -. executeAction .-> S1

    S0 -- whitelisted calls --> A
    S0 -- whitelisted calls --> UNI
    S1 -- whitelisted calls --> M

    ADM -. create/whitelist .-> V
    AUTH -. rebalance .-> V
```

**In short:**

- Users only interact with the **Vault** (deposit/withdraw shares).
- The vault **splits each deposit across strategies** by target weight.
- Each **Strategy is a separate contract** that holds its own slice and
  any external positions (aTokens, LP positions, etc.).
- AI agents act **through** their strategy via `executeAction` — they
  never touch tokens directly.

---

## 3. Three core ideas

### 3.1 Strategies are real contracts, not just ledger rows

Most multi-strategy vaults just remember how much each strategy owns in
a lookup table. AISandbox instead deploys a **separate Strategy
contract per strategy**, cloned via EIP-1167 minimal proxies.

```mermaid
flowchart LR
    I[Strategy Implementation<br/>deployed once<br/>initialized=true 🔒]
    V[Vault.createStrategy]
    C0[Strategy 0 clone<br/>~45 bytes<br/>delegatecalls to impl]
    C1[Strategy 1 clone]
    C2[Strategy 2 clone]

    V -- Clones.clone --> C0
    V -- Clones.clone --> C1
    V -- Clones.clone --> C2
    I -. delegatecall .- C0
    I -. delegatecall .- C1
    I -. delegatecall .- C2
```

**Why this matters:** a compromised strategy can only lose **its own**
funds. Strategy 0's delegate can't touch Strategy 1's aTokens, because
they live at a different address with different approvals.

### 3.2 The whitelist is scoped to each strategy

The delegate never gets token approvals. They call
`Strategy.executeAction(target, data)`, which checks a per-strategy list:

```
allowedActions[target][selector] → { allowed, recipientOffset }
```

Whitelisting `aavePool.supply` on Strategy 0 does **not** let Strategy
1's delegate supply, even though the selector is the same.

### 3.3 Anti-theft check on every call

Even with a whitelisted call, the delegate could try calling something
like `someRouter.swapToSelf(...)` if the admin slipped up. AISandbox
catches this with a simple rule enforced at call time:

> **The caller's asset balance must not go up after the call.**

If it does, the call reverts. Paired with the `recipientOffset` check
(the recipient encoded in calldata must equal the strategy itself, not
the delegate), damage stays small even if the whitelist has a gap.

---

## 4. Roles

```mermaid
flowchart TB
    subgraph Onchain
        direction LR
        ADM[DEFAULT_ADMIN_ROLE<br/><b>Admin</b>]
        AUT[AUTHORITY_ROLE<br/><b>Authority</b>]
        DEL[Strategy.delegate<br/><b>Delegate</b><br/>per-strategy, not a role]
        USR[<b>Users</b><br/>anyone holding shares]
    end

    ADM --> |createStrategy,<br/>setStrategyWeight,<br/>deactivateStrategy,<br/>whitelist,<br/>configs| Caps1[Vault + Strategy config]
    AUT --> |rebalance,<br/>executeAction override| Caps2[Fund movement<br/>+ agent override]
    DEL --> |executeAction<br/>for own strategy only| Caps3[Protocol interaction]
    USR --> |deposit,<br/>withdraw,<br/>redeem,<br/>mint| Caps4[ERC-4626 share mgmt]
```

| Role          | Held by                     | Can do                                                         | Cannot do                                              |
| ------------- | --------------------------- | -------------------------------------------------------------- | ------------------------------------------------------ |
| **Admin**     | Multisig / DAO              | Configure vault + strategies, whitelist actions                | Move funds directly                                    |
| **Authority** | Rebalancer EOA / keeper     | Push/pull funds between vault ↔ strategies; override any agent | Change whitelists                                      |
| **Delegate**  | AI agent EOA (per strategy) | Invoke whitelisted actions on its own strategy                 | Touch any other strategy, move funds outside whitelist |
| **User**      | Anyone                      | ERC-4626 deposit/withdraw                                      | Anything privileged                                    |

---

## 5. User flow — deposit

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant V as Vault
    participant S0 as Strategy 0 (60%)
    participant S1 as Strategy 1 (40%)
    participant A as Aave Pool

    U->>V: approve(asset, amount)
    U->>V: deposit(amount, user)
    V->>V: mint shares (ERC-4626)
    Note over V: _autoRebalanceIn(amount)
    V->>S0: transfer(amount * 0.6)
    V->>S0: pushFunds(amount * 0.6)
    S0->>A: supply(amount * 0.6) [deposit config]
    A-->>S0: aToken minted
    V->>S1: transfer(amount * 0.4)
    V->>S1: pushFunds(amount * 0.4)
    S1->>A: (no config, idle on strategy)
```

The deposit is **split by each strategy's weight as-is** (not scaled to
100%): if active weights add up to less than 10_000 bps, the remainder
stays idle in the vault as a liquidity buffer.

## 6. User flow — withdraw

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant V as Vault
    participant S0 as Strategy 0
    participant S1 as Strategy 1
    participant A as Aave Pool

    U->>V: withdraw(amount, user, user)
    Note over V: need `amount` of idle
    alt idle >= amount
        V->>U: transfer(amount)
    else idle < amount
        V->>S0: pullFunds(deficit)
        S0->>A: withdraw(needed) [withdraw config]
        A-->>S0: asset returned
        S0->>V: transfer(actual)
        opt still short
            V->>S1: pullFunds(remaining)
            S1->>V: transfer(actual)
        end
        V->>U: transfer(amount)
    end
    V->>V: burn shares
```

Strategies are tried **in the order they were created**. If the last
strategy still can't free up enough, the whole withdraw reverts with
`InsufficientLiquidity`.

---

## 7. Agent flow — executeAction validation steps

This is the most important flow. Every AI action goes through it.

```mermaid
flowchart TB
    Start([delegate calls Strategy.executeAction<br/>target, data])

    Caller{caller is delegate<br/>OR authority?}
    Len{data.length >= 4?}
    WL{allowedActions<br/>target, selector<br/>.allowed?}
    Guard{target != asset,<br/>self, vault?}
    Recip{recipientOffset != 0?}
    RecipCheck{decoded recipient<br/>== strategy?}
    Snap[snapshot<br/>asset.balanceOf msg.sender]
    Call[target.call data]
    CallOk{call succeeded?}
    Anti{asset.balanceOf msg.sender<br/>did not increase?}
    Emit[increment actionCount<br/>emit ActionExecuted]

    Done([return result])
    Revert1([revert NotDelegateNorAuthority])
    Revert2([revert DataTooShort])
    Revert3([revert ActionNotAllowed])
    Revert4([revert TargetIs...])
    Revert5([revert RecipientMustBeVault])
    Revert6([revert CallFailed])
    Revert7([revert AntiTheft])

    Start --> Caller
    Caller -- no --> Revert1
    Caller -- yes --> Len
    Len -- no --> Revert2
    Len -- yes --> WL
    WL -- no --> Revert3
    WL -- yes --> Guard
    Guard -- no --> Revert4
    Guard -- yes --> Recip
    Recip -- no --> Snap
    Recip -- yes --> RecipCheck
    RecipCheck -- no --> Revert5
    RecipCheck -- yes --> Snap
    Snap --> Call
    Call --> CallOk
    CallOk -- no --> Revert6
    CallOk -- yes --> Anti
    Anti -- no --> Revert7
    Anti -- yes --> Emit --> Done

    classDef guard fill:#fff3cd,stroke:#b38500;
    classDef danger fill:#f8d7da,stroke:#842029;
    classDef happy fill:#d1e7dd,stroke:#0f5132;
    class Caller,Len,WL,Guard,Recip,RecipCheck,CallOk,Anti guard
    class Revert1,Revert2,Revert3,Revert4,Revert5,Revert6,Revert7 danger
    class Emit,Done happy
```

Every failure branch is a tested revert in
[test/unit/StrategyActionWhitelist.t.sol](test/unit/StrategyActionWhitelist.t.sol).

---

## 8. NAV — how the vault knows what it's worth

```mermaid
flowchart LR
    subgraph V["Vault.totalAssets()"]
        IDLE[idle =<br/>asset.balanceOf vault]
        S0V[Strategy 0.totalValue]
        S1V[Strategy 1.totalValue]
        SUM((+))
    end

    subgraph S0["Strategy 0.totalValue()"]
        I0[idle]
        VS0a[aToken.balanceOf self]
        VS0b[anchor price oracle]
        S0SUM((+))
    end

    IDLE --> SUM
    S0V --> SUM
    S1V --> SUM

    I0 --> S0SUM
    VS0a --> S0SUM
    VS0b --> S0SUM

    S0SUM --> S0V
```

- `Strategy.totalValue() = idleBalance + Σ valueSources`
- Each **value source** is a `(target, data)` read-only call set up by
  the admin (e.g. `aUSDC.balanceOf(strategy)`).
- The vault's `totalAssets()` is a **live scan over every strategy** —
  no stored snapshot. Share price reflects protocol state at the exact
  block it's read.

This is why yield from rebasing aTokens (or our mock
[YieldDripper](src/mocks/YieldDripper.sol)) shows up **automatically** in
the share price — no `reportYield` call needed.

---

## 9. Deployment topology

```mermaid
flowchart TB
    subgraph Once["Once per deployment"]
        F[Vault constructor]
        F --> SI[Strategy implementation<br/>deployed + locked]
    end

    subgraph PerStrategy["Per strategy (admin)"]
        C[createStrategy delegate]
        C --> CL[EIP-1167 clone]
        CL --> INIT[clone.initialize vault, asset, delegate]
        INIT --> WL[addAllowedAction x N]
        WL --> CFG[setDeposit/WithdrawConfig]
        CFG --> VSRC[addValueSource x N]
        VSRC --> W[setStrategyWeight]
    end

    subgraph Testnet["Testnet (no real Aave on Base Sepolia)"]
        MP[MockAavePool]
        MA[MockAToken<br/>rebasing]
        YD[YieldDripper]
        YD -- periodically --> MA
    end

    SI --> CL
    WL -. whitelists .-> MP
    VSRC -. reads .-> MA
```

On **Base Sepolia** (see [DEPLOYMENTS.md](DEPLOYMENTS.md)):

- Two vaults: `avUSDC`, `avWETH`
- Each USDC strategy points at `MockAavePool` + `aUSDCm` rebasing aToken
- `YieldDripper` drips yield into `aUSDCm` on a schedule — simulates
  interest accrual so demo vaults show realistic share-price growth

On **Base mainnet**: same scripts, swap in the real Aave V3 Pool
address. No production deployment yet.

---

## 10. Security model

| Threat                                                 | Mitigation                                                                                       |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| Agent key is stolen and tries to drain the vault       | Agent has no token approvals; must go through the per-strategy whitelisted selector.             |
| A whitelisted call tries to reroute funds              | Anti-theft check on caller balance + optional `recipientOffset` check.                           |
| Strategy A's delegate tries to move Strategy B's funds | Strategies are separate contracts with separate approvals.                                       |
| Re-entrancy during action execution                    | `nonReentrant` on every external fund-movement entrypoint on both Vault and Strategy.            |
| Inflation attack on a fresh vault                      | `_decimalsOffset = 6` (OpenZeppelin virtual shares pattern).                                     |
| Admin makes a mistake                                  | Strategy deactivation is **permanent** — there's no way to turn one back on.                     |
| Strategy gets re-initialized                           | Implementation constructor locks `initialized = true`; `initialize` can only run once per clone. |

---

## 11. What's not in scope

The following are **deliberately deferred** — see [TODO.md](TODO.md):

- VaultFactory (multi-vault registry with cheaper clones)
- Emergency pause / circuit breaker (`PAUSER_ROLE`)
- Per-action gas or loss caps
- Protocol / performance fees
- Token allowlist for swap outputs (currently an agent with a whitelisted
  router can park funds in any output token the router supports)
- Reactivation path (intentionally never)

These can all be added on later; the core model is stable.

---

## 12. How to pitch it

If you get 60 seconds:

> AISandbox is an ERC-4626 vault that lets AI agents move real money
> without being able to steal any of it. Each strategy is a separate
> sandbox contract. The agent can only call pre-approved DeFi actions,
> and even then, if any of those actions would reroute assets to the
> agent's own wallet, the transaction reverts on-chain. Users deposit
> once, the vault fans their money across strategies by weight, and
> NAV is computed live from the positions each strategy holds.

If you get 5 minutes: §2, §3, §7 (the validation flowchart), §10.

If they have engineers in the room: also §8 (NAV) and §6 (withdraw
fallback chain).

---

## 13. Further reading

- [EVM_VAULT_SPEC.md](EVM_VAULT_SPEC.md) — original build spec (some sections describe goals that aren't built yet; see TODO.md).
- [CLAUDE.md](CLAUDE.md) — build/test commands + architecture notes for contributors.
- [DEPLOYMENTS.md](DEPLOYMENTS.md) — live addresses on Base Sepolia + local anvil.
- [TODO.md](TODO.md) — deferred items and open design questions.
- [frontend/DECISIONS.md](frontend/DECISIONS.md) — UI architecture decisions.
