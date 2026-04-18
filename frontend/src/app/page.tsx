"use client";

import {
  StatsStrip,
  StrategyTable,
  AllocationPie,
  ActivityFeed,
  DepositForm,
} from "@/components";
import { useVaultReads, useAssetInfo, useStrategies } from "@/hooks";

export default function Dashboard() {
  const { strategyCount, vaultDecimals, assetAddress } = useVaultReads();
  const { strategies } = useStrategies(strategyCount);

  const strategyAddresses = strategies
    .filter((s) => s.address)
    .map((s) => s.address);

  return (
    <div className="space-y-6 w-full">
      <h1 className="text-4xl font-bold text-center mt-8 mb-4">Vaults</h1>
      <StatsStrip />
      <div className="space-y-6 w-full">
        <StrategyTable strategyCount={strategyCount} decimals={vaultDecimals} />
        <AllocationPie
          strategyCount={strategyCount}
          decimals={vaultDecimals}
          assetAddress={assetAddress}
        />
        <ActivityFeed strategyAddresses={strategyAddresses} />
      </div>
    </div>
  );
}
