import { createConfig, http } from "wagmi";
import { baseSepolia } from "wagmi/chains";
import { connectorsForWallets } from "@rainbow-me/rainbowkit";
import { injectedWallet } from "@rainbow-me/rainbowkit/wallets";
import { ADDRESSES, CHAIN_ID } from "./contracts";

// Injected-only (MetaMask, Rabby, etc.) — no WalletConnect relay needed, so
// no project id required. The `projectId` field below is a placeholder that
// RainbowKit's wallet registry wants, but it is never used because we don't
// include any WC-backed wallet in the list.
const connectors = connectorsForWallets(
    [{ groupName: "Recommended", wallets: [injectedWallet] }],
    { appName: "AISandbox", projectId: "unused" }
);

export const config = createConfig({
    connectors,
    chains: [baseSepolia],
    transports: {
        [baseSepolia.id]: http(`/api/rpc/${CHAIN_ID}`),
    },
    ssr: true,
});

export const VAULT_ADDRESS = (process.env.NEXT_PUBLIC_VAULT_ADDRESS ||
    ADDRESSES.vault) as `0x${string}`;
export const ASSET_ADDRESS = ADDRESSES.asset as `0x${string}`;
export const POOL_ADDRESS = ADDRESSES.pool as `0x${string}`;
export const ATOKEN_ADDRESS = ADDRESSES.aToken as `0x${string}`;
export const DRIPPER_ADDRESS = ADDRESSES.dripper as `0x${string}`;
