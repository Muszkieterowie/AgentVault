"use client";

import { useActivityFeed } from "@/hooks";

interface Props {
  strategyAddresses: `0x${string}`[];
}

export function ActivityFeed({ strategyAddresses }: Props) {
  const { rows, loading } = useActivityFeed(strategyAddresses);

  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-900/50">
      <div className="flex items-center justify-between border-b border-zinc-800 px-4 py-3">
        <h3 className="text-sm font-medium text-zinc-400 uppercase tracking-wide">
          Recent Activity
        </h3>
        {loading && (
          <div className="h-2 w-2 animate-pulse rounded-full bg-blue-500" />
        )}
      </div>
      {rows.length === 0 ? (
        <p className="p-4 text-center text-sm text-zinc-600">
          No recent events
        </p>
      ) : (
        <div className="max-h-80 overflow-y-auto">
          <table className="w-full text-left text-xs">
            <thead className="sticky top-0 bg-zinc-900 text-zinc-500 uppercase">
              <tr>
                <th className="px-4 py-2">Event</th>
                <th className="px-4 py-2">Details</th>
                <th className="px-4 py-2">Block</th>
                <th className="px-4 py-2">Tx</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800/50">
              {rows.map((r) => (
                <tr
                  key={`${r.transactionHash}-${r.logIndex}`}
                  className="hover:bg-zinc-900/50"
                >
                  <td className="px-4 py-2 font-medium text-zinc-300 whitespace-nowrap">
                    {r.eventName}
                  </td>
                  <td className="px-4 py-2 text-zinc-400">{r.summary}</td>
                  <td className="px-4 py-2 text-zinc-500 whitespace-nowrap">
                    {r.blockNumber.toString()}
                  </td>
                  <td className="px-4 py-2 font-mono text-zinc-500 whitespace-nowrap">
                    <a
                      href={`https://sepolia.basescan.org/tx/${r.transactionHash}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="hover:text-blue-400"
                    >
                      {r.transactionHash.slice(0, 8)}…
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
