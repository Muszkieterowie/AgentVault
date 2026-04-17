"use client";

import { useMemo } from "react";
import { formatUnits } from "viem";
import { useStrategies, useIdleBalance } from "@/hooks";

interface Props {
  strategyCount: number;
  decimals: number;
  assetAddress?: `0x${string}`;
}

export function AllocationPie({
  strategyCount,
  decimals,
  assetAddress,
}: Props) {
  const { strategies } = useStrategies(strategyCount);
  const idle = useIdleBalance(assetAddress);

  const slices = useMemo(() => {
    const items: { label: string; value: number; color: string }[] = [];
    const colors = [
      "#3b82f6",
      "#8b5cf6",
      "#ec4899",
      "#f59e0b",
      "#10b981",
      "#06b6d4",
      "#f97316",
      "#6366f1",
    ];

    const idleVal = Number(formatUnits(idle, decimals));
    if (idleVal > 0) {
      items.push({ label: "Idle", value: idleVal, color: "#71717a" });
    }

    strategies.forEach((s, i) => {
      const val = Number(formatUnits(s.totalValue, decimals));
      if (val > 0 || s.active) {
        items.push({
          label: `Strategy ${s.id}`,
          value: val,
          color: colors[i % colors.length],
        });
      }
    });

    return items;
  }, [strategies, idle, decimals]);

  const total = slices.reduce((sum, s) => sum + s.value, 0);

  if (total === 0) {
    return (
      <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-6 text-center text-zinc-500">
        No allocation data
      </div>
    );
  }

  // Simple CSS-based pie using conic-gradient
  let cumulative = 0;
  const stops = slices
    .map((s) => {
      const start = cumulative;
      cumulative += (s.value / total) * 360;
      return `${s.color} ${start}deg ${cumulative}deg`;
    })
    .join(", ");

  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-6">
      <h3 className="mb-4 text-sm font-medium text-zinc-400 uppercase tracking-wide">
        Allocation
      </h3>
      <div className="flex items-center gap-6">
        <div
          className="h-40 w-40 shrink-0 rounded-full"
          style={{ background: `conic-gradient(${stops})` }}
        />
        <div className="flex flex-col gap-2">
          {slices.map((s) => (
            <div key={s.label} className="flex items-center gap-2 text-sm">
              <div
                className="h-3 w-3 rounded-full"
                style={{ backgroundColor: s.color }}
              />
              <span className="text-zinc-300">{s.label}</span>
              <span className="text-zinc-500">
                {s.value.toLocaleString(undefined, {
                  maximumFractionDigits: 2,
                })}{" "}
                ({((s.value / total) * 100).toFixed(1)}%)
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
