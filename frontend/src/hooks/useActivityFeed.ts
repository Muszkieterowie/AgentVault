import { usePublicClient } from "wagmi";
import { useEffect, useState, useCallback } from "react";
import { decodeEventLog } from "viem";
import { VaultABI, StrategyABI } from "@/abi";
import { VAULT_ADDRESS } from "@/config/wagmi";
import type { Log } from "viem";

const LOOKBACK =
    Number(process.env.NEXT_PUBLIC_LOG_LOOKBACK_BLOCKS) || 10;

export interface ActivityRow {
    eventName: string;
    contractAddress: `0x${string}`;
    blockNumber: bigint;
    transactionHash: `0x${string}`;
    logIndex: number;
}

export function useActivityFeed(strategyAddresses: `0x${string}`[]) {
    const client = usePublicClient();
    const [rows, setRows] = useState<ActivityRow[]>([]);
    const [loading, setLoading] = useState(false);

    const fetchLogs = useCallback(async () => {
        if (!client) return;
        setLoading(true);
        try {
            const block = await client.getBlockNumber();
            const fromBlock = block > BigInt(LOOKBACK) ? block - BigInt(LOOKBACK) : 0n;

            const allAddresses = [
                VAULT_ADDRESS,
                ...strategyAddresses,
            ].filter(Boolean);

            const logs = await client.getLogs({
                address: allAddresses as `0x${string}`[],
                fromBlock,
                toBlock: block,
            });

            const decoded: ActivityRow[] = logs.map((log) => {
                let eventName = "Unknown";

                for (const abi of [...VaultABI, ...StrategyABI]) {
                    if (abi.type !== "event") continue;
                    try {
                        const result = decodeEventLog({
                            abi: [abi],
                            data: log.data,
                            topics: log.topics,
                        });
                        eventName = result.eventName;
                        break;
                    } catch { }
                }

                return {
                    eventName,
                    contractAddress: log.address as `0x${string}`,
                    blockNumber: log.blockNumber ?? 0n,
                    transactionHash: log.transactionHash ?? ("0x" as `0x${string}`),
                    logIndex: log.logIndex ?? 0,
                };
            });

            setRows(decoded.slice(-30).reverse());
        } catch (err) {
            console.error("Failed to fetch logs:", err);
        } finally {
            setLoading(false);
        }
    }, [client, strategyAddresses]);

    useEffect(() => {
        fetchLogs();
        const interval = setInterval(fetchLogs, 15_000);
        return () => clearInterval(interval);
    }, [fetchLogs]);

    return { rows, loading, refetch: fetchLogs };
}
