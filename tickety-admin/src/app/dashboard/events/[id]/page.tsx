"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Input } from "@/components/ui/input";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { formatCents, formatDate, formatDateTime } from "@/lib/utils/format";
import type { Event, EventTicketType, EventStaff, Profile } from "@/types/database";
import { ArrowLeft, ShieldCheck, Ban, CheckCircle } from "lucide-react";
import Link from "next/link";

interface EventDetail {
  event: Event;
  organizer: Profile | null;
  ticketTypes: EventTicketType[];
  staff: (EventStaff & { user_email?: string; user_name?: string })[];
  analytics: Record<string, unknown> | null;
}

const statusBadgeColors: Record<string, string> = {
  active: "border-emerald-500/30 text-emerald-400",
  pending_review: "border-amber-500/30 text-amber-400",
  suspended: "border-red-500/30 text-red-400",
};

export default function EventDetailPage() {
  const params = useParams();
  const eventId = params.id as string;
  const [data, setData] = useState<EventDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [suspendOpen, setSuspendOpen] = useState(false);
  const [suspendReason, setSuspendReason] = useState("");

  useEffect(() => {
    async function fetchEvent() {
      try {
        const res = await fetch(`/api/admin/events/${eventId}`);
        if (!res.ok) {
          setLoading(false);
          return;
        }
        const json = await res.json();
        setData(json);
      } catch {
        // Fetch failed
      }
      setLoading(false);
    }
    fetchEvent();
  }, [eventId]);

  const handleEventAction = async (action: string, reason?: string) => {
    setActionLoading(action);
    try {
      const res = await fetch(`/api/admin/events/${eventId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, reason }),
      });
      if (res.ok) {
        const result = await res.json();
        setData((prev) =>
          prev
            ? {
                ...prev,
                event: {
                  ...prev.event,
                  status: result.status,
                },
              }
            : prev
        );
        setSuspendOpen(false);
      }
    } finally {
      setActionLoading(null);
    }
  };

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
        {event.status && (
          <Badge
            variant="outline"
            className={statusBadgeColors[event.status] ?? "border-zinc-600 text-zinc-400"}
          >
            {event.status === "pending_review" ? "Pending Review" : event.status}
          </Badge>
        )}
      </div>

      {/* Event Status Actions */}
      <Card className="border-zinc-800 bg-zinc-900">
        <CardHeader>
          <CardTitle className="text-sm text-zinc-400">Event Actions</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          {event.status === "pending_review" && (
            <Button
              size="sm"
              variant="outline"
              onClick={() => handleEventAction("approve")}
              disabled={actionLoading === "approve"}
              className="border-emerald-500/30 text-emerald-400 hover:bg-emerald-950/30"
            >
              <CheckCircle className="mr-2 h-3 w-3" />
              {actionLoading === "approve" ? "..." : "Approve"}
            </Button>
          )}
          {event.status !== "suspended" && (
            <Button
              size="sm"
              variant="outline"
              onClick={() => setSuspendOpen(true)}
              className="border-red-500/30 text-red-400 hover:bg-red-950/30"
            >
              <Ban className="mr-2 h-3 w-3" />
              Suspend
            </Button>
          )}
          {event.status === "suspended" && (
            <Button
              size="sm"
              variant="outline"
              onClick={() => handleEventAction("reactivate")}
              disabled={actionLoading === "reactivate"}
              className="border-emerald-500/30 text-emerald-400 hover:bg-emerald-950/30"
            >
              <ShieldCheck className="mr-2 h-3 w-3" />
              {actionLoading === "reactivate" ? "..." : "Reactivate"}
            </Button>
          )}
        </CardContent>
      </Card>

      {/* Suspend Dialog */}
      <Dialog open={suspendOpen} onOpenChange={setSuspendOpen}>
        <DialogContent className="border-zinc-800 bg-zinc-900">
          <DialogHeader>
            <DialogTitle className="text-white">Suspend Event</DialogTitle>
            <DialogDescription className="text-zinc-400">
              Suspend &quot;{event.title}&quot;? It will no longer be visible to buyers.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label className="text-zinc-300">Reason</Label>
            <Input
              value={suspendReason}
              onChange={(e) => setSuspendReason(e.target.value)}
              placeholder="Reason for suspension..."
              className="border-zinc-700 bg-zinc-800 text-white"
            />
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setSuspendOpen(false)}
              className="border-zinc-700 text-zinc-300"
            >
              Cancel
            </Button>
            <Button
              onClick={() => handleEventAction("suspend", suspendReason)}
              disabled={actionLoading === "suspend"}
              className="bg-red-600 hover:bg-red-700"
            >
              {actionLoading === "suspend" ? "Suspending..." : "Confirm Suspend"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

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
