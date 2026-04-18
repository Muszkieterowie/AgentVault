"use client";

import { useState } from "react";
import {
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
} from "wagmi";
import {
  VaultABI,
  StrategyABI,
  ERC20ABI,
  YieldDripperABI,
  MockAavePoolABI,
} from "@/abi";
import {
  VAULT_ADDRESS,
  ASSET_ADDRESS,
  POOL_ADDRESS,
  ATOKEN_ADDRESS,
  DRIPPER_ADDRESS,
} from "@/config/wagmi";
import { useRoles, useStrategies, type StrategyInfo } from "@/hooks";
import { encodeFunctionData, maxUint256, toFunctionSelector } from "viem";

// Aave V3 pool selectors. Computed from the ABI so they stay in sync.
const SUPPLY_SELECTOR = toFunctionSelector(
  "supply(address,uint256,address,uint16)"
);
const WITHDRAW_SELECTOR = toFunctionSelector(
  "withdraw(address,uint256,address)"
);

// Calldata offsets for MockAavePool.supply(address,uint256,address,uint16):
//   [0..4)    selector
//   [4..36)   asset
//   [36..68)  amount
//   [68..100) onBehalfOf   → recipientOffset = 68
const SUPPLY_RECIPIENT_OFFSET = 68;

// For MockAavePool.withdraw(address,uint256,address):
//   [0..4)    selector
//   [4..36)   asset
//   [36..68)  amount       → amountOffset = 36
//   [68..100) to
const WITHDRAW_AMOUNT_OFFSET = 36;

const ACTION_PRESETS = [
  {
    label: "Aave V3: supply",
    target: POOL_ADDRESS,
    selector: SUPPLY_SELECTOR,
    recipientOffset: SUPPLY_RECIPIENT_OFFSET,
  },
  {
    label: "Aave V3: withdraw",
    target: POOL_ADDRESS,
    selector: WITHDRAW_SELECTOR,
    recipientOffset: 68,
  },
  {
    label: "Aave V3: borrow",
    target: POOL_ADDRESS,
    selector: "0xa415bcad" as `0x${string}`,
    recipientOffset: 0,
  },
  {
    label: "Aave V3: repay",
    target: POOL_ADDRESS,
    selector: "0x573ade81" as `0x${string}`,
    recipientOffset: 0,
  },
] as const;

interface AdminProps {
  strategyCount: number;
  // Asset (not share) decimals — rebalance() consumes asset units, and the
  // strategy totalValue display is also asset-denominated.
  assetDecimals: number;
}

export function AdminPanel({ strategyCount, assetDecimals }: AdminProps) {
  const { isAdmin, isAuthority } = useRoles();
  const { strategies, refetch } = useStrategies(strategyCount);

  return (
    <div className="space-y-8">
      <YieldDripperCard />
      <CreateStrategySection isAdmin={isAdmin} onSuccess={refetch} />
      {strategies.map((s) => (
        <StrategyAdmin
          key={s.id}
          strategy={s}
          assetDecimals={assetDecimals}
          isAdmin={isAdmin}
          isAuthority={isAuthority}
          onSuccess={refetch}
        />
      ))}
    </div>
  );
}

