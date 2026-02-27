"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { DataTable } from "@/components/tables/data-table";
import { eventColumns } from "@/components/tables/columns/events";
import type { Event } from "@/types/database";
import { Skeleton } from "@/components/ui/skeleton";

interface EventRow extends Event {
  organizer_name?: string;
  ticket_count?: number;
}

export default function EventsPage() {
  const [events, setEvents] = useState<EventRow[]>([]);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    async function fetchEvents() {
      const supabase = createClient();
      const { data } = await supabase
        .from("events")
        .select("*, profiles!events_organizer_id_fkey(display_name, email)")
        .is("deleted_at", null)
        .order("date", { ascending: false });

      if (!data) {
        setLoading(false);
        return;
      }

      // Get ticket counts per event
      const eventIds = data.map((e) => e.id);
      const { data: ticketCounts } = await supabase
        .from("tickets")
        .select("event_id")
        .in("event_id", eventIds);

      const countMap = new Map<string, number>();
      ticketCounts?.forEach((t) => {
        countMap.set(t.event_id, (countMap.get(t.event_id) ?? 0) + 1);
      });

      const rows: EventRow[] = data.map((e) => {
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

      setEvents(rows);
      setLoading(false);
    }
    fetchEvents();
  }, []);

  if (loading) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-white">Events</h1>
        <Skeleton className="h-96 w-full bg-zinc-800" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-white">Events</h1>
      <DataTable
        columns={eventColumns}
        data={events}
        searchKey="title"
        searchPlaceholder="Search by title..."
        exportFilename="events"
        onRowClick={(row) => router.push(`/dashboard/events/${row.id}`)}
      />
    </div>
  );
}
