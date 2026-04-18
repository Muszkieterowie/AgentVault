"use client";

import { StatsStrip, DepositForm, WithdrawForm } from "@/components";
import { useVaultReads, useAssetInfo } from "@/hooks";
import Link from "next/link";

export default function Vault() {
  const {
    vaultDecimals,
    assetAddress,
    userShares,
    sharePrice,
    refetch,
    vaultName,
  } = useVaultReads();
  const { assetSymbol, assetDecimals } = useAssetInfo(assetAddress);

  return (
    <div className="min-h-screen">
      {/* Header */}
      <div className="mb-8 flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-white mb-1">
            {vaultName || "Vault"}
          </h1>
          <p className="text-sm text-zinc-400">Manage your position</p>
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
        <StatsStrip />
      </div>

      {/* Forms */}
      <div className="max-w-5xl mx-auto grid gap-6 md:grid-cols-2">
        <DepositForm
          assetAddress={assetAddress}
          assetDecimals={assetDecimals}
          assetSymbol={assetSymbol}
          onSuccess={refetch}
        />
        <WithdrawForm
          vaultDecimals={vaultDecimals}
          assetSymbol={assetSymbol}
          userShares={userShares}
          sharePrice={sharePrice}
          onSuccess={refetch}
        />
      </div>
    </div>
  );
}