function YieldDripperCard() {
  const { writeContract, isPending, data: txHash } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const { data: isReady, refetch: refetchReady } = useReadContract({
    address: DRIPPER_ADDRESS,
    abi: YieldDripperABI,
    functionName: "isReady",
    query: { refetchInterval: 10_000 },
  });
  const { data: waitSec } = useReadContract({
    address: DRIPPER_ADDRESS,
    abi: YieldDripperABI,
    functionName: "timeUntilReady",
    query: { refetchInterval: 10_000 },
  });

  const secs = typeof waitSec === "bigint" ? Number(waitSec) : undefined;
  const label = isReady
    ? "Ready"
    : secs !== undefined
      ? `Ready in ${Math.floor(secs / 60)}m ${secs % 60}s`
      : "—";

  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-white">Yield Dripper</h2>
          <p className="mt-1 text-xs text-zinc-500">
            Mints demo-USDC yield into the aToken reserve on demand. Anyone can
            call when ready.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <span
            className={`rounded-full px-2.5 py-0.5 text-xs font-medium ${isReady
              ? "bg-green-900/50 text-green-300 ring-1 ring-green-800"
              : "bg-zinc-800 text-zinc-400"
              }`}
          >
            {label}
          </span>
          <button
            disabled={!isReady || isPending || isConfirming}
            onClick={() =>
              writeContract(
                {
                  address: DRIPPER_ADDRESS,
                  abi: YieldDripperABI,
                  functionName: "drip",
                },
                { onSuccess: () => refetchReady() }
              )
            }
            className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-emerald-500 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isPending || isConfirming ? "Dripping…" : "Drip"}
          </button>
        </div>
      </div>
    </div>
  );
}

function CreateStrategySection({
  isAdmin,
  onSuccess,
}: {
  isAdmin: boolean;
  onSuccess: () => void;
}) {
  const [delegate, setDelegate] = useState("");
  const { writeContract, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-6">
      <h2 className="mb-4 text-lg font-semibold text-white">Create Strategy</h2>
      <div className="flex gap-3">
        <input
          type="text"
          value={delegate}
          onChange={(e) => setDelegate(e.target.value)}
          placeholder="Delegate address (0x…)"
          className="flex-1 rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-2 text-sm text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
        />
        <button
          disabled={!isAdmin || !delegate || isPending || isConfirming}
          onClick={() =>
            writeContract(
              {
                address: VAULT_ADDRESS,
                abi: VaultABI,
                functionName: "createStrategy",
                args: [delegate as `0x${string}`],
              },
              {
                onSuccess: () => {
                  setDelegate("");
                  reset();
                  onSuccess();
                },
              }
            )
          }
          className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {isPending || isConfirming ? "Creating…" : "Create"}
        </button>
      </div>
      {!isAdmin && (
        <p className="mt-2 text-xs text-zinc-500">
          Requires DEFAULT_ADMIN_ROLE
        </p>
      )}
    </div>
  );
}

function StrategyAdmin({
  strategy,
  assetDecimals,
  isAdmin,
  isAuthority,
  onSuccess,
}: {
  strategy: StrategyInfo;
  assetDecimals: number;
  isAdmin: boolean;
  isAuthority: boolean;
  onSuccess: () => void;
}) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-6">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-white">
          Strategy {strategy.id}
        </h2>
        <div className="flex items-center gap-2">
          <span className="font-mono text-xs text-zinc-500">
            {strategy.address?.slice(0, 6)}...{strategy.address?.slice(-4)}
          </span>
          {strategy.active ? (
            <span className="rounded-full bg-green-900/50 px-2 py-0.5 text-xs text-green-400 ring-1 ring-green-800">
              Active
            </span>
          ) : (
            <span className="rounded-full bg-red-900/50 px-2 py-0.5 text-xs text-red-400 ring-1 ring-red-800">
              Inactive
            </span>
          )}
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <WeightEditor
          strategyId={strategy.id}
          currentWeight={strategy.weight}
          isAdmin={isAdmin}
          onSuccess={onSuccess}
        />
        <DelegateEditor strategyAddress={strategy.address} isAdmin={isAdmin} />
        <TrustedSpenderEditor
          strategyAddress={strategy.address}
          isAdmin={isAdmin}
        />
        <ApproveTokenEditor
          strategyAddress={strategy.address}
          isAdmin={isAdmin}
        />
        <AllowedActionEditor
          strategyAddress={strategy.address}
          isAdmin={isAdmin}
        />
        <ConfigEditor strategyAddress={strategy.address} isAdmin={isAdmin} />
        <ValueSourceEditor
          strategyAddress={strategy.address}
          isAdmin={isAdmin}
        />
        <RebalanceControl
          strategyId={strategy.id}
          assetDecimals={assetDecimals}
          isAuthority={isAuthority}
        />
        <DeactivateButton
          strategyId={strategy.id}
          active={strategy.active}
          isAdmin={isAdmin}
          onSuccess={onSuccess}
        />
      </div>
    </div>
  );
}

