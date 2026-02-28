"use client";

import { useEffect, useState } from "react";
import { DataTable } from "@/components/tables/data-table";
import { ticketColumns } from "@/components/tables/columns/tickets";
import type { Ticket } from "@/types/database";
import { Skeleton } from "@/components/ui/skeleton";

interface TicketRow extends Ticket {
  event_title?: string;
}

export default function TicketsPage() {
  const [tickets, setTickets] = useState<TicketRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchTickets() {
      try {
        const res = await fetch("/api/admin/tickets");
        if (!res.ok) {
          setLoading(false);
          return;
        }
        const data = await res.json();
        setTickets(data);
      } catch {
        // Fetch failed
      }
      setLoading(false);
    }
    fetchTickets();
  }, []);

  if (loading) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-white">Tickets</h1>
        <Skeleton className="h-96 w-full bg-zinc-800" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-white">Tickets</h1>
      <DataTable
        columns={ticketColumns}
        data={tickets}
        searchKey="ticket_number"
        searchPlaceholder="Search by ticket number..."
        exportFilename="tickets"
      />
    </div>
  );
}
