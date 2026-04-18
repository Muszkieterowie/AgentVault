import { useReadContract, useReadContracts } from "wagmi";
import { VaultABI, ERC20ABI } from "@/abi";
import { VAULT_ADDRESS } from "@/config/wagmi";
import { formatUnits } from "viem";
import { useAccount } from "wagmi";

export function useVaultReads(vaultAddr?: `0x${string}`) {
    const vault = vaultAddr ?? VAULT_ADDRESS;
    const { address } = useAccount();

    const { data, isLoading, refetch } = useReadContracts({
        contracts: [
            { address: vault, abi: VaultABI, functionName: "totalAssets" },
            { address: vault, abi: VaultABI, functionName: "totalSupply" },
            { address: vault, abi: VaultABI, functionName: "asset" },
            { address: vault, abi: VaultABI, functionName: "decimals" },
            { address: vault, abi: VaultABI, functionName: "name" },
            { address: vault, abi: VaultABI, functionName: "symbol" },
            { address: vault, abi: VaultABI, functionName: "strategyCount" },
        ] as const,
        query: { refetchInterval: 12_000 },
    });

    const { data: userSharesData } = useReadContract({
        address: vault,
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

    // The vault uses ERC-4626 decimal offset: share decimals = asset decimals
    // + offset (6). `totalAssets` is denominated in ASSET units, `totalSupply`
    // and `userShares` in SHARE units. Mixing them with a single `decimals`
    // produces silently wrong TVL / share-price / position numbers (asset-side
    // gets divided by the share scale, flattening everything to ~0).
    const { data: assetDecimalsData } = useReadContract({
        address: assetAddress as `0x${string}` | undefined,
        abi: ERC20ABI,
        functionName: "decimals",
        query: { enabled: !!assetAddress },
    });

    const shareDecimals = vaultDecimals ?? 18;
    const assetDecimals = (assetDecimalsData as number | undefined) ?? shareDecimals;

    const totalAssetsHuman = Number(formatUnits(totalAssets ?? 0n, assetDecimals));
    const totalSupplyHuman = Number(formatUnits(totalSupply ?? 0n, shareDecimals));
    const sharePrice = totalSupplyHuman > 0 ? totalAssetsHuman / totalSupplyHuman : 1;

    const userSharesHuman = userShares !== undefined
        ? Number(formatUnits(userShares, shareDecimals))
        : 0;
    const userAssetsValue = userSharesHuman * sharePrice;

    return {
        totalAssets,
        totalSupply,
        assetAddress,
        vaultDecimals: shareDecimals,
        assetDecimals,
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
