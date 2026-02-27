"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { Badge } from "@/components/ui/badge";
import { formatCents, formatDate } from "@/lib/utils/format";
import type { ReferralEarning } from "@/types/database";

interface ReferralRow extends ReferralEarning {
  referrer_email?: string;
  referred_email?: string;
}

export const referralColumns: ColumnDef<ReferralRow>[] = [
  {
    accessorKey: "referrer_email",
    header: "Referrer",
  },
  {
    accessorKey: "referred_email",
    header: "Referee",
  },
  {
    accessorKey: "earning_cents",
    header: "Earnings",
    cell: ({ getValue }) => formatCents(getValue() as number),
  },
  {
    accessorKey: "discount_cents",
    header: "Discount",
    cell: ({ getValue }) => formatCents(getValue() as number),
  },
  {
    accessorKey: "platform_fee_cents",
    header: "Fee",
    cell: ({ getValue }) => formatCents(getValue() as number),
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ getValue }) => {
      const status = getValue() as string;
      const colors: Record<string, string> = {
        pending: "border-amber-500/30 text-amber-400",
        paid: "border-emerald-500/30 text-emerald-400",
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
    header: "Date",
    cell: ({ getValue }) => formatDate(getValue() as string),
  },
];
