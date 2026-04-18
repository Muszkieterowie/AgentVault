"use client";

import { VaultsTable } from "@/components";

export default function Dashboard() {
  return (
    <div className="space-y-6 w-full">
      <h1 className="text-4xl font-bold text-center mt-15 mb-11">
        Kolektyw3 Vaults
      </h1>

      <div className="space-y-6 w-full">
        <VaultsTable />
      </div>
    </div>
  );
}
