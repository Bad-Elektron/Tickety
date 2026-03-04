import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET(request: NextRequest) {
  const supabase = createAdminClient();

  const city = request.nextUrl.searchParams.get("city") || null;

  const [engagementResult, metaResult] = await Promise.all([
    supabase.rpc("get_platform_engagement_summary", { p_city: city }),
    supabase
      .from("analytics_cache_meta")
      .select("refreshed_at")
      .eq("key", "engagement_last_refresh")
      .maybeSingle(),
  ]);

  if (engagementResult.error) {
    return NextResponse.json(
      { error: engagementResult.error.message },
      { status: 500 }
    );
  }

  return NextResponse.json({
    ...engagementResult.data,
    last_refreshed: metaResult.data?.refreshed_at ?? null,
  });
}
