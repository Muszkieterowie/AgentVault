"use client";

import { useState } from "react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, maxUint256 } from "viem";
import { VaultABI, ERC20ABI } from "@/abi";
import { VAULT_ADDRESS } from "@/config/wagmi";
import { useAllowance, useUserAssetBalance } from "@/hooks";

interface Props {
  assetAddress?: `0x${string}`;
  assetDecimals: number;
  assetSymbol?: string;
  onSuccess?: () => void;
}

export function DepositForm({
  assetAddress,
  assetDecimals,
  assetSymbol,
  onSuccess,
}: Props) {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const { allowance, refetchAllowance } = useAllowance(
    assetAddress,
    address,
    VAULT_ADDRESS
  );
  const balance = useUserAssetBalance(assetAddress, address);

  const { writeContract, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const parsedAmount = amount ? parseUnits(amount, assetDecimals) : 0n;
  const needsApproval =
    parsedAmount > 0n && (allowance === undefined || allowance < parsedAmount);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!address || parsedAmount === 0n) return;

    if (needsApproval && assetAddress) {
      writeContract(
        {
          address: assetAddress,
          abi: ERC20ABI,
          functionName: "approve",
          args: [VAULT_ADDRESS, maxUint256],
        },
        {
          onSuccess: () => {
            refetchAllowance();
            reset();
          },
        }
      );
    } else {
      writeContract(
        {
          address: VAULT_ADDRESS,
          abi: VaultABI,
          functionName: "deposit",
          args: [parsedAmount, address],
        },
        {
          onSuccess: () => {
            setAmount("");
            reset();
            onSuccess?.();
          },
        }
      );
    }
  };

  return (
    <form
      onSubmit={handleSubmit}
      className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-4"
    >
      <h3 className="mb-3 text-sm font-medium text-zinc-400 uppercase tracking-wide">
        Deposit
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
        {balance !== undefined && (
          <p className="mt-1 text-xs text-zinc-500">
            Wallet:{" "}
            {Number(
              parseFloat(
                (Number(balance) / 10 ** assetDecimals).toString()
              ).toFixed(4)
            )}{" "}
            {assetSymbol}
            <button
              type="button"
              className="ml-2 text-blue-400 hover:text-blue-300"
              onClick={() =>
                setAmount((Number(balance) / 10 ** assetDecimals).toString())
              }
            >
              Max
            </button>
          </p>
        )}
      </div>
      <button
        type="submit"
        disabled={!address || parsedAmount === 0n || isPending || isConfirming}
        className="w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {isPending || isConfirming
          ? "Confirming…"
          : needsApproval
          ? "Approve"
          : "Deposit"}
      </button>
    </form>
  );
}
