import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const supabase = createAdminClient();

  // Single RPC call — all aggregation happens server-side in SQL
  const { data, error } = await supabase.rpc("get_admin_overview_stats");

  if (error) {
    console.error("get_admin_overview_stats failed:", error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  // Map snake_case RPC output to camelCase for frontend compatibility
  return NextResponse.json({
    totalUsers: data.total_users ?? 0,
    totalEvents: data.total_events ?? 0,
    totalRevenue: data.total_revenue ?? 0,
    activeSubscriptions: data.active_subscriptions ?? 0,
    ticketsSold30d: data.tickets_sold_30d ?? 0,
    platformFees30d: data.platform_fees_30d ?? 0,
    revenueWeekly: data.revenue_weekly ?? [],
    signupsWeekly: data.signups_weekly ?? [],
    tierDistribution: data.tier_distribution ?? [],
  });
}
