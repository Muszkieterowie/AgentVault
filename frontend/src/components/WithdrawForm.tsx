"use client";

import { useState } from "react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, formatUnits } from "viem";
import { VaultABI } from "@/abi";
import { VAULT_ADDRESS } from "@/config/wagmi";

interface Props {
  vaultDecimals: number;
  assetSymbol?: string;
  userShares?: bigint;
  sharePrice: number;
  onSuccess?: () => void;
}

export function WithdrawForm({
  vaultDecimals,
  assetSymbol,
  userShares,
  sharePrice,
  onSuccess,
}: Props) {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");

  const { writeContract, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const parsedAmount = amount ? parseUnits(amount, vaultDecimals) : 0n;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!address || parsedAmount === 0n) return;

    writeContract(
      {
        address: VAULT_ADDRESS,
        abi: VaultABI,
        functionName: "withdraw",
        args: [parsedAmount, address, address],
      },
      {
        onSuccess: () => {
          setAmount("");
          reset();
          onSuccess?.();
        },
      }
    );
  };

  const maxWithdrawable =
    userShares !== undefined
      ? Number(formatUnits(userShares, vaultDecimals)) * sharePrice
      : 0;

  return (
    <form
      onSubmit={handleSubmit}
      className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-4"
    >
      <h3 className="mb-3 text-sm font-medium text-zinc-400 uppercase tracking-wide">
        Withdraw
      </h3>
      <div className="mb-3">
        <label className="mb-1 block text-xs text-zinc-500">
          Amount ({assetSymbol ?? "tokens"})
        </label>
        <input
          type="text"
          inputMode="decimal"
          pattern="[0-9]*\.?[0-9]*"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="0.0"
          className="w-full rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-2 text-white placeholder-zinc-600 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
        />
        {userShares !== undefined && userShares > 0n && (
          <p className="mt-1 text-xs text-zinc-500">
            Available: ~
            {maxWithdrawable.toLocaleString(undefined, {
              maximumFractionDigits: 4,
            })}{" "}
            {assetSymbol}
            <button
              type="button"
              className="ml-2 text-blue-400 hover:text-blue-300"
              onClick={() => setAmount(maxWithdrawable.toFixed(vaultDecimals))}
            >
              Max
            </button>
          </p>
        )}
      </div>
      <button
        type="submit"
        disabled={!address || parsedAmount === 0n || isPending || isConfirming}
        className="w-full rounded-lg bg-zinc-700 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-zinc-600 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {isPending || isConfirming ? "Confirming…" : "Withdraw"}
      </button>
    </form>
  );
}
