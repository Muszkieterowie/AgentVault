// AgentVault — deployed addresses.
// Source of truth: ../../deployments/base-sepolia.md
// Keep this file in sync whenever the deployment manifest changes.

export const CHAIN_ID = 84532; // Base Sepolia

export const ADDRESSES = {
  asset:                  "0x6a3601942C2F17370E87a2834317BFC24E0e9E70", // DemoUSDC (6 dec)
  vault:                  "0x21c5b7a26a554748c1c557c50e78f5f178e5ba39", // ERC-4626
  strategyImplementation: "0x11D310d30E32275b9F82e671a3b542a09B26c058",
  strategyId0:            "0xbdf36639462Cf6174Dc895514DEbA2116850992E",
  pool:                   "0x4CE0Ee1Ed18C2f0D9E5D45ed037380e482ba3C1A", // MockAavePool
  aToken:                 "0xEb6566A83ec76Ed023370bAefBE5c0bc402243e5", // aDemoUSDC
  debtToken:              "0x8f6193f8737913216A6144B18a6E9B4AbDDf8d92",
  dripper:                "0xC74119243E3cb9474171740d7707F470F989c194", // YieldDripper
} as const satisfies Record<string, `0x${string}`>;

export type DeployedAddresses = typeof ADDRESSES;
