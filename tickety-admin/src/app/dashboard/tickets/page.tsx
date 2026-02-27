"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
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
      const supabase = createClient();
      const { data } = await supabase
        .from("tickets")
        .select("*, events(title)")
        .order("sold_at", { ascending: false })
        .limit(500);

      if (!data) {
        setLoading(false);
        return;
      }

      const rows: TicketRow[] = data.map((t) => ({
        ...t,
        event_title: (t.events as unknown as { title: string })?.title,
        events: undefined,
      }));

      setTickets(rows);
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
