import { redirect } from "next/navigation";
import { DEFAULT_VAULT } from "@/config/contracts";

export default function VaultRedirect() {
  redirect(`/vault/${DEFAULT_VAULT}`);
}