function WeightEditor({
  strategyId,
  currentWeight,
  isAdmin,
  onSuccess,
}: {
  strategyId: number;
  currentWeight: number;
  isAdmin: boolean;
  onSuccess: () => void;
}) {
  const [weight, setWeight] = useState(currentWeight.toString());
  const { writeContract, isPending } = useWriteContract();

  return (
    <div>
      <label className="mb-1 block text-xs font-medium text-zinc-400">
        Weight (bps, max 10000)
      </label>
      <div className="flex gap-2">
        <input
          type="range"
          min="0"
          max="10000"
          step="100"
          value={weight}
          onChange={(e) => setWeight(e.target.value)}
          className="flex-1"
        />
        <span className="w-16 text-right text-sm text-zinc-300">
          {weight} bps
        </span>
        <button
          disabled={!isAdmin || isPending}
          onClick={() =>
            writeContract(
              {
                address: VAULT_ADDRESS,
                abi: VaultABI,
                functionName: "setStrategyWeight",
                args: [BigInt(strategyId), Number(weight)],
              },
              { onSuccess }
            )
          }
          className="rounded bg-zinc-700 px-3 py-1 text-xs text-white hover:bg-zinc-600 disabled:opacity-50"
        >
          Save
        </button>
      </div>
    </div>
  );
}

function DelegateEditor({
  strategyAddress,
  isAdmin,
}: {
  strategyAddress: `0x${string}`;
  isAdmin: boolean;
}) {
  const [newDelegate, setNewDelegate] = useState("");
  const { writeContract, isPending } = useWriteContract();

  return (
    <div>
      <label className="mb-1 block text-xs font-medium text-zinc-400">
        Set Delegate
      </label>
      <div className="flex gap-2">
        <input
          type="text"
          value={newDelegate}
          onChange={(e) => setNewDelegate(e.target.value)}
          placeholder="0x…"
          className="flex-1 rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
        />
        <button
          disabled={!isAdmin || !newDelegate || isPending}
          onClick={() =>
            writeContract({
              address: strategyAddress,
              abi: StrategyABI,
              functionName: "setDelegate",
              args: [newDelegate as `0x${string}`],
            })
          }
          className="rounded bg-zinc-700 px-3 py-1 text-xs text-white hover:bg-zinc-600 disabled:opacity-50"
        >
          Set
        </button>
      </div>
    </div>
  );
}

function TrustedSpenderEditor({
  strategyAddress,
  isAdmin,
}: {
  strategyAddress: `0x${string}`;
  isAdmin: boolean;
}) {
  const [spender, setSpender] = useState(POOL_ADDRESS);
  const { writeContract, isPending } = useWriteContract();

  const call = (trusted: boolean) =>
    writeContract({
      address: strategyAddress,
      abi: StrategyABI,
      functionName: "setTrustedSpender",
      args: [spender as `0x${string}`, trusted],
    });

  return (
    <div className="space-y-2">
      <label className="block text-xs font-medium text-zinc-400">
        Trusted Spenders
      </label>
      <input
        type="text"
        value={spender}
        onChange={(e) => setSpender(e.target.value as `0x${string}`)}
        placeholder="Spender (0x…)"
        className="w-full rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
      />
      <div className="flex gap-2">
        <button
          disabled={!isAdmin || !spender || isPending}
          onClick={() => call(true)}
          className="rounded bg-green-700 px-3 py-1 text-xs text-white hover:bg-green-600 disabled:opacity-50"
        >
          Trust
        </button>
        <button
          disabled={!isAdmin || !spender || isPending}
          onClick={() => call(false)}
          className="rounded bg-red-700 px-3 py-1 text-xs text-white hover:bg-red-600 disabled:opacity-50"
        >
          Revoke
        </button>
      </div>
    </div>
  );
}

