"use client";

import { use } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { AdminPanel } from "@/components";
import { useVaultReads } from "@/hooks";
import { VAULTS, type VaultKey } from "@/config/contracts";

export default function AdminPage({
  params,
}: {
  params: Promise<{ key: string }>;
}) {
  const { key } = use(params);
  if (!(key in VAULTS)) notFound();
  const vaultKey = key as VaultKey;
  const vaultConfig = VAULTS[vaultKey];
  const vaultAddress = vaultConfig.vault as `0x${string}`;

  const { strategyCount, assetDecimals, assetAddress } =
    useVaultReads(vaultAddress);

  // Vault selector: each target-date vault has its own AccessControl +
  // registry, so the admin UI has to point at one vault explicitly.
  const allKeys = Object.keys(VAULTS) as VaultKey[];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <Link
            href={`/vault/${vaultKey}`}
            className="text-xs text-zinc-500 hover:text-zinc-300 transition-colors"
          >
            ← Back to vault
          </Link>
          <h1 className="mt-1 text-2xl font-bold text-white">
            Admin · {vaultConfig.label}
          </h1>
          <p className="mt-1 text-sm text-zinc-500">
            Controls are visible to everyone but write actions require the
            appropriate role on this vault. Buttons are disabled unless the
            connected wallet holds DEFAULT_ADMIN_ROLE or AUTHORITY_ROLE.
          </p>
        </div>
        <nav className="flex gap-2">
          {allKeys.map((k) => (
            <Link
              key={k}
              href={`/admin/${k}`}
              className={`rounded-lg border px-3 py-1.5 text-xs ${
                k === vaultKey
                  ? "border-blue-500 bg-blue-500/10 text-blue-200"
                  : "border-zinc-800 bg-zinc-900/50 text-zinc-400 hover:bg-zinc-800"
              }`}
            >
              {VAULTS[k].label}
            </Link>
          ))}
        </nav>
      </div>

      {assetAddress ? (
        <AdminPanel
          strategyCount={strategyCount}
          assetDecimals={assetDecimals}
          vaultAddress={vaultAddress}
          assetAddress={assetAddress as `0x${string}`}
        />
      ) : (
        <div className="text-sm text-zinc-500">Loading vault state…</div>
      )}
    </div>
  );
}
