"use client";

import {
  StatsStrip,
  StrategyTable,
  AllocationPie,
  ActivityFeed,
  DepositForm,
  WithdrawForm,
} from "@/components";
import { useVaultReads, useAssetInfo, useStrategies } from "@/hooks";

export default function Dashboard() {
  const {
    strategyCount,
    vaultDecimals,
    assetAddress,
    userShares,
    sharePrice,
    refetch,
  } = useVaultReads();
  const { assetSymbol, assetDecimals } = useAssetInfo(assetAddress);
  const { strategies } = useStrategies(strategyCount);

  const strategyAddresses = strategies
    .filter((s) => s.address)
    .map((s) => s.address);

  return (
    <div className="space-y-6">
      <StatsStrip />

      <div className="grid gap-6 lg:grid-cols-3">
        {/* Main column */}
        <div className="space-y-6 lg:col-span-2">
          <StrategyTable
            strategyCount={strategyCount}
            decimals={vaultDecimals}
          />
          <AllocationPie
            strategyCount={strategyCount}
            decimals={vaultDecimals}
            assetAddress={assetAddress}
          />
          <ActivityFeed strategyAddresses={strategyAddresses} />
        </div>

        {/* Side column */}
        <div className="space-y-4">
          <DepositForm
            assetAddress={assetAddress}
            assetDecimals={assetDecimals}
            assetSymbol={assetSymbol}
            onSuccess={refetch}
          />
          <WithdrawForm
            vaultDecimals={vaultDecimals}
            assetSymbol={assetSymbol}
            userShares={userShares}
            sharePrice={sharePrice}
            onSuccess={refetch}
          />
        </div>
      </div>
    </div>
  );
}
