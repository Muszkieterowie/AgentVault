import { useReadContract, useReadContracts } from "wagmi";
import { VaultABI, ERC20ABI } from "@/abi";
import { VAULT_ADDRESS } from "@/config/wagmi";
import { formatUnits } from "viem";
import { useAccount } from "wagmi";

export function useVaultReads() {
    const { address } = useAccount();

    const { data, isLoading, refetch } = useReadContracts({
        contracts: [
            { address: VAULT_ADDRESS, abi: VaultABI, functionName: "totalAssets" },
            { address: VAULT_ADDRESS, abi: VaultABI, functionName: "totalSupply" },
            { address: VAULT_ADDRESS, abi: VaultABI, functionName: "asset" },
            { address: VAULT_ADDRESS, abi: VaultABI, functionName: "decimals" },
            { address: VAULT_ADDRESS, abi: VaultABI, functionName: "name" },
            { address: VAULT_ADDRESS, abi: VaultABI, functionName: "symbol" },
            { address: VAULT_ADDRESS, abi: VaultABI, functionName: "strategyCount" },
        ] as const,
        query: { refetchInterval: 12_000 },
    });

    const { data: userSharesData } = useReadContract({
        address: VAULT_ADDRESS,
        abi: VaultABI,
        functionName: "balanceOf",
        args: address ? [address] : undefined,
        query: { enabled: !!address, refetchInterval: 12_000 },
    });

    const totalAssets = data?.[0]?.result;
    const totalSupply = data?.[1]?.result;
    const assetAddress = data?.[2]?.result;
    const vaultDecimals = data?.[3]?.result;
    const vaultName = data?.[4]?.result;
    const vaultSymbol = data?.[5]?.result;
    const strategyCount = data?.[6]?.result;
    const userShares = userSharesData;

    const decimals = vaultDecimals ?? 18;
    const sharePrice =
        totalSupply && totalSupply > 0n
            ? Number(formatUnits(totalAssets ?? 0n, decimals)) /
            Number(formatUnits(totalSupply, decimals))
            : 1;

    const userAssetsValue =
        userShares !== undefined
            ? Number(formatUnits(userShares, decimals)) * sharePrice
            : 0;

    return {
        totalAssets,
        totalSupply,
        assetAddress,
        vaultDecimals: decimals,
        vaultName,
        vaultSymbol,
        strategyCount: strategyCount ? Number(strategyCount) : 0,
        userShares,
        sharePrice,
        userAssetsValue,
        isLoading,
        refetch,
    };
}

export function useAssetInfo(assetAddress?: `0x${string}`) {
    const { data } = useReadContracts({
        contracts: assetAddress
            ? [
                { address: assetAddress, abi: ERC20ABI, functionName: "symbol" },
                { address: assetAddress, abi: ERC20ABI, functionName: "decimals" },
                { address: assetAddress, abi: ERC20ABI, functionName: "name" },
            ]
            : [],
    });

    return {
        assetSymbol: data?.[0]?.result as string | undefined,
        assetDecimals: (data?.[1]?.result as number | undefined) ?? 18,
        assetName: data?.[2]?.result as string | undefined,
    };
}

export function useAllowance(
    assetAddress?: `0x${string}`,
    owner?: `0x${string}`,
    spender?: `0x${string}`
) {
    const { data, refetch } = useReadContract({
        address: assetAddress,
        abi: ERC20ABI,
        functionName: "allowance",
        args: owner && spender ? [owner, spender] : undefined,
        query: { enabled: !!assetAddress && !!owner && !!spender },
    });

    return { allowance: data as bigint | undefined, refetchAllowance: refetch };
}

export function useUserAssetBalance(
    assetAddress?: `0x${string}`,
    user?: `0x${string}`
) {
    const { data } = useReadContract({
        address: assetAddress,
        abi: ERC20ABI,
        functionName: "balanceOf",
        args: user ? [user] : undefined,
        query: { enabled: !!assetAddress && !!user, refetchInterval: 12_000 },
    });

    return data as bigint | undefined;
}
