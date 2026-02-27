import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const supabase = createAdminClient();

  const [
    usersResult,
    eventsResult,
    revenueResult,
    subscriptionsResult,
    tickets30dResult,
    fees30dResult,
    revenueWeeklyResult,
    signupsWeeklyResult,
    tierDistResult,
  ] = await Promise.all([
    // Total users
    supabase.from("profiles").select("*", { count: "exact", head: true }),
    // Total events (excluding soft-deleted)
    supabase
      .from("events")
      .select("*", { count: "exact", head: true })
      .is("deleted_at", null),
    // Total revenue (completed payments)
    supabase
      .from("payments")
      .select("amount_cents")
      .eq("status", "completed"),
    // Active paid subscriptions
    supabase
      .from("subscriptions")
      .select("*", { count: "exact", head: true })
      .eq("status", "active")
      .neq("tier", "base"),
    // Tickets sold (30d)
    supabase
      .from("tickets")
      .select("*", { count: "exact", head: true })
      .gte("sold_at", new Date(Date.now() - 30 * 86400000).toISOString()),
    // Platform fees (30d)
    supabase
      .from("payments")
      .select("platform_fee_cents")
      .eq("status", "completed")
      .gte("created_at", new Date(Date.now() - 30 * 86400000).toISOString()),
    // Revenue weekly (12 weeks) - fetch all completed payments from last 12 weeks
    supabase
      .from("payments")
      .select("amount_cents, created_at")
      .eq("status", "completed")
      .gte("created_at", new Date(Date.now() - 84 * 86400000).toISOString())
      .order("created_at", { ascending: true }),
    // Signups weekly (12 weeks) - use profiles created timestamps
    supabase
      .from("profiles")
      .select("id, referred_at")
      .gte(
        "referred_at",
        new Date(Date.now() - 84 * 86400000).toISOString()
      ),
    // Subscription tier distribution
    supabase.from("subscriptions").select("tier").eq("status", "active"),
  ]);

  // Calculate total revenue
  const totalRevenue =
    revenueResult.data?.reduce((sum, p) => sum + (p.amount_cents || 0), 0) ??
    0;

  // Calculate platform fees 30d
  const platformFees30d =
    fees30dResult.data?.reduce(
      (sum, p) => sum + (p.platform_fee_cents || 0),
      0
    ) ?? 0;

  // Build weekly revenue data
  const revenueWeekly = buildWeeklyBuckets(
    revenueWeeklyResult.data ?? [],
    "amount_cents",
    "revenue"
  );

  // Build weekly signups - we don't have a created_at on profiles directly,
  // so we'll use a simplified approach with the profiles count
  // For signups, we'll query auth.users via the admin client
  const signupsWeekly: { week: string; signups: number }[] = [];
  const now = new Date();
  for (let i = 11; i >= 0; i--) {
    const weekStart = new Date(now.getTime() - (i + 1) * 7 * 86400000);
    const weekEnd = new Date(now.getTime() - i * 7 * 86400000);
    const weekLabel = `W${12 - i}`;
    // Count profiles that have referred_at in this range (approximation)
    // A better approach would be counting auth.users by created_at
    const count =
      signupsWeeklyResult.data?.filter((p) => {
        if (!p.referred_at) return false;
        const d = new Date(p.referred_at);
        return d >= weekStart && d < weekEnd;
      }).length ?? 0;
    signupsWeekly.push({ week: weekLabel, signups: count });
  }

  // Tier distribution
  const tierCounts = { base: 0, pro: 0, enterprise: 0 };
  tierDistResult.data?.forEach((s) => {
    if (s.tier in tierCounts) {
      tierCounts[s.tier as keyof typeof tierCounts]++;
    }
  });
  const tierDistribution = [
    { name: "Base", value: tierCounts.base },
    { name: "Pro", value: tierCounts.pro },
    { name: "Enterprise", value: tierCounts.enterprise },
  ];

  return NextResponse.json({
    totalUsers: usersResult.count ?? 0,
    totalEvents: eventsResult.count ?? 0,
    totalRevenue,
    activeSubscriptions: subscriptionsResult.count ?? 0,
    ticketsSold30d: tickets30dResult.count ?? 0,
    platformFees30d,
    revenueWeekly,
    signupsWeekly,
    tierDistribution,
  });
}

function buildWeeklyBuckets(
  data: { amount_cents?: number; created_at?: string }[],
  valueKey: string,
  outputKey: string
) {
  const now = new Date();
  const buckets: { week: string; [key: string]: number | string }[] = [];

  for (let i = 11; i >= 0; i--) {
    const weekStart = new Date(now.getTime() - (i + 1) * 7 * 86400000);
    const weekEnd = new Date(now.getTime() - i * 7 * 86400000);
    const weekLabel = `W${12 - i}`;

    const total = data
      .filter((item) => {
        const d = new Date(item.created_at ?? "");
        return d >= weekStart && d < weekEnd;
      })
      .reduce(
        (sum, item) =>
          sum + ((item as Record<string, number>)[valueKey] || 0),
        0
      );

    buckets.push({ week: weekLabel, [outputKey]: total });
  }

  return buckets;
}
