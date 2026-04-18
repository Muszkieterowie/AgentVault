import { usePublicClient } from "wagmi";
import { useEffect, useState, useCallback } from "react";
import { decodeEventLog, formatUnits } from "viem";
import { VaultABI, StrategyABI, YieldDripperABI } from "@/abi";
import { VAULT_ADDRESS, DRIPPER_ADDRESS } from "@/config/wagmi";

const LOOKBACK = Number(process.env.NEXT_PUBLIC_LOG_LOOKBACK_BLOCKS) || 500;

export interface ActivityRow {
    eventName: string;
    contractAddress: `0x${string}`;
    blockNumber: bigint;
    transactionHash: `0x${string}`;
    logIndex: number;
    /** Human-readable one-line summary, already decoded. */
    summary: string;
}

const short = (addr: string) =>
    `${addr.slice(0, 6)}…${addr.slice(-4)}`;

/** Convert a bigint-of-asset-decimals into a short decimal string. */
const fmt = (value: unknown, decimals = 6): string => {
    if (typeof value !== "bigint") return String(value);
    const n = Number(formatUnits(value, decimals));
    return n.toLocaleString(undefined, { maximumFractionDigits: 4 });
};

/** Build a short human-readable string for a decoded event. */
function summarize(eventName: string, args: Record<string, unknown>): string {
    switch (eventName) {
        case "Deposit":
            return `${short(String(args.owner))} deposited ${fmt(args.assets)} → ${fmt(args.shares, 6)} shares`;
        case "Withdraw":
            return `${short(String(args.owner))} withdrew ${fmt(args.assets)} (${fmt(args.shares, 6)} shares)`;
        case "StrategyCreated":
            return `Strategy #${args.strategyId} created at ${short(String(args.strategy))} (delegate ${short(String(args.delegate))})`;
        case "StrategyWeightSet":
            return `Strategy #${args.strategyId} weight: ${args.oldWeightBps} → ${args.newWeightBps} bps`;
        case "StrategyDeactivated":
            return `Strategy #${args.strategyId} deactivated`;
        case "Rebalanced": {
            const delta = args.delta as bigint;
            const sign = delta < 0n ? "pull" : "push";
            const abs = delta < 0n ? -delta : delta;
            return `Rebalance #${args.strategyId}: ${sign} ${fmt(abs)} (actual ${fmt(args.actual)})`;
        }
        case "AuthoritySet":
            return `Authority: ${short(String(args.oldAuthority))} → ${short(String(args.newAuthority))}`;
        case "ActionExecuted":
            return `Action on ${short(String(args.target))} selector ${String(args.selector)}`;
        case "AllowedActionAdded":
            return `Whitelisted ${String(args.selector)} on ${short(String(args.target))} (recipientOffset ${args.recipientOffset})`;
        case "AllowedActionRemoved":
            return `Unwhitelisted ${String(args.selector)} on ${short(String(args.target))}`;
        case "DelegateUpdated":
            return `Delegate: ${short(String(args.oldDelegate))} → ${short(String(args.newDelegate))}`;
        case "DepositConfigSet":
            return `Deposit config → ${short(String(args.target))}`;
        case "WithdrawConfigSet":
            return `Withdraw config → ${short(String(args.target))}`;
        case "DepositConfigRemoved":
            return "Deposit config removed";
        case "WithdrawConfigRemoved":
            return "Withdraw config removed";
        case "ValueSourceAdded":
            return `Value source #${args.index} → ${short(String(args.target))}`;
        case "ValueSourceRemoved":
            return `Value source #${args.index} removed`;
        case "TokenApproved":
            return `${short(String(args.caller))} approved ${fmt(args.amount)} of ${short(String(args.token))} to ${short(String(args.spender))}`;
        case "TrustedSpenderSet":
            return `Trusted spender ${short(String(args.spender))}: ${args.trusted ? "on" : "off"}`;
        case "Dripped":
            return `Yield dripped ${fmt(args.amount)}`;
        default:
            return eventName;
    }
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
                DRIPPER_ADDRESS,
                ...strategyAddresses,
            ].filter(Boolean);

            const logs = await client.getLogs({
                address: allAddresses as `0x${string}`[],
                fromBlock,
                toBlock: block,
            });

            const mergedAbi = [...VaultABI, ...StrategyABI, ...YieldDripperABI];

            const decoded: ActivityRow[] = logs.map((log) => {
                let eventName = "Unknown";
                let summary = "Unknown event";

                for (const entry of mergedAbi) {
                    if (entry.type !== "event") continue;
                    try {
                        const result = decodeEventLog({
                            abi: [entry],
                            data: log.data,
                            topics: log.topics,
                        });
                        eventName = result.eventName;
                        summary = summarize(
                            eventName,
                            (result.args ?? {}) as Record<string, unknown>
                        );
                        break;
                    } catch { }
                }

                return {
                    eventName,
                    summary,
                    contractAddress: log.address as `0x${string}`,
                    blockNumber: log.blockNumber ?? 0n,
                    transactionHash: log.transactionHash ?? ("0x" as `0x${string}`),
                    logIndex: log.logIndex ?? 0,
                };
            });

            // Newest first, cap to 30.
            decoded.sort((a, b) => {
                if (a.blockNumber !== b.blockNumber) {
                    return a.blockNumber < b.blockNumber ? 1 : -1;
                }
                return b.logIndex - a.logIndex;
            });
            setRows(decoded.slice(0, 30));
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
