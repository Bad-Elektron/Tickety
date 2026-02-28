import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const admin = createAdminClient();

  const { data, error } = await admin
    .from("events")
    .select("*, profiles!events_organizer_id_profiles_fkey(display_name, email)")
    .is("deleted_at", null)
    .order("date", { ascending: false });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  // Get ticket counts per event
  const eventIds = (data ?? []).map((e) => e.id);
  let countMap = new Map<string, number>();

  if (eventIds.length > 0) {
    const { data: ticketCounts } = await admin
      .from("tickets")
      .select("event_id")
      .in("event_id", eventIds);

    ticketCounts?.forEach((t) => {
      countMap.set(t.event_id, (countMap.get(t.event_id) ?? 0) + 1);
    });
  }

  const rows = (data ?? []).map((e) => {
    const organizer = e.profiles as unknown as {
      display_name: string | null;
      email: string | null;
    };
    return {
      ...e,
      organizer_name: organizer?.display_name ?? organizer?.email ?? "Unknown",
      ticket_count: countMap.get(e.id) ?? 0,
      profiles: undefined,
    };
  });

  return NextResponse.json(rows);
}
