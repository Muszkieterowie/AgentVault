import { useReadContract, useAccount } from "wagmi";
import { VaultABI } from "@/abi";
import { VAULT_ADDRESS } from "@/config/wagmi";
import { keccak256, toHex } from "viem";

const ADMIN_ROLE =
    "0x0000000000000000000000000000000000000000000000000000000000000000" as const;
const AUTHORITY_ROLE = keccak256(toHex("AUTHORITY_ROLE"));

export function useRoles() {
    const { address } = useAccount();

    const { data: isAdmin } = useReadContract({
        address: VAULT_ADDRESS,
        abi: VaultABI,
        functionName: "hasRole",
        args: address ? [ADMIN_ROLE, address] : undefined,
        query: { enabled: !!address },
    });

    const { data: isAuthority } = useReadContract({
        address: VAULT_ADDRESS,
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