function ApproveTokenEditor({
  strategyAddress,
  isAdmin,
}: {
  strategyAddress: `0x${string}`;
  isAdmin: boolean;
}) {
  const [token, setToken] = useState<`0x${string}`>(ASSET_ADDRESS);
  const [spender, setSpender] = useState<`0x${string}`>(POOL_ADDRESS);
  const { writeContract, isPending } = useWriteContract();

  return (
    <div className="space-y-2">
      <label className="block text-xs font-medium text-zinc-400">
        Approve Token (strategy → spender)
      </label>
      <input
        type="text"
        value={token}
        onChange={(e) => setToken(e.target.value as `0x${string}`)}
        placeholder="Token (0x…)"
        className="w-full rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
      />
      <input
        type="text"
        value={spender}
        onChange={(e) => setSpender(e.target.value as `0x${string}`)}
        placeholder="Spender (0x…)"
        className="w-full rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
      />
      <div className="flex gap-2">
        <button
          disabled={!isAdmin || isPending}
          onClick={() =>
            writeContract({
              address: strategyAddress,
              abi: StrategyABI,
              functionName: "approveToken",
              args: [token, spender, maxUint256],
            })
          }
          className="rounded bg-blue-700 px-3 py-1 text-xs text-white hover:bg-blue-600 disabled:opacity-50"
        >
          Approve max
        </button>
        <button
          disabled={!isAdmin || isPending}
          onClick={() =>
            writeContract({
              address: strategyAddress,
              abi: StrategyABI,
              functionName: "approveToken",
              args: [token, spender, 0n],
            })
          }
          className="rounded bg-zinc-700 px-3 py-1 text-xs text-white hover:bg-zinc-600 disabled:opacity-50"
        >
          Revoke
        </button>
      </div>
    </div>
  );
}

function AllowedActionEditor({
  strategyAddress,
  isAdmin,
}: {
  strategyAddress: `0x${string}`;
  isAdmin: boolean;
}) {
  const [target, setTarget] = useState<string>("");
  const [selector, setSelector] = useState<string>("");
  const [recipientOffset, setRecipientOffset] = useState("0");
  const { writeContract, isPending } = useWriteContract();

  const applyPreset = (p: (typeof ACTION_PRESETS)[number]) => {
    setTarget(p.target);
    setSelector(p.selector);
    setRecipientOffset(String(p.recipientOffset));
  };

  return (
    <div className="space-y-2">
      <label className="block text-xs font-medium text-zinc-400">
        Whitelist Actions
      </label>
      <div className="flex flex-wrap gap-1">
        {ACTION_PRESETS.map((p) => (
          <button
            key={p.label}
            type="button"
            onClick={() => applyPreset(p)}
            className={`rounded px-2 py-0.5 text-xs ${selector === p.selector && target === p.target
              ? "bg-blue-600 text-white"
              : "bg-zinc-800 text-zinc-400 hover:bg-zinc-700"
              }`}
          >
            {p.label}
          </button>
        ))}
      </div>
      <input
        type="text"
        value={target}
        onChange={(e) => setTarget(e.target.value)}
        placeholder="Target contract (0x…)"
        className="w-full rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
      />
      <div className="flex gap-2">
        <input
          type="text"
          value={selector}
          onChange={(e) => setSelector(e.target.value)}
          placeholder="Selector (0x…)"
          className="flex-1 rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
        />
        <input
          type="number"
          value={recipientOffset}
          onChange={(e) => setRecipientOffset(e.target.value)}
          placeholder="recipientOffset"
          className="w-24 rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
        />
      </div>
      <div className="flex gap-2">
        <button
          disabled={!isAdmin || !target || !selector || isPending}
          onClick={() =>
            writeContract({
              address: strategyAddress,
              abi: StrategyABI,
              functionName: "addAllowedAction",
              args: [
                target as `0x${string}`,
                selector as `0x${string}`,
                Number(recipientOffset || "0"),
              ],
            })
          }
          className="rounded bg-green-700 px-3 py-1 text-xs text-white hover:bg-green-600 disabled:opacity-50"
        >
          Add
        </button>
        <button
          disabled={!isAdmin || !target || !selector || isPending}
          onClick={() =>
            writeContract({
              address: strategyAddress,
              abi: StrategyABI,
              functionName: "removeAllowedAction",
              args: [target as `0x${string}`, selector as `0x${string}`],
            })
          }
          className="rounded bg-red-700 px-3 py-1 text-xs text-white hover:bg-red-600 disabled:opacity-50"
        >
          Remove
        </button>
      </div>
    </div>
  );
}

