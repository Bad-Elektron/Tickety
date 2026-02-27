import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET(request: NextRequest) {
  const limit = Number(request.nextUrl.searchParams.get("limit") ?? "100");
  const status = request.nextUrl.searchParams.get("status");

  const supabase = createAdminClient();

  let query = supabase
    .from("webhook_events")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(limit);

  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const { data, error } = await query;

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  // Also get summary stats
  const [totalRes, failedRes, last24hRes] = await Promise.all([
    supabase
      .from("webhook_events")
      .select("*", { count: "exact", head: true }),
    supabase
      .from("webhook_events")
      .select("*", { count: "exact", head: true })
      .eq("status", "failed"),
    supabase
      .from("webhook_events")
      .select("*", { count: "exact", head: true })
      .gte("created_at", new Date(Date.now() - 86400000).toISOString()),
  ]);

  return NextResponse.json({
    events: data ?? [],
    stats: {
      total: totalRes.count ?? 0,
      failed: failedRes.count ?? 0,
      last24h: last24hRes.count ?? 0,
    },
  });
}
