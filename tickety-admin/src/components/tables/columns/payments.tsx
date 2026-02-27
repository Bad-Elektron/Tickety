"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { Badge } from "@/components/ui/badge";
import { formatCents, formatDateTime } from "@/lib/utils/format";
import type { Payment } from "@/types/database";

interface PaymentRow extends Payment {
  user_email?: string;
  event_title?: string;
}

export const paymentColumns: ColumnDef<PaymentRow>[] = [
  {
    accessorKey: "user_email",
    header: "User",
  },
  {
    accessorKey: "event_title",
    header: "Event",
  },
  {
    accessorKey: "amount_cents",
    header: "Amount",
    cell: ({ row }) =>
      formatCents(row.original.amount_cents, row.original.currency),
  },
  {
    accessorKey: "platform_fee_cents",
    header: "Fee",
    cell: ({ row }) =>
      formatCents(row.original.platform_fee_cents, row.original.currency),
  },
  {
    accessorKey: "type",
    header: "Type",
    cell: ({ getValue }) => {
      const type = (getValue() as string).replace(/_/g, " ");
      return (
        <Badge variant="outline" className="border-zinc-600 text-zinc-400">
          {type}
        </Badge>
      );
    },
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ getValue }) => {
      const status = getValue() as string;
      const colors: Record<string, string> = {
        completed: "border-emerald-500/30 text-emerald-400",
        pending: "border-amber-500/30 text-amber-400",
        processing: "border-blue-500/30 text-blue-400",
        failed: "border-red-500/30 text-red-400",
        refunded: "border-zinc-500/30 text-zinc-400",
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
    header: "Date",
    cell: ({ getValue }) => formatDateTime(getValue() as string),
  },
];
