import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const admin = createAdminClient();

  const { data, error } = await admin
    .from("tickets")
    .select("*, events(title)")
    .order("sold_at", { ascending: false })
    .limit(500);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const rows = (data ?? []).map((t) => ({
    ...t,
    event_title: (t.events as unknown as { title: string })?.title,
    events: undefined,
  }));

  return NextResponse.json(rows);
}
