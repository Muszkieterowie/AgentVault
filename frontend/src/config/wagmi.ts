import { http, createConfig } from "wagmi";
import { baseSepolia } from "wagmi/chains";
import { getDefaultConfig } from "@rainbow-me/rainbowkit";

const rpcUrl =
    process.env.NEXT_PUBLIC_LOCAL_RPC_URL || "http://127.0.0.1:8545";

export const config = getDefaultConfig({
    appName: "AgentVault",
    projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "placeholder",
    chains: [baseSepolia],
    transports: {
        [baseSepolia.id]: http("/api/rpc/84532"),
    },
    ssr: true,
});

export const VAULT_ADDRESS = (process.env.NEXT_PUBLIC_VAULT_ADDRESS ||
    "0x") as `0x${string}`;