function ConfigEditor({
  strategyAddress,
  isAdmin,
}: {
  strategyAddress: `0x${string}`;
  isAdmin: boolean;
}) {
  const [configTarget, setConfigTarget] = useState<string>(POOL_ADDRESS);
  const [configData, setConfigData] = useState("");
  const [amountOffset, setAmountOffset] = useState(
    String(WITHDRAW_AMOUNT_OFFSET)
  );
  const { writeContract, isPending } = useWriteContract();

  // Preset: Aave withdraw(asset, 0, strategy). The vault rewrites the
  // amount field at amountOffset=36 before executing.
  const applyAaveWithdrawPreset = () => {
    const data = encodeFunctionData({
      abi: MockAavePoolABI,
      functionName: "withdraw",
      args: [ASSET_ADDRESS, 0n, strategyAddress],
    });
    setConfigTarget(POOL_ADDRESS);
    setConfigData(data);
    setAmountOffset(String(WITHDRAW_AMOUNT_OFFSET));
  };

  // Preset: Aave supply(asset, 0, strategy, 0). amountOffset=36.
  const applyAaveSupplyPreset = () => {
    const data = encodeFunctionData({
      abi: MockAavePoolABI,
      functionName: "supply",
      args: [ASSET_ADDRESS, 0n, strategyAddress, 0],
    });
    setConfigTarget(POOL_ADDRESS);
    setConfigData(data);
    setAmountOffset("36");
  };

  return (
    <div className="space-y-2">
      <label className="block text-xs font-medium text-zinc-400">
        Deposit / Withdraw Config
      </label>
      <div className="flex flex-wrap gap-1">
        <button
          type="button"
          onClick={applyAaveSupplyPreset}
          className="rounded bg-zinc-800 px-2 py-0.5 text-xs text-zinc-400 hover:bg-zinc-700"
        >
          Preset: Aave supply
        </button>
        <button
          type="button"
          onClick={applyAaveWithdrawPreset}
          className="rounded bg-zinc-800 px-2 py-0.5 text-xs text-zinc-400 hover:bg-zinc-700"
        >
          Preset: Aave withdraw
        </button>
      </div>
      <input
        type="text"
        value={configTarget}
        onChange={(e) => setConfigTarget(e.target.value)}
        placeholder="Target (0x…)"
        className="w-full rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
      />
      <input
        type="text"
        value={configData}
        onChange={(e) => setConfigData(e.target.value)}
        placeholder="Calldata (0x…)"
        className="w-full rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
      />
      <div className="flex gap-2">
        <input
          type="number"
          value={amountOffset}
          onChange={(e) => setAmountOffset(e.target.value)}
          placeholder="amountOffset"
          className="w-28 rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
        />
        <span className="flex-1 self-center text-xs text-zinc-600">
          byte offset of the amount word in calldata
        </span>
      </div>
      <div className="flex flex-wrap gap-2">
        <button
          disabled={!isAdmin || !configTarget || !configData || isPending}
          onClick={() =>
            writeContract({
              address: strategyAddress,
              abi: StrategyABI,
              functionName: "setDepositConfig",
              args: [
                configTarget as `0x${string}`,
                configData as `0x${string}`,
                Number(amountOffset || "0"),
              ],
            })
          }
          className="rounded bg-blue-700 px-3 py-1 text-xs text-white hover:bg-blue-600 disabled:opacity-50"
        >
          Set Deposit
        </button>
        <button
          disabled={!isAdmin || !configTarget || !configData || isPending}
          onClick={() =>
            writeContract({
              address: strategyAddress,
              abi: StrategyABI,
              functionName: "setWithdrawConfig",
              args: [
                configTarget as `0x${string}`,
                configData as `0x${string}`,
                Number(amountOffset || "0"),
              ],
            })
          }
          className="rounded bg-blue-700 px-3 py-1 text-xs text-white hover:bg-blue-600 disabled:opacity-50"
        >
          Set Withdraw
        </button>
        <button
          disabled={!isAdmin || isPending}
          onClick={() =>
            writeContract({
              address: strategyAddress,
              abi: StrategyABI,
              functionName: "removeDepositConfig",
            })
          }
          className="rounded bg-red-700 px-3 py-1 text-xs text-white hover:bg-red-600 disabled:opacity-50"
        >
          Remove Deposit
        </button>
        <button
          disabled={!isAdmin || isPending}
          onClick={() =>
            writeContract({
              address: strategyAddress,
              abi: StrategyABI,
              functionName: "removeWithdrawConfig",
            })
          }
          className="rounded bg-red-700 px-3 py-1 text-xs text-white hover:bg-red-600 disabled:opacity-50"
        >
          Remove Withdraw
        </button>
      </div>
    </div>
  );
}

