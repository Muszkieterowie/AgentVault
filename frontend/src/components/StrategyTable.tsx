"use client";

import { formatUnits } from "viem";
import { useStrategies, type StrategyInfo } from "@/hooks";
import { useState } from "react";
import Link from "next/link";

interface Props {
  strategyCount: number;
  // Asset (not share) decimals — Strategy.totalValue() is denominated in the
  // vault's underlying asset, so formatting against the share decimals would
  // underflow by 10^offset and display as 0.
  assetDecimals: number;
  vaultAddress?: `0x${string}`;
  hideNavigation?: boolean;
}

export function StrategyTable({
  strategyCount,
  assetDecimals,
  vaultAddress,
  hideNavigation,
}: Props) {
  const { strategies, isLoading } = useStrategies(strategyCount, vaultAddress);
  const [copiedAddress, setCopiedAddress] = useState<string | null>(null);

  const copyAddress = async (address: string) => {
    await navigator.clipboard.writeText(address);
    setCopiedAddress(address);
    setTimeout(() => setCopiedAddress(null), 2000);
  };

  if (isLoading) {
    return <div className="animate-pulse rounded-xl bg-zinc-900 p-4 h-40" />;
  }

  if (strategies.length === 0) {
    return (
      <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-6 text-center text-zinc-500">
        No strategies created yet
      </div>
    );
  }

  return (
    <div className="overflow-x-auto rounded-xl border border-zinc-800">
      <table className="w-full text-left text-sm">
        <thead className="border-b border-zinc-800 bg-zinc-900/80 text-xs uppercase text-zinc-500">
          <tr>
            <th className="px-4 py-3">ID</th>
            <th className="px-4 py-3">Address</th>
            <th className="px-4 py-3">Weight (bps)</th>
            <th className="px-4 py-3">Total Value</th>
            <th className="px-4 py-3">Status</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-800">
          {strategies.map((s) => (
            <tr
              key={s.id}
              className="bg-zinc-950 hover:bg-zinc-900/50 transition-colors"
            >
              <td className="px-4 py-3 font-mono text-zinc-300">{s.id}</td>
              <td className="px-4 py-3">
                {s.address ? (
                  <div className="flex items-center gap-2">
                    <span className="font-mono text-xs text-zinc-400">
                      {s.address}
                    </span>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        copyAddress(s.address!);
                      }}
                      className="rounded px-2 py-1 text-xs text-zinc-500 hover:bg-zinc-800 hover:text-zinc-300 transition-colors"
                      title="Copy address"
                    >
                      {copiedAddress === s.address ? "✓" : "⧉"}
                    </button>
                  </div>
                ) : (
                  <span className="text-zinc-500">—</span>
                )}
              </td>
              <td className="px-4 py-3 text-zinc-300">{s.weight.toString()}</td>
              <td className="px-4 py-3 text-zinc-300">
                {Number(formatUnits(s.totalValue, assetDecimals)).toLocaleString(
                  undefined,
                  { maximumFractionDigits: 2 }
                )}
              </td>
              <td className="px-4 py-3">
                {s.active ? (
                  <span className="rounded-full bg-green-900/50 px-2 py-0.5 text-xs text-green-400 ring-1 ring-green-800">
                    Active
                  </span>
                ) : (
                  <span className="rounded-full bg-red-900/50 px-2 py-0.5 text-xs text-red-400 ring-1 ring-red-800">
                    Inactive
                  </span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
