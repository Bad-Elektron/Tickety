"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { formatCents, formatDate, formatDateTime } from "@/lib/utils/format";
import type { Event, EventTicketType, EventStaff, Profile } from "@/types/database";
import { ArrowLeft } from "lucide-react";
import Link from "next/link";

interface EventDetail {
  event: Event;
  organizer: Profile | null;
  ticketTypes: EventTicketType[];
  staff: (EventStaff & { user_email?: string; user_name?: string })[];
  analytics: Record<string, unknown> | null;
}

export default function EventDetailPage() {
  const params = useParams();
  const eventId = params.id as string;
  const [data, setData] = useState<EventDetail | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchEvent() {
      const supabase = createClient();

      const [eventRes, ticketTypesRes, staffRes] = await Promise.all([
        supabase.from("events").select("*").eq("id", eventId).single(),
        supabase
          .from("event_ticket_types")
          .select("*")
          .eq("event_id", eventId)
          .order("sort_order"),
        supabase
          .from("event_staff")
          .select("*, profiles!event_staff_user_id_fkey(display_name, email)")
          .eq("event_id", eventId),
      ]);

      const event = eventRes.data;
      if (!event) {
        setLoading(false);
        return;
      }

      // Fetch organizer
      const { data: organizer } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", event.organizer_id)
        .single();

      // Try to get analytics via RPC
      let analytics: Record<string, unknown> | null = null;
      try {
        const { data: analyticsData } = await supabase.rpc(
          "get_event_analytics",
          { p_event_id: eventId }
        );
        if (analyticsData) analytics = analyticsData;
      } catch {
        // RPC may not exist or user may not have access
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

      setData({
        event,
        organizer,
        ticketTypes: ticketTypesRes.data ?? [],
        staff,
        analytics,
      });
      setLoading(false);
    }
    fetchEvent();
  }, [eventId]);

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-48 bg-zinc-800" />
        <Skeleton className="h-64 w-full bg-zinc-800" />
      </div>
    );
  }

  if (!data) {
    return <p className="text-zinc-400">Event not found.</p>;
  }

  const { event, organizer, ticketTypes, staff, analytics } = data;

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Link href="/dashboard/events">
          <Button variant="ghost" size="sm" className="text-zinc-400">
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back
          </Button>
        </Link>
        <h1 className="text-2xl font-bold text-white">{event.title}</h1>
        {event.deleted_at && (
          <Badge variant="outline" className="border-red-500/30 text-red-400">
            Deleted
          </Badge>
        )}
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        {/* Event Info */}
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm text-zinc-400">
              Event Details
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <InfoRow label="ID" value={event.id} mono />
            <InfoRow label="Date" value={formatDateTime(event.date)} />
            <InfoRow label="Venue" value={event.venue} />
            <InfoRow label="City" value={event.city} />
            <InfoRow label="Country" value={event.country} />
            <InfoRow label="Category" value={event.category} />
            <InfoRow
              label="Base Price"
              value={
                event.priceInCents
                  ? formatCents(event.priceInCents, event.currency)
                  : "Free"
              }
            />
            <InfoRow
              label="Max Tickets"
              value={event.max_tickets?.toString() ?? "Unlimited"}
            />
            <InfoRow
              label="Cash Sales"
              value={event.cash_sales_enabled ? "Enabled" : "Disabled"}
            />
          </CardContent>
        </Card>

        {/* Organizer */}
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm text-zinc-400">Organizer</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {organizer ? (
              <>
                <InfoRow
                  label="Name"
                  value={organizer.display_name}
                />
                <InfoRow label="Email" value={organizer.email} />
                <InfoRow label="Handle" value={organizer.handle} />
                <Link
                  href={`/dashboard/users/${organizer.id}`}
                  className="inline-block text-xs text-indigo-400 hover:underline"
                >
                  View profile →
                </Link>
              </>
            ) : (
              <p className="text-sm text-zinc-500">Unknown organizer</p>
            )}
          </CardContent>
        </Card>

        {/* Analytics */}
        {analytics && (
          <Card className="border-zinc-800 bg-zinc-900">
            <CardHeader>
              <CardTitle className="text-sm text-zinc-400">
                Analytics
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {Object.entries(analytics).map(([key, value]) => (
                <InfoRow
                  key={key}
                  label={key.replace(/_/g, " ")}
                  value={String(value)}
                />
              ))}
            </CardContent>
          </Card>
        )}
      </div>

      {/* Ticket Types */}
      {ticketTypes.length > 0 && (
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm text-zinc-400">
              Ticket Types ({ticketTypes.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {ticketTypes.map((tt) => (
                <div
                  key={tt.id}
                  className="flex items-center justify-between rounded-lg border border-zinc-800 p-3"
                >
                  <div>
                    <p className="font-medium text-white">{tt.name}</p>
                    {tt.description && (
                      <p className="text-xs text-zinc-500">{tt.description}</p>
                    )}
                  </div>
                  <div className="flex items-center gap-4 text-sm">
                    <span className="text-zinc-400">
                      {formatCents(tt.price_cents, tt.currency)}
                    </span>
                    <span className="text-zinc-500">
                      {tt.sold_count}/{tt.max_quantity ?? "∞"} sold
                    </span>
                    <Badge
                      variant="outline"
                      className={
                        tt.is_active
                          ? "border-emerald-500/30 text-emerald-400"
                          : "border-zinc-600 text-zinc-400"
                      }
                    >
                      {tt.is_active ? "active" : "inactive"}
                    </Badge>
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Staff */}
      {staff.length > 0 && (
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm text-zinc-400">
              Staff ({staff.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {staff.map((s) => (
                <div
                  key={s.id}
                  className="flex items-center justify-between rounded-lg p-2"
                >
                  <div>
                    <p className="text-sm text-white">
                      {s.user_name ?? s.user_email}
                    </p>
                    {s.user_name && (
                      <p className="text-xs text-zinc-500">{s.user_email}</p>
                    )}
                  </div>
                  <div className="flex items-center gap-2">
                    <Badge
                      variant="outline"
                      className="border-zinc-600 text-zinc-400"
                    >
                      {s.role}
                    </Badge>
                    {s.accepted_at ? (
                      <span className="text-xs text-emerald-400">Accepted</span>
                    ) : (
                      <span className="text-xs text-amber-400">Pending</span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function InfoRow({
  label,
  value,
  mono,
}: {
  label: string;
  value?: string | null;
  mono?: boolean;
}) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-xs text-zinc-500">{label}</span>
      <span
        className={`text-sm text-zinc-300 ${mono ? "font-mono text-xs" : ""} max-w-[200px] truncate`}
      >
        {value ?? "-"}
      </span>
    </div>
  );
}