function ValueSourceEditor({
  strategyAddress,
  isAdmin,
}: {
  strategyAddress: `0x${string}`;
  isAdmin: boolean;
}) {
  const [vsTarget, setVsTarget] = useState<string>(ATOKEN_ADDRESS);
  const [vsData, setVsData] = useState("");
  const [removeIndex, setRemoveIndex] = useState("");
  const { writeContract, isPending } = useWriteContract();

  // Preset: aToken.balanceOf(strategy) — reads protocol receipt balance.
  const applyATokenBalancePreset = () => {
    const data = encodeFunctionData({
      abi: ERC20ABI,
      functionName: "balanceOf",
      args: [strategyAddress],
    });
    setVsTarget(ATOKEN_ADDRESS);
    setVsData(data);
  };

  return (
    <div className="space-y-2">
      <label className="block text-xs font-medium text-zinc-400">
        Value Sources
      </label>
      <div className="flex flex-wrap gap-1">
        <button
          type="button"
          onClick={applyATokenBalancePreset}
          className="rounded bg-zinc-800 px-2 py-0.5 text-xs text-zinc-400 hover:bg-zinc-700"
        >
          Preset: aToken balanceOf(strategy)
        </button>
      </div>
      <input
        type="text"
        value={vsTarget}
        onChange={(e) => setVsTarget(e.target.value)}
        placeholder="Target (0x…)"
        className="w-full rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
      />
      <input
        type="text"
        value={vsData}
        onChange={(e) => setVsData(e.target.value)}
        placeholder="Calldata (0x…)"
        className="w-full rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
      />
      <div className="flex gap-2">
        <button
          disabled={!isAdmin || !vsTarget || !vsData || isPending}
          onClick={() =>
            writeContract({
              address: strategyAddress,
              abi: StrategyABI,
              functionName: "addValueSource",
              args: [vsTarget as `0x${string}`, vsData as `0x${string}`],
            })
          }
          className="rounded bg-green-700 px-3 py-1 text-xs text-white hover:bg-green-600 disabled:opacity-50"
        >
          Add Source
        </button>
        <input
          type="number"
          value={removeIndex}
          onChange={(e) => setRemoveIndex(e.target.value)}
          placeholder="Index"
          className="w-16 rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
        />
        <button
          disabled={!isAdmin || removeIndex === "" || isPending}
          onClick={() =>
            writeContract({
              address: strategyAddress,
              abi: StrategyABI,
              functionName: "removeValueSource",
              args: [BigInt(removeIndex)],
            })
          }
          className="rounded bg-red-700 px-3 py-1 text-xs text-white hover:bg-red-600 disabled:opacity-50"
        >
          Remove
        </button>
      </div>
    </div>
  );
}

