import { useReadContracts } from "wagmi";
import { useMemo } from "react";
import { StrategyABI } from "@/abi";

export interface AllowedActionEntry {
    target: `0x${string}`;
    selector: `0x${string}`;
    recipientOffset: number;
    /** Optional human-readable label if the (target, selector) is a known preset. */
    label?: string;
}

export interface AllowedActionCandidate {
    target: `0x${string}`;
    selector: `0x${string}`;
    label?: string;
}

/**
 * Strategy has no enumerable whitelist view. Enumerating via events would be
 * ideal but public Base Sepolia RPCs cap `eth_getLogs` to a 500-block window
 * — deploy-time entries sit far outside that. Instead we multicall the known
 * `allowedActions(target, selector)` view for each candidate the caller
 * knows about (presets, plus anything surfaced in the current session) and
 * filter to the ones currently active.
 */
export function useAllowedActions(
    strategyAddress: `0x${string}` | undefined,
    candidates: readonly AllowedActionCandidate[]
) {
    const { data, isLoading, refetch } = useReadContracts({
        contracts: strategyAddress
            ? candidates.map((c) => ({
                address: strategyAddress,
                abi: StrategyABI,
                functionName: "allowedActions" as const,
                args: [c.target, c.selector] as const,
            }))
            : [],
        query: { enabled: !!strategyAddress && candidates.length > 0, refetchInterval: 12_000 },
    });

    const entries: AllowedActionEntry[] = useMemo(() => {
        if (!data) return [];
        const out: AllowedActionEntry[] = [];
        for (let i = 0; i < candidates.length; i++) {
            const result = data[i]?.result as
                | readonly [boolean, number]
                | undefined;
            if (!result || !result[0]) continue;
            out.push({
                target: candidates[i].target,
                selector: candidates[i].selector,
                recipientOffset: Number(result[1]),
                label: candidates[i].label,
            });
        }
        return out;
    }, [data, candidates]);

    return { entries, loading: isLoading, refetch };
}
