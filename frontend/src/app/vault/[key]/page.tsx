"use client";

import { use } from "react";
import { notFound } from "next/navigation";
import {
  StatsStrip,
  DepositForm,
  WithdrawForm,
  StrategyTable,
  AllocationPie,
} from "@/components";
import { useVaultReads, useAssetInfo } from "@/hooks";
import { VAULTS, type VaultKey } from "@/config/contracts";
import Link from "next/link";

export default function VaultPage({
  params,
}: {
  params: Promise<{ key: string }>;
}) {
  const { key } = use(params);

  if (!(key in VAULTS)) {
    notFound();
  }
  const vaultKey = key as VaultKey;
  const vaultConfig = VAULTS[vaultKey];
  const vaultAddress = vaultConfig.vault as `0x${string}`;

  const {
    vaultDecimals,
    assetAddress,
    userShares,
    sharePrice,
    refetch,
    vaultName,
    strategyCount,
  } = useVaultReads(vaultAddress);
  const { assetSymbol, assetDecimals } = useAssetInfo(assetAddress);

  return (
    <div className="min-h-screen">
      {/* Header */}
      <div className="mb-8 flex items-center justify-between">
        <div>
          <Link
            href="/"
            className="text-xs text-zinc-500 hover:text-zinc-300 transition-colors mb-4 inline-block"
          >
            ← Back to Vaults
          </Link>
          <h1 className="text-3xl font-bold text-white mb-3">
            {vaultName || vaultConfig.label}
          </h1>
          <p className="text-sm text-zinc-400 mt-2">
            {vaultConfig.shareSymbol} · Deadline:{" "}
            {new Date(vaultConfig.deadline * 1000).toLocaleDateString()}
          </p>
        </div>
        <Link
          href="/admin"
          className="inline-flex items-center gap-2 rounded-xl border border-zinc-800 bg-zinc-900/50 px-4 py-2.5 text-sm font-medium text-zinc-300 transition-all hover:border-zinc-700 hover:bg-zinc-800/50"
        >
          <svg
            className="w-4 h-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
            />
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
            />
          </svg>
          Admin
        </Link>
      </div>

      {/* Stats Grid */}
      <div className="mb-8">
        <StatsStrip vaultAddress={vaultAddress} />
      </div>
      {/* Forms + Allocation Pie */}
      <div className="mx-auto grid gap-6 md:grid-cols-2">
        <div className="flex flex-col gap-6">
          <DepositForm
            assetAddress={assetAddress}
            assetDecimals={assetDecimals}
            assetSymbol={assetSymbol}
            vaultAddress={vaultAddress}
            onSuccess={refetch}
          />
          <WithdrawForm
            vaultDecimals={vaultDecimals}
            assetDecimals={assetDecimals}
            assetSymbol={assetSymbol}
            userShares={userShares}
            sharePrice={sharePrice}
            vaultAddress={vaultAddress}
            deadline={vaultConfig.deadline}
            onSuccess={refetch}
          />
        </div>
        <AllocationPie
          strategyCount={strategyCount}
          decimals={assetDecimals}
          assetAddress={assetAddress}
          vaultAddress={vaultAddress}
        />
      </div>

      {/* Strategies */}
      <div className="mb-8">
        <h2 className="text-lg font-semibold text-zinc-200 mb-3">Strategies</h2>
        <StrategyTable
          strategyCount={strategyCount}
          assetDecimals={assetDecimals}
          vaultAddress={vaultAddress}
          hideNavigation
        />
      </div>
    </div>
  );
}
