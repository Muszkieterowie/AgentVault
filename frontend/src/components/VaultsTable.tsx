"use client";

import { formatUnits } from "viem";
import { useReadContracts } from "wagmi";
import { VaultABI, ERC20ABI } from "@/abi";
import { SHARED, VAULTS, type VaultKey } from "@/config/contracts";
import { useState } from "react";
import { useRouter } from "next/navigation";

const vaultKeys = Object.keys(VAULTS) as VaultKey[];

export function VaultsTable() {
  const [copiedAddress, setCopiedAddress] = useState<string | null>(null);
  const router = useRouter();

  const { data, isLoading } = useReadContracts({
    contracts: [
      ...vaultKeys.flatMap((key) => [
        {
          address: VAULTS[key].vault as `0x${string}`,
          abi: VaultABI,
          functionName: "totalAssets" as const,
        },
        {
          address: VAULTS[key].vault as `0x${string}`,
          abi: VaultABI,
          functionName: "strategyCount" as const,
        },
      ]),
      // TVL is asset-denominated, not share-denominated — formatting against
      // the vault's own decimals() underflows by 10^offset and reads "0".
      {
        address: SHARED.asset as `0x${string}`,
        abi: ERC20ABI,
        functionName: "decimals" as const,
      },
    ],
    query: { refetchInterval: 12_000 },
  });

  const assetDecimals = (data?.[vaultKeys.length * 2]?.result as number | undefined) ?? 18;

  const copyAddress = async (address: string) => {
    await navigator.clipboard.writeText(address);
    setCopiedAddress(address);
    setTimeout(() => setCopiedAddress(null), 2000);
  };

  if (isLoading) {
    return <div className="animate-pulse rounded-xl bg-zinc-900 p-4 h-40" />;
  }

  return (
    <div className="overflow-x-auto rounded-xl border border-zinc-800">
      <table className="w-full text-left text-sm">
        <thead className="border-b border-zinc-800 bg-zinc-900/80 text-xs uppercase text-zinc-500">
          <tr>
            <th className="px-4 py-3">Vault</th>
            <th className="px-4 py-3">Address</th>
            <th className="px-4 py-3">Share Symbol</th>
            <th className="px-4 py-3">TVL</th>
            <th className="px-4 py-3">Strategies</th>
            <th className="px-4 py-3">Deadline</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-800">
          {vaultKeys.map((key, idx) => {
            const v = VAULTS[key];
            const totalAssets = data?.[idx * 2]?.result as bigint | undefined;
            const strategyCount = data?.[idx * 2 + 1]?.result as
              | bigint
              | undefined;

            return (
              <tr
                key={key}
                onClick={() => router.push(`/vault/${key}`)}
                className="bg-zinc-950 hover:bg-zinc-900/50 cursor-pointer transition-colors"
              >
                <td className="px-4 py-3 font-semibold text-zinc-200">
                  {v.label}
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <span className="font-mono text-xs text-zinc-400">
                      {v.vault.slice(0, 6)}…{v.vault.slice(-4)}
                    </span>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        copyAddress(v.vault);
                      }}
                      className="rounded px-2 py-1 text-xs text-zinc-500 hover:bg-zinc-800 hover:text-zinc-300 transition-colors"
                      title="Copy address"
                    >
                      {copiedAddress === v.vault ? "✓" : "⧉"}
                    </button>
                  </div>
                </td>
                <td className="px-4 py-3 text-zinc-300">{v.shareSymbol}</td>
                <td className="px-4 py-3 text-zinc-300">
                  {totalAssets !== undefined
                    ? Number(formatUnits(totalAssets, assetDecimals)).toLocaleString(
                        undefined,
                        { maximumFractionDigits: 2 }
                      )
                    : "—"}
                </td>
                <td className="px-4 py-3 text-zinc-300">
                  {strategyCount !== undefined ? Number(strategyCount) : "—"}
                </td>
                <td className="px-4 py-3 text-zinc-400 text-xs">
                  {new Date(v.deadline * 1000).toLocaleDateString()}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
