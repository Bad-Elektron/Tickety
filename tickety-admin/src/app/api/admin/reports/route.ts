import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const admin = createAdminClient();

  const { data, error } = await admin
    .from("event_reports")
    .select(
      "*, events!event_reports_event_id_fkey(title), reporter:profiles!event_reports_reporter_id_profiles_fkey(email, display_name)"
    )
    .order("created_at", { ascending: false });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const rows = (data ?? []).map((r) => {
    const event = r.events as unknown as { title: string | null };
    const reporter = r.reporter as unknown as {
      email: string | null;
      display_name: string | null;
    };
    return {
      ...r,
      event_title: event?.title ?? "Unknown",
      reporter_email: reporter?.display_name ?? reporter?.email ?? "Unknown",
      events: undefined,
      reporter: undefined,
    };
  });

  return NextResponse.json(rows);
}

export async function PATCH(request: NextRequest) {
  const admin = createAdminClient();
  const body = await request.json();

  const { id, status } = body;
  if (!id || !status) {
    return NextResponse.json(
      { error: "Missing id or status" },
      { status: 400 }
    );
  }

  const { error } = await admin
    .from("event_reports")
    .update({
      status,
      reviewed_at: new Date().toISOString(),
    })
    .eq("id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}
