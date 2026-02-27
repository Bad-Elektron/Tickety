import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const admin = createAdminClient();

  const { data, error } = await admin
    .from("admin_audit_log")
    .select("*, profiles!admin_audit_log_admin_user_id_fkey(email)")
    .order("created_at", { ascending: false })
    .limit(200);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const rows = (data ?? []).map((row) => ({
    ...row,
    admin_email: (row.profiles as unknown as { email: string })?.email,
    profiles: undefined,
  }));

  return NextResponse.json(rows);
}
