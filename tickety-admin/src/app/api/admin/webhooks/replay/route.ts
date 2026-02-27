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

  const { webhook_event_id } = await request.json();
  if (!webhook_event_id) {
    return NextResponse.json({ error: "Missing webhook_event_id" }, { status: 400 });
  }

  const admin = createAdminClient();

  // Get the webhook event
  const { data: event, error } = await admin
    .from("webhook_events")
    .select("*")
    .eq("id", webhook_event_id)
    .single();

  if (error || !event) {
    return NextResponse.json({ error: "Event not found" }, { status: 404 });
  }

  // Determine which edge function to call based on event type
  const eventType = event.event_type as string;
  let functionName = "stripe-webhook";
  if (eventType.startsWith("account.")) {
    functionName = "connect-webhook";
  }

  // Mark as processing
  await admin
    .from("webhook_events")
    .update({ status: "processing" })
    .eq("id", webhook_event_id);

  // Re-invoke the edge function with the original payload
  const startTime = Date.now();
  const { error: invokeError } = await admin.functions.invoke(functionName, {
    body: event.payload,
  });

  const processingTime = Date.now() - startTime;

  if (invokeError) {
    await admin
      .from("webhook_events")
      .update({
        status: "failed",
        error_message: invokeError.message,
        processing_time_ms: processingTime,
        processed_at: new Date().toISOString(),
      })
      .eq("id", webhook_event_id);

    return NextResponse.json(
      { error: invokeError.message, replayed: true },
      { status: 500 }
    );
  }

  await admin
    .from("webhook_events")
    .update({
      status: "succeeded",
      error_message: null,
      processing_time_ms: processingTime,
      processed_at: new Date().toISOString(),
    })
    .eq("id", webhook_event_id);

  await writeAuditLog({
    admin_user_id: session.user.id,
    action: "webhook_replay",
    target_table: "webhook_events",
    target_id: webhook_event_id,
    details: {
      stripe_event_id: event.stripe_event_id,
      event_type: event.event_type,
      function_name: functionName,
    },
    ip_address: request.headers.get("x-forwarded-for") ?? undefined,
  });

  return NextResponse.json({ success: true, processing_time_ms: processingTime });
}
