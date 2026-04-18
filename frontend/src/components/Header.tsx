"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useRoles } from "@/hooks";
import Link from "next/link";
import { usePathname } from "next/navigation";

export function Header() {
  const { isAdmin, isAuthority } = useRoles();
  const pathname = usePathname();

  return (
    <header className="border-b border-zinc-800 bg-zinc-950 px-6 py-4">
      <div className="mx-auto flex max-w-7xl items-center justify-between">
        <div className="flex items-center gap-6">
          <Link href="/" className="text-xl font-bold text-white">
            AgentVault
          </Link>
          <nav className="flex gap-4">
            <Link
              href="/"
              className={`text-sm ${
                pathname === "/"
                  ? "text-blue-400 font-medium"
                  : "text-zinc-400 hover:text-white"
              }`}
            >
              Dashboard
            </Link>
            <Link
              href="/vault"
              className={`text-sm ${
                pathname === "/vault"
                  ? "text-blue-400 font-medium"
                  : "text-zinc-400 hover:text-white"
              }`}
            >
              Vault
            </Link>
            <Link
              href="/admin"
              className={`text-sm ${
                pathname === "/admin"
                  ? "text-blue-400 font-medium"
                  : "text-zinc-400 hover:text-white"
              }`}
            >
              Admin
            </Link>
          </nav>
        </div>
        <div className="flex items-center gap-3">
          {isAdmin && (
            <span className="rounded-full bg-purple-900/50 px-2.5 py-0.5 text-xs font-medium text-purple-300 ring-1 ring-purple-700">
              admin
            </span>
          )}
          {isAuthority && (
            <span className="rounded-full bg-amber-900/50 px-2.5 py-0.5 text-xs font-medium text-amber-300 ring-1 ring-amber-700">
              authority
            </span>
          )}
          <ConnectButton />
        </div>
      </div>
    </header>
  );
}
