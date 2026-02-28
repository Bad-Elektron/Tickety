import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const admin = createAdminClient();

  const { data: profiles, error } = await admin
    .from("profiles")
    .select("*")
    .order("email", { ascending: true });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  // Fetch subscriptions to join tier
  const { data: subs } = await admin
    .from("subscriptions")
    .select("user_id, tier");

  const subMap = new Map(subs?.map((s) => [s.user_id, s.tier]) ?? []);

  const rows = (profiles ?? []).map((p) => ({
    ...p,
    subscription_tier: subMap.get(p.id) ?? "base",
  }));

  return NextResponse.json(rows);
}