function RebalanceControl({
  strategyId,
  assetDecimals,
  isAuthority,
}: {
  strategyId: number;
  assetDecimals: number;
  isAuthority: boolean;
}) {
  const [delta, setDelta] = useState("");
  const [direction, setDirection] = useState<"push" | "pull">("push");
  const { writeContract, isPending } = useWriteContract();

  const handleRebalance = () => {
    if (!delta) return;
    const rawDelta = BigInt(Math.round(parseFloat(delta) * 10 ** assetDecimals));
    const signedDelta = direction === "pull" ? -rawDelta : rawDelta;

    writeContract({
      address: VAULT_ADDRESS,
      abi: VaultABI,
      functionName: "rebalance",
      args: [BigInt(strategyId), signedDelta],
    });
  };

  return (
    <div className="space-y-2">
      <label className="block text-xs font-medium text-zinc-400">
        Rebalance
      </label>
      <div className="flex items-center gap-2">
        <label className="flex items-center gap-1 text-xs text-zinc-300">
          <input
            type="radio"
            name={`dir-${strategyId}`}
            checked={direction === "push"}
            onChange={() => setDirection("push")}
          />
          Push
        </label>
        <label className="flex items-center gap-1 text-xs text-zinc-300">
          <input
            type="radio"
            name={`dir-${strategyId}`}
            checked={direction === "pull"}
            onChange={() => setDirection("pull")}
          />
          Pull
        </label>
      </div>
      <div className="flex gap-2">
        <input
          type="text"
          inputMode="decimal"
          value={delta}
          onChange={(e) => setDelta(e.target.value)}
          placeholder="Amount"
          className="flex-1 rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-xs text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none"
        />
        <button
          disabled={!isAuthority || !delta || isPending}
          onClick={handleRebalance}
          className="rounded bg-amber-700 px-3 py-1 text-xs text-white hover:bg-amber-600 disabled:opacity-50"
        >
          Rebalance
        </button>
      </div>
      {!isAuthority && (
        <p className="text-xs text-zinc-500">Requires AUTHORITY_ROLE</p>
      )}
    </div>
  );
}

function DeactivateButton({
  strategyId,
  active,
  isAdmin,
  onSuccess,
}: {
  strategyId: number;
  active: boolean;
  isAdmin: boolean;
  onSuccess: () => void;
}) {
  const { writeContract, isPending } = useWriteContract();

  if (!active) return null;

  return (
    <div>
      <button
        disabled={!isAdmin || isPending}
        onClick={() =>
          writeContract(
            {
              address: VAULT_ADDRESS,
              abi: VaultABI,
              functionName: "deactivateStrategy",
              args: [BigInt(strategyId)],
            },
            { onSuccess }
          )
        }
        className="rounded bg-red-800 px-4 py-2 text-xs font-medium text-white hover:bg-red-700 disabled:opacity-50"
      >
        Deactivate Strategy (permanent)
      </button>
      {!isAdmin && (
        <p className="mt-1 text-xs text-zinc-500">
          Requires DEFAULT_ADMIN_ROLE
        </p>
      )}
    </div>
  );
}
