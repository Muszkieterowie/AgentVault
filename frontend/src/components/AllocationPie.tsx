"use client";

import { useMemo, useRef } from "react";
import { formatUnits } from "viem";
import {
  Chart as ChartJS,
  ArcElement,
  Tooltip,
  Legend,
  type ChartOptions,
} from "chart.js";
import { Doughnut } from "react-chartjs-2";
import { useStrategies, useIdleBalance } from "@/hooks";

ChartJS.register(ArcElement, Tooltip, Legend);

interface Props {
  strategyCount: number;
  decimals: number;
  assetAddress?: `0x${string}`;
  vaultAddress?: `0x${string}`;
}

interface Slice {
  label: string;
  value: number;
  color: string;
}

export function AllocationPie({
  strategyCount,
  decimals,
  assetAddress,
  vaultAddress,
}: Props) {
  const { strategies } = useStrategies(strategyCount, vaultAddress);
  const idle = useIdleBalance(assetAddress, vaultAddress);
  const chartRef = useRef<ChartJS<"doughnut">>(null);

  const slices: Slice[] = useMemo(() => {
    const items: Slice[] = [];
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

  const data = {
    labels: slices.map((s) => s.label),
    datasets: [
      {
        data: slices.map((s) => s.value),
        backgroundColor: slices.map((s) => s.color),
        hoverBackgroundColor: slices.map((s) => s.color),
        borderColor: "#18181b",
        borderWidth: 2,
        borderRadius: 6,
        hoverOffset: 12,
        spacing: 3,
      },
    ],
  };

  const options: ChartOptions<"doughnut"> = {
    responsive: true,
    maintainAspectRatio: true,
    cutout: "55%",
    animation: {
      animateRotate: true,
      animateScale: true,
      duration: 800,
      easing: "easeOutQuart",
    },
    plugins: {
      legend: {
        position: "bottom",
        labels: {
          color: "#d4d4d8",
          padding: 16,
          usePointStyle: true,
          pointStyle: "circle",
          font: { size: 13 },
        },
      },
      tooltip: {
        backgroundColor: "#27272a",
        titleColor: "#e4e4e7",
        bodyColor: "#a1a1aa",
        borderColor: "#3f3f46",
        borderWidth: 1,
        cornerRadius: 8,
        padding: 12,
        callbacks: {
          label(ctx) {
            const val = ctx.parsed;
            const pct = ((val / total) * 100).toFixed(1);
            return ` ${val.toLocaleString(undefined, {
              maximumFractionDigits: 2,
            })} (${pct}%)`;
          },
        },
      },
    },
  };

  /* Center text plugin */
  const centerTextPlugin = {
    id: "centerText",
    afterDraw(chart: ChartJS<"doughnut">) {
      const { ctx, width, height } = chart;
      ctx.save();
      const centerX = width / 2;
      const centerY = height / 2 - 16;

      ctx.font = "500 12px ui-sans-serif, system-ui, sans-serif";
      ctx.fillStyle = "#a1a1aa";
      ctx.textAlign = "center" as CanvasTextAlign;
      ctx.textBaseline = "middle" as CanvasTextBaseline;
      ctx.fillText("Total", centerX, centerY);

      ctx.font = "600 16px ui-sans-serif, system-ui, sans-serif";
      ctx.fillStyle = "#e4e4e7";
      ctx.fillText(
        total.toLocaleString(undefined, { maximumFractionDigits: 2 }),
        centerX,
        centerY + 18
      );
      ctx.restore();
    },
  };

  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-6">
      <h3 className="mb-4 text-sm font-medium text-zinc-400 uppercase tracking-wide">
        Allocation
      </h3>
      <div className="flex items-center justify-center">
        <div className="w-72">
          <Doughnut
            ref={chartRef}
            data={data}
            options={options}
            plugins={[centerTextPlugin]}
          />
        </div>
      </div>
    </div>
  );
}
