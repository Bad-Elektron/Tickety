import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { writeAuditLog } from "@/lib/utils/audit";

export async function POST(request: NextRequest) {
  const serverClient = await createServerSupabaseClient();
  const {
    data: { session },
  } = await serverClient.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json();
  const { user_id, new_tier } = body;

  if (!user_id || !new_tier) {
    return NextResponse.json(
      { error: "Missing user_id or new_tier" },
      { status: 400 }
    );
  }

  if (!["base", "pro", "enterprise"].includes(new_tier)) {
    return NextResponse.json({ error: "Invalid tier" }, { status: 400 });
  }

  const admin = createAdminClient();

  // Get current subscription
  const { data: current } = await admin
    .from("subscriptions")
    .select("*")
    .eq("user_id", user_id)
    .maybeSingle();

  const oldTier = current?.tier ?? "base";

  if (current) {
    // Update existing subscription
    const { error } = await admin
      .from("subscriptions")
      .update({ tier: new_tier, updated_at: new Date().toISOString() })
      .eq("user_id", user_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }
  } else {
    // Create new subscription record
    const { error } = await admin.from("subscriptions").insert({
      user_id,
      tier: new_tier,
      status: "active",
    });

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }
  }

  await writeAuditLog({
    admin_user_id: session.user.id,
    action: "subscription_override",
    target_table: "subscriptions",
    target_id: user_id,
    old_values: { tier: oldTier },
    new_values: { tier: new_tier },
    ip_address: request.headers.get("x-forwarded-for") ?? undefined,
  });

  return NextResponse.json({ success: true, old_tier: oldTier, new_tier });
}
