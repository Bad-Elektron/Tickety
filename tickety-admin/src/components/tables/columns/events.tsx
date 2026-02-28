"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { Badge } from "@/components/ui/badge";
import { formatCents, formatDate } from "@/lib/utils/format";
import type { Event } from "@/types/database";

interface EventRow extends Event {
  organizer_name?: string;
  ticket_count?: number;
}

const statusColors: Record<string, string> = {
  active: "border-emerald-500/30 text-emerald-400",
  pending_review: "border-amber-500/30 text-amber-400",
  suspended: "border-red-500/30 text-red-400",
};

export const eventColumns: ColumnDef<EventRow>[] = [
  {
    accessorKey: "title",
    header: "Title",
    cell: ({ getValue }) => (
      <span className="font-medium text-white">{getValue() as string}</span>
    ),
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ getValue }) => {
      const status = (getValue() as string) ?? "active";
      return (
        <Badge
          variant="outline"
          className={statusColors[status] ?? "border-zinc-600 text-zinc-400"}
        >
          {status === "pending_review" ? "Pending" : status}
        </Badge>
      );
    },
  },
  {
    accessorKey: "organizer_name",
    header: "Organizer",
  },
  {
    accessorKey: "date",
    header: "Date",
    cell: ({ getValue }) => formatDate(getValue() as string),
  },
  {
    accessorKey: "city",
    header: "City",
    cell: ({ getValue }) => (getValue() as string) ?? "-",
  },
  {
    accessorKey: "priceInCents",
    header: "Price",
    cell: ({ row }) => {
      const cents = row.original.priceInCents;
      return cents ? formatCents(cents, row.original.currency) : "Free";
    },
  },
  {
    accessorKey: "category",
    header: "Category",
    cell: ({ getValue }) => {
      const cat = getValue() as string | null;
      return cat ? (
        <Badge variant="outline" className="border-zinc-600 text-zinc-400">
          {cat}
        </Badge>
      ) : (
        "-"
      );
    },
  },
  {
    accessorKey: "ticket_count",
    header: "Tickets",
    cell: ({ getValue }) => (getValue() as number) ?? 0,
  },
];
