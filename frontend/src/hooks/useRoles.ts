import { useReadContract, useAccount } from "wagmi";
import { VaultABI } from "@/abi";
import { VAULT_ADDRESS } from "@/config/wagmi";
import { keccak256, toHex } from "viem";

const ADMIN_ROLE =
    "0x0000000000000000000000000000000000000000000000000000000000000000" as const;
const AUTHORITY_ROLE = keccak256(toHex("AUTHORITY_ROLE"));

/**
 * Each vault has its own AccessControl, so the role check has to be
 * scoped to the vault the admin page is currently viewing. The default
 * here stays at the configured VAULT_ADDRESS for callers (e.g. the
 * global Header) that are not tied to a specific vault page.
 */
export function useRoles(vaultAddress?: `0x${string}`) {
    const { address } = useAccount();
    const vault = vaultAddress ?? VAULT_ADDRESS;

    const { data: isAdmin } = useReadContract({
        address: vault,
        abi: VaultABI,
        functionName: "hasRole",
        args: address ? [ADMIN_ROLE, address] : undefined,
        query: { enabled: !!address },
    });

    const { data: isAuthority } = useReadContract({
        address: vault,
        abi: VaultABI,
        functionName: "hasRole",
        args: address ? [AUTHORITY_ROLE, address] : undefined,
        query: { enabled: !!address },
    });

    return {
        isAdmin: !!isAdmin,
        isAuthority: !!isAuthority,
        ADMIN_ROLE,
        AUTHORITY_ROLE,
    };
}
