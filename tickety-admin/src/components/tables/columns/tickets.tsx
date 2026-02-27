"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { Badge } from "@/components/ui/badge";
import { formatCents, formatDate } from "@/lib/utils/format";
import type { Ticket } from "@/types/database";

interface TicketRow extends Ticket {
  event_title?: string;
}

export const ticketColumns: ColumnDef<TicketRow>[] = [
  {
    accessorKey: "ticket_number",
    header: "Number",
    cell: ({ getValue }) => (
      <span className="font-mono text-xs text-white">
        {getValue() as string}
      </span>
    ),
  },
  {
    accessorKey: "event_title",
    header: "Event",
  },
  {
    accessorKey: "owner_email",
    header: "Owner",
    cell: ({ getValue }) => (getValue() as string) ?? "-",
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ getValue }) => {
      const status = getValue() as string;
      const colors: Record<string, string> = {
        valid: "border-emerald-500/30 text-emerald-400",
        used: "border-blue-500/30 text-blue-400",
        cancelled: "border-red-500/30 text-red-400",
        refunded: "border-amber-500/30 text-amber-400",
      };
      return (
        <Badge variant="outline" className={colors[status] ?? "text-zinc-400"}>
          {status}
        </Badge>
      );
    },
  },
  {
    accessorKey: "ticket_mode",
    header: "Mode",
    cell: ({ getValue }) => {
      const mode = getValue() as string;
      return (
        <Badge variant="outline" className="border-zinc-600 text-zinc-400">
          {mode}
        </Badge>
      );
    },
  },
  {
    accessorKey: "price_paid_cents",
    header: "Price",
    cell: ({ row }) =>
      formatCents(row.original.price_paid_cents, row.original.currency),
  },
  {
    accessorKey: "sold_at",
    header: "Sold",
    cell: ({ getValue }) => {
      const val = getValue() as string;
      return val ? formatDate(val) : "-";
    },
  },
];
