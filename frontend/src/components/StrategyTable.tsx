"use client";

import { formatUnits } from "viem";
import { useStrategies, type StrategyInfo } from "@/hooks";

interface Props {
  strategyCount: number;
  decimals: number;
}

export function StrategyTable({ strategyCount, decimals }: Props) {
  const { strategies, isLoading } = useStrategies(strategyCount);

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
            <tr key={s.id} className="bg-zinc-950 hover:bg-zinc-900/50">
              <td className="px-4 py-3 font-mono text-zinc-300">{s.id}</td>
              <td className="px-4 py-3 font-mono text-xs text-zinc-400">
                {s.address
                  ? `${s.address.slice(0, 6)}...${s.address.slice(-4)}`
                  : "—"}
              </td>
              <td className="px-4 py-3 text-zinc-300">{s.weight.toString()}</td>
              <td className="px-4 py-3 text-zinc-300">
                {Number(formatUnits(s.totalValue, decimals)).toLocaleString(
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
