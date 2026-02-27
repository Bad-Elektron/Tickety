import { createAdminClient } from "@/lib/supabase/admin";

interface AuditEntry {
  admin_user_id: string;
  action: string;
  target_table?: string;
  target_id?: string;
  old_values?: Record<string, unknown>;
  new_values?: Record<string, unknown>;
  details?: Record<string, unknown>;
  ip_address?: string;
}

export async function writeAuditLog(entry: AuditEntry) {
  const supabase = createAdminClient();
  const { error } = await supabase.from("admin_audit_log").insert(entry);
  if (error) {
    console.error("Failed to write audit log:", error);
  }
}
