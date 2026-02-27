"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { Badge } from "@/components/ui/badge";
import { formatCents, formatDate } from "@/lib/utils/format";
import type { ResaleListing } from "@/types/database";

interface ResaleRow extends ResaleListing {
  seller_email?: string;
  event_title?: string;
  ticket_number?: string;
}

export const resaleColumns: ColumnDef<ResaleRow>[] = [
  {
    accessorKey: "ticket_number",
    header: "Ticket",
    cell: ({ getValue }) => (
      <span className="font-mono text-xs text-white">
        {(getValue() as string) ?? "-"}
      </span>
    ),
  },
  {
    accessorKey: "event_title",
    header: "Event",
  },
  {
    accessorKey: "seller_email",
    header: "Seller",
  },
  {
    accessorKey: "price_cents",
    header: "Price",
    cell: ({ row }) =>
      formatCents(row.original.price_cents, row.original.currency),
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ getValue }) => {
      const status = getValue() as string;
      const colors: Record<string, string> = {
        active: "border-emerald-500/30 text-emerald-400",
        sold: "border-blue-500/30 text-blue-400",
        cancelled: "border-red-500/30 text-red-400",
      };
      return (
        <Badge variant="outline" className={colors[status] ?? "text-zinc-400"}>
          {status}
        </Badge>
      );
    },
  },
  {
    accessorKey: "created_at",
    header: "Listed",
    cell: ({ getValue }) => formatDate(getValue() as string),
  },
];
