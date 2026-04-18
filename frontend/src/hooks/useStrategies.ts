import { useReadContracts } from "wagmi";
import { VaultABI, StrategyABI, ERC20ABI } from "@/abi";
import { VAULT_ADDRESS } from "@/config/wagmi";
import { useMemo } from "react";

export interface StrategyInfo {
    id: number;
    address: `0x${string}`;
    weight: bigint;
    active: boolean;
    totalValue: bigint;
}

export function useStrategies(count: number) {
    const indices = useMemo(
        () => Array.from({ length: count }, (_, i) => i),
        [count]
    );

    const { data, isLoading, refetch } = useReadContracts({
        contracts: indices.flatMap((i) => [
            {
                address: VAULT_ADDRESS,
                abi: VaultABI,
                functionName: "strategies" as const,
                args: [BigInt(i)] as const,
            },
            {
                address: VAULT_ADDRESS,
                abi: VaultABI,
                functionName: "strategyWeights" as const,
                args: [BigInt(i)] as const,
            },
            {
                address: VAULT_ADDRESS,
                abi: VaultABI,
                functionName: "strategyActive" as const,
                args: [BigInt(i)] as const,
            },
        ]),
        query: { enabled: count > 0, refetchInterval: 12_000 },
    });

    const strategyAddresses = useMemo(() => {
        if (!data) return [];
        return indices.map((i) => data[i * 3]?.result as `0x${string}` | undefined);
    }, [data, indices]);

    // Fetch totalValue for each strategy
    const { data: valueData } = useReadContracts({
        contracts: strategyAddresses
            .filter((addr): addr is `0x${string}` => !!addr)
            .map((addr) => ({
                address: addr,
                abi: StrategyABI,
                functionName: "totalValue" as const,
            })),
        query: {
            enabled: strategyAddresses.some(Boolean),
            refetchInterval: 12_000,
        },
    });

    const strategies: StrategyInfo[] = useMemo(() => {
        if (!data) return [];
        return indices.map((i) => {
            const addr = data[i * 3]?.result as `0x${string}`;
            const weight = data[i * 3 + 1]?.result as bigint;
            const active = data[i * 3 + 2]?.result as boolean;

            const valueIdx = strategyAddresses
                .filter(Boolean)
                .findIndex((a) => a === addr);
            const totalValue =
                valueIdx >= 0
                    ? ((valueData?.[valueIdx]?.result as bigint) ?? 0n)
                    : 0n;

            return { id: i, address: addr, weight: weight ?? 0n, active: !!active, totalValue };
        });
    }, [data, valueData, indices, strategyAddresses]);

    return { strategies, isLoading, refetch };
}

export function useIdleBalance(assetAddress?: `0x${string}`) {
    const { data } = useReadContracts({
        contracts: assetAddress
            ? [
                {
                    address: assetAddress,
                    abi: ERC20ABI,
                    functionName: "balanceOf" as const,
                    args: [VAULT_ADDRESS] as const,
                },
            ]
            : [],
        query: { refetchInterval: 12_000 },
    });

    return (data?.[0]?.result as bigint) ?? 0n;
}
