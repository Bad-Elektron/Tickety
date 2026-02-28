import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id: userId } = await params;
  const admin = createAdminClient();

  const [profileRes, subRes, paymentsRes, eventsRes, , referralsRes] =
    await Promise.all([
      admin.from("profiles").select("*").eq("id", userId).single(),
      admin
        .from("subscriptions")
        .select("*")
        .eq("user_id", userId)
        .maybeSingle(),
      admin
        .from("payments")
        .select("*, events(title)")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(50),
      admin
        .from("events")
        .select("*")
        .eq("organizer_id", userId)
        .is("deleted_at", null)
        .order("date", { ascending: false }),
      admin.from("tickets").select("*").eq("owner_email", "").limit(0),
      admin.from("profiles").select("*").eq("referred_by", userId),
    ]);

  const profile = profileRes.data;
  if (!profile) {
    return NextResponse.json({ error: "User not found" }, { status: 404 });
  }

  const { data: tickets } = await admin
    .from("tickets")
    .select("*")
    .eq("owner_email", profile.email ?? "")
    .order("sold_at", { ascending: false })
    .limit(50);

  let referredBy = null;
  if (profile.referred_by) {
    const { data } = await admin
      .from("profiles")
      .select("*")
      .eq("id", profile.referred_by)
      .single();
    referredBy = data;
  }

  const payments = (paymentsRes.data ?? []).map((p) => ({
    ...p,
    user_email: profile.email ?? undefined,
    event_title: (p.events as unknown as { title: string })?.title,
  }));

  return NextResponse.json({
    profile,
    subscription: subRes.data,
    payments,
    events: eventsRes.data ?? [],
    tickets: tickets ?? [],
    referredBy,
    referrals: referralsRes.data ?? [],
  });
}
