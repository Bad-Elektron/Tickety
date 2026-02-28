"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
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
      try {
        const res = await fetch("/api/admin/events");
        if (!res.ok) {
          setLoading(false);
          return;
        }
        const data = await res.json();
        setEvents(data);
      } catch {
        // Fetch failed
      }
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
