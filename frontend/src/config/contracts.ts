// AgentVault — deployed addresses.
// Source of truth: ../../../deployments/base-sepolia.md
// Keep this file in sync whenever the deployment manifest changes.
//
// Deployment shape (latest): TWO target-date event vaults sharing a single
// asset + pool + aToken + dripper. `ADDRESSES` below keeps the old flat
// shape consumed by wagmi.ts pointing at the ETHSilesia vault as the
// default; `VAULTS` is the canonical map the UI should switch over.

export const CHAIN_ID = 84532; // Base Sepolia

/// Shared infrastructure — one instance for both vaults.
export const SHARED = {
  asset:     "0xEAE8C41253197440c84669982b84463cb3410E62", // DemoUSDC (6 dec)
  pool:      "0xA3269593C784Ae3cf068fEfBCe15851C0895e738", // MockAavePool
  aToken:    "0xda1439a46687b8494c42e4d91bF1d69364D65E4A", // aDemoUSDC
  debtToken: "0xc5e66419F10a26D66c4F76a7152EE92753A05029",
  dripper:   "0x44F3d81c3b21C57a820C3D2eFb168F7c4Fd5a517", // YieldDripper, 100 USDC/h
} as const satisfies Record<string, `0x${string}`>;

/// Target-date event vaults. Each has its own Strategy clone + deadline.
export const VAULTS = {
  ETHSilesia: {
    label: "ETHSilesia",
    shareSymbol: "avETHSilesia",
    vault:                  "0xBaCF3F8237BAbFF700B762561A3cCF474f6688A8",
    strategyImplementation: "0xbE2c0aBdc927b37391865335A49227d439839441",
    strategyId0:            "0xDc728730E5bc238f845f96318C49A9F01e99C217",
    deadline:     1779105926, // 2026-05-18 14:05 UTC (30 day window)
    deadlineUtc:  "2026-05-18T14:05:00Z",
  },
  ETHWarsaw: {
    label: "ETHWarsaw",
    shareSymbol: "avETHWarsaw",
    vault:                  "0x26E20946d273d6B3d17094744C9C3d648DE7F425",
    strategyImplementation: "0x56fF4C75bE854990E8a8708c21B75Aac2309cb77",
    strategyId0:            "0xbf69d0cA0AcD1857C63047F3a75d3b0100869BEb",
    deadline:     1781697926, // 2026-06-17 14:05 UTC (60 day window)
    deadlineUtc:  "2026-06-17T14:05:00Z",
  },
} as const;

export type VaultKey = keyof typeof VAULTS;
export const DEFAULT_VAULT: VaultKey = "ETHSilesia";

/// Legacy flat shape kept for wagmi.ts backward compatibility. Points at
/// DEFAULT_VAULT — can still be overridden at runtime via the
/// `NEXT_PUBLIC_VAULT_ADDRESS` env var.
export const ADDRESSES = {
  asset:                  SHARED.asset,
  vault:                  VAULTS[DEFAULT_VAULT].vault,
  strategyImplementation: VAULTS[DEFAULT_VAULT].strategyImplementation,
  strategyId0:            VAULTS[DEFAULT_VAULT].strategyId0,
  pool:                   SHARED.pool,
  aToken:                 SHARED.aToken,
  debtToken:              SHARED.debtToken,
  dripper:                SHARED.dripper,
} as const satisfies Record<string, `0x${string}`>;

export type DeployedAddresses = typeof ADDRESSES;
