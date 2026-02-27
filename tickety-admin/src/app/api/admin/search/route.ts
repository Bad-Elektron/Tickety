import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET(request: NextRequest) {
  const q = request.nextUrl.searchParams.get("q")?.trim();
  if (!q || q.length < 2) {
    return NextResponse.json({ users: [], events: [], tickets: [], payments: [] });
  }

  const supabase = createAdminClient();
  const pattern = `%${q}%`;

  const [usersRes, eventsRes, ticketsRes, paymentsRes] = await Promise.all([
    supabase
      .from("profiles")
      .select("id, display_name, email, handle")
      .or(`email.ilike.${pattern},display_name.ilike.${pattern},handle.ilike.${pattern}`)
      .limit(5),
    supabase
      .from("events")
      .select("id, title, city, date")
      .ilike("title", pattern)
      .is("deleted_at", null)
      .limit(5),
    supabase
      .from("tickets")
      .select("id, ticket_number, owner_email, event_id")
      .or(`ticket_number.ilike.${pattern},owner_email.ilike.${pattern}`)
      .limit(5),
    supabase
      .from("payments")
      .select("id, stripe_payment_intent_id, amount_cents, status")
      .ilike("stripe_payment_intent_id", pattern)
      .limit(5),
  ]);

  return NextResponse.json({
    users: usersRes.data ?? [],
    events: eventsRes.data ?? [],
    tickets: ticketsRes.data ?? [],
    payments: paymentsRes.data ?? [],
  });
}
