"use client";

import { formatUnits } from "viem";
import { useVaultReads, useAssetInfo } from "@/hooks";

export function StatsStrip({ vaultAddress }: { vaultAddress?: `0x${string}` }) {
  const {
    totalAssets,
    assetDecimals,
    sharePrice,
    userShares,
    userAssetsValue,
    assetAddress,
    isLoading,
  } = useVaultReads(vaultAddress);
  const { assetSymbol } = useAssetInfo(assetAddress);

  if (isLoading) {
    return (
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        {[...Array(4)].map((_, i) => (
          <div
            key={i}
            className="animate-pulse rounded-xl bg-zinc-900 p-4 h-20"
          />
        ))}
      </div>
    );
  }

  const stats = [
    {
      label: "Asset",
      value: assetSymbol ?? "—",
    },
    {
      label: "TVL",
      value: totalAssets
        ? `${Number(formatUnits(totalAssets, assetDecimals)).toLocaleString(
            undefined,
            { maximumFractionDigits: 2 }
          )} ${assetSymbol ?? ""}`
        : "—",
    },
    {
      label: "Share Price",
      value: sharePrice.toFixed(4),
    },
    {
      label: "Your Position",
      value:
        userShares !== undefined && userShares > 0n
          ? `${userAssetsValue.toLocaleString(undefined, {
              maximumFractionDigits: 2,
            })} ${assetSymbol ?? ""}`
          : "—",
    },
  ];

  return (
    <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
      {stats.map((s) => (
        <div
          key={s.label}
          className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-4"
        >
          <p className="text-xs text-zinc-500 uppercase tracking-wide">
            {s.label}
          </p>
          <p className="mt-1 text-lg font-semibold text-white">{s.value}</p>
        </div>
      ))}
    </div>
  );
}
