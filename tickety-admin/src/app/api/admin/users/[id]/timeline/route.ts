import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

interface TimelineEvent {
  type: string;
  title: string;
  detail: string;
  timestamp: string;
}

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id: userId } = await params;
  const admin = createAdminClient();

  // Get user email for ticket lookups
  const { data: profile } = await admin
    .from("profiles")
    .select("email, referred_at")
    .eq("id", userId)
    .single();

  if (!profile) {
    return NextResponse.json({ error: "User not found" }, { status: 404 });
  }

  const timeline: TimelineEvent[] = [];

  // Account creation
  if (profile.referred_at) {
    timeline.push({
      type: "signup",
      title: "Account created",
      detail: profile.email ?? "",
      timestamp: profile.referred_at,
    });
  }

  // Payments
  const { data: payments } = await admin
    .from("payments")
    .select("id, amount_cents, currency, type, status, created_at, events(title)")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(50);

  payments?.forEach((p) => {
    const eventTitle = (p.events as unknown as { title: string })?.title ?? "Unknown event";
    timeline.push({
      type: "payment",
      title: `Payment ${p.status}: $${(p.amount_cents / 100).toFixed(2)}`,
      detail: `${p.type.replace(/_/g, " ")} for ${eventTitle}`,
      timestamp: p.created_at,
    });
  });

  // Tickets purchased
  const { data: tickets } = await admin
    .from("tickets")
    .select("id, ticket_number, status, sold_at, checked_in_at, events(title)")
    .eq("owner_email", profile.email ?? "")
    .order("sold_at", { ascending: false })
    .limit(50);

  tickets?.forEach((t) => {
    const eventTitle = (t.events as unknown as { title: string })?.title ?? "Unknown event";
    timeline.push({
      type: "ticket",
      title: `Ticket purchased: ${t.ticket_number}`,
      detail: eventTitle,
      timestamp: t.sold_at,
    });
    if (t.checked_in_at) {
      timeline.push({
        type: "checkin",
        title: `Checked in: ${t.ticket_number}`,
        detail: eventTitle,
        timestamp: t.checked_in_at,
      });
    }
  });

  // Events organized
  const { data: events } = await admin
    .from("events")
    .select("id, title, date")
    .eq("organizer_id", userId)
    .is("deleted_at", null)
    .order("date", { ascending: false })
    .limit(20);

  events?.forEach((e) => {
    timeline.push({
      type: "event_created",
      title: `Created event: ${e.title}`,
      detail: "",
      timestamp: e.date,
    });
  });

  // Resale listings
  const { data: listings } = await admin
    .from("resale_listings")
    .select("id, price_cents, status, created_at")
    .eq("seller_id", userId)
    .order("created_at", { ascending: false })
    .limit(20);

  listings?.forEach((l) => {
    timeline.push({
      type: "resale",
      title: `Listed ticket for $${(l.price_cents / 100).toFixed(2)}`,
      detail: `Status: ${l.status}`,
      timestamp: l.created_at,
    });
  });

  // Subscription changes
  const { data: sub } = await admin
    .from("subscriptions")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();

  if (sub) {
    timeline.push({
      type: "subscription",
      title: `Subscription: ${sub.tier} (${sub.status})`,
      detail: sub.stripe_subscription_id ?? "",
      timestamp: sub.created_at,
    });
  }

  // Sort by timestamp descending
  timeline.sort(
    (a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
  );

  return NextResponse.json(timeline);
}
