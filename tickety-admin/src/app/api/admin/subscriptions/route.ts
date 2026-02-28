import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const admin = createAdminClient();

  const { data, error } = await admin
    .from("subscriptions")
    .select("*, profiles!subscriptions_user_id_profiles_fkey(email, display_name)")
    .order("created_at", { ascending: false });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const rows = (data ?? []).map((s) => {
    const profile = s.profiles as unknown as { email: string; display_name: string } | null;
    return {
      ...s,
      user_email: profile?.email ?? "Unknown",
      user_display_name: profile?.display_name,
      profiles: undefined,
    };
  });

  return NextResponse.json(rows);
}
