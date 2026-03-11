import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id: eventId } = await params;
  const admin = createAdminClient();

  const [eventRes, ticketTypesRes, staffRes] = await Promise.all([
    admin.from("events").select("*").eq("id", eventId).single(),
    admin
      .from("event_ticket_types")
      .select("*")
      .eq("event_id", eventId)
      .order("sort_order"),
    admin
      .from("event_staff")
      .select("*, profiles!event_staff_user_id_profiles_fkey(display_name, email)")
      .eq("event_id", eventId),
  ]);

  const event = eventRes.data;
  if (!event) {
    return NextResponse.json({ error: "Event not found" }, { status: 404 });
  }

  // Fetch organizer
  const { data: organizer } = await admin
    .from("profiles")
    .select("*")
    .eq("id", event.organizer_id)
    .single();

  // Unified event dashboard: tickets + check-ins + engagement in one call
  let analytics: Record<string, unknown> | null = null;
  try {
    const { data: dashData } = await admin.rpc("get_event_dashboard", {
      p_event_id: eventId,
    });
    if (dashData) analytics = dashData;
  } catch {
    // Fallback: try legacy RPC if new one not deployed yet
    try {
      const { data: legacyData } = await admin.rpc("get_event_analytics", {
        p_event_id: eventId,
      });
      if (legacyData) analytics = legacyData;
    } catch {
      // RPC may not exist
    }
  }

  const staff = (staffRes.data ?? []).map((s) => {
    const profile = s.profiles as unknown as {
      display_name: string | null;
      email: string | null;
    };
    return {
      ...s,
      user_name: profile?.display_name ?? undefined,
      user_email: profile?.email ?? s.invited_email ?? undefined,
      profiles: undefined,
    };
  });

  return NextResponse.json({
    event,
    organizer,
    ticketTypes: ticketTypesRes.data ?? [],
    staff,
    analytics,
  });
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id: eventId } = await params;
  const admin = createAdminClient();
  const body = await request.json();

  const { action, reason } = body;

  const updateData: Record<string, unknown> = {};

  switch (action) {
    case "approve":
      updateData.status = "active";
      updateData.status_reason = "Approved by admin";
      break;
    case "suspend":
      updateData.status = "suspended";
      updateData.status_reason = reason || "Suspended by admin";
      break;
    case "reactivate":
      updateData.status = "active";
      updateData.status_reason = "Reactivated by admin";
      break;
    default:
      return NextResponse.json({ error: "Invalid action" }, { status: 400 });
  }

  const { error } = await admin
    .from("events")
    .update(updateData)
    .eq("id", eventId);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ success: true, status: updateData.status });
}
