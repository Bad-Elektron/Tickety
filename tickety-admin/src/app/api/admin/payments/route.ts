import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const admin = createAdminClient();

  const { data, error } = await admin
    .from("payments")
    .select("*, profiles!payments_user_id_profiles_fkey(email), events(title)")
    .order("created_at", { ascending: false })
    .limit(500);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const rows = (data ?? []).map((p) => ({
    ...p,
    user_email: (p.profiles as unknown as { email: string })?.email,
    event_title: (p.events as unknown as { title: string })?.title,
    profiles: undefined,
    events: undefined,
  }));

  return NextResponse.json(rows);
}
