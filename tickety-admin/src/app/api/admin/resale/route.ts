import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  const admin = createAdminClient();

  const { data, error } = await admin
    .from("resale_listings")
    .select(
      "*, profiles!resale_listings_seller_id_profiles_fkey(email), tickets!resale_listings_ticket_id_fkey(ticket_number, events(title))"
    )
    .order("created_at", { ascending: false })
    .limit(500);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const rows = (data ?? []).map((r) => {
    const ticket = r.tickets as unknown as {
      ticket_number: string;
      events: { title: string };
    };
    return {
      ...r,
      seller_email: (r.profiles as unknown as { email: string })?.email,
      ticket_number: ticket?.ticket_number,
      event_title: ticket?.events?.title,
      profiles: undefined,
      tickets: undefined,
    };
  });

  return NextResponse.json(rows);
}

export async function PATCH(request: NextRequest) {
  const admin = createAdminClient();
  const { id, status } = await request.json();

  if (!id || !status) {
    return NextResponse.json({ error: "Missing id or status" }, { status: 400 });
  }

  const { error } = await admin
    .from("resale_listings")
    .update({ status })
    .eq("id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ success: true });
}
