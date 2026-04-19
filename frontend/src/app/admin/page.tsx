import { redirect } from "next/navigation";
import { DEFAULT_VAULT } from "@/config/contracts";

// /admin without a vault key redirects to the default vault's admin. This
// matches /vault/ → /vault/<default> and keeps any old links working.
export default function AdminRedirect() {
  redirect(`/admin/${DEFAULT_VAULT}`);
}
