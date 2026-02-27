import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { writeAuditLog } from "@/lib/utils/audit";

export async function GET() {
  const admin = createAdminClient();

  const { data, error } = await admin
    .from("feature_flags")
    .select("*")
    .order("key", { ascending: true });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json(data);
}

export async function PATCH(request: NextRequest) {
  const serverClient = await createServerSupabaseClient();
  const {
    data: { session },
  } = await serverClient.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id, enabled } = await request.json();

  if (!id || typeof enabled !== "boolean") {
    return NextResponse.json(
      { error: "Missing id or enabled" },
      { status: 400 }
    );
  }

  const admin = createAdminClient();

  // Get current state for audit
  const { data: current } = await admin
    .from("feature_flags")
    .select("key, enabled")
    .eq("id", id)
    .single();

  const { error } = await admin
    .from("feature_flags")
    .update({
      enabled,
      updated_by: session.user.id,
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await writeAuditLog({
    admin_user_id: session.user.id,
    action: "feature_flag_toggle",
    target_table: "feature_flags",
    target_id: id,
    old_values: { key: current?.key, enabled: current?.enabled },
    new_values: { key: current?.key, enabled },
    ip_address: request.headers.get("x-forwarded-for") ?? undefined,
  });

  return NextResponse.json({ success: true });
}

export async function POST(request: NextRequest) {
  const serverClient = await createServerSupabaseClient();
  const {
    data: { session },
  } = await serverClient.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { key, description, enabled } = await request.json();

  if (!key) {
    return NextResponse.json({ error: "Missing key" }, { status: 400 });
  }

  const admin = createAdminClient();

  const { data, error } = await admin
    .from("feature_flags")
    .insert({
      key,
      description: description ?? null,
      enabled: enabled ?? false,
      updated_by: session.user.id,
    })
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await writeAuditLog({
    admin_user_id: session.user.id,
    action: "feature_flag_create",
    target_table: "feature_flags",
    target_id: data.id,
    new_values: { key, description, enabled },
    ip_address: request.headers.get("x-forwarded-for") ?? undefined,
  });

  return NextResponse.json(data);
}

export async function DELETE(request: NextRequest) {
  const serverClient = await createServerSupabaseClient();
  const {
    data: { session },
  } = await serverClient.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await request.json();

  if (!id) {
    return NextResponse.json({ error: "Missing id" }, { status: 400 });
  }

  const admin = createAdminClient();

  // Get current state for audit
  const { data: current } = await admin
    .from("feature_flags")
    .select("key")
    .eq("id", id)
    .single();

  const { error } = await admin.from("feature_flags").delete().eq("id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await writeAuditLog({
    admin_user_id: session.user.id,
    action: "feature_flag_delete",
    target_table: "feature_flags",
    target_id: id,
    old_values: { key: current?.key },
    ip_address: request.headers.get("x-forwarded-for") ?? undefined,
  });

  return NextResponse.json({ success: true });
}
