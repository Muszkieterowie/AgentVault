"use client";

import { AdminPanel } from "@/components";
import { useVaultReads } from "@/hooks";

export default function AdminPage() {
  const { strategyCount, assetDecimals } = useVaultReads();

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-white">Admin Panel</h1>
      <p className="text-sm text-zinc-500">
        Controls are visible to everyone but write actions require the
        appropriate role. Buttons are disabled unless the connected wallet holds
        DEFAULT_ADMIN_ROLE or AUTHORITY_ROLE.
      </p>
      <AdminPanel strategyCount={strategyCount} assetDecimals={assetDecimals} />
    </div>
  );
}
