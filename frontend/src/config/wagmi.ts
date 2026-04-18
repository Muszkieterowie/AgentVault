import { http } from "wagmi";
import { baseSepolia } from "wagmi/chains";
import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { ADDRESSES, CHAIN_ID } from "./contracts";

export const config = getDefaultConfig({
    appName: "AgentVault",
    projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "placeholder",
    chains: [baseSepolia],
    transports: {
        [baseSepolia.id]: http(`/api/rpc/${CHAIN_ID}`),
    },
    ssr: true,
});

// Deployed address aliases, re-exported so existing hooks/components keep
// importing from @/config/wagmi. Override at runtime via NEXT_PUBLIC_VAULT_ADDRESS
// if you redeploy to a different address without regenerating contracts.ts.
export const VAULT_ADDRESS = (process.env.NEXT_PUBLIC_VAULT_ADDRESS ||
    ADDRESSES.vault) as `0x${string}`;
export const ASSET_ADDRESS = ADDRESSES.asset as `0x${string}`;
export const POOL_ADDRESS = ADDRESSES.pool as `0x${string}`;
export const ATOKEN_ADDRESS = ADDRESSES.aToken as `0x${string}`;
export const DRIPPER_ADDRESS = ADDRESSES.dripper as `0x${string}`;
