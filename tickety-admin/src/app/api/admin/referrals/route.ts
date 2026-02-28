import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const admin = createAdminClient();

  // Fetch profiles that were referred (referred_by is set)
  const { data, error } = await admin
    .from("profiles")
    .select("id, email, display_name, handle, referred_by, referred_at, created_at")
    .not("referred_by", "is", null)
    .order("referred_at", { ascending: false });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  // Collect referrer IDs and fetch their profiles in one query
  const referrerIds = [...new Set((data ?? []).map((p) => p.referred_by))];
  const referrerMap = new Map<string, { email: string; display_name: string | null }>();

  if (referrerIds.length > 0) {
    const { data: referrers } = await admin
      .from("profiles")
      .select("id, email, display_name")
      .in("id", referrerIds);

    referrers?.forEach((r) => {
      referrerMap.set(r.id, { email: r.email, display_name: r.display_name });
    });
  }

  const rows = (data ?? []).map((p) => {
    const referrer = referrerMap.get(p.referred_by);
    return {
      id: p.id,
      referred_email: p.email,
      referred_name: p.display_name ?? p.handle,
      referrer_email: referrer?.email ?? "Unknown",
      referrer_name: referrer?.display_name,
      referred_at: p.referred_at,
      signed_up_at: p.created_at,
    };
  });

  return NextResponse.json(rows);
}
