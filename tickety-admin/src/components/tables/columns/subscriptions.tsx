"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { Badge } from "@/components/ui/badge";
import { formatDate } from "@/lib/utils/format";
import type { Subscription } from "@/types/database";

interface SubscriptionRow extends Subscription {
  user_email?: string;
}

export const subscriptionColumns: ColumnDef<SubscriptionRow>[] = [
  {
    accessorKey: "user_email",
    header: "User",
  },
  {
    accessorKey: "tier",
    header: "Tier",
    cell: ({ getValue }) => {
      const tier = getValue() as string;
      const colors: Record<string, string> = {
        base: "border-zinc-600 text-zinc-400",
        pro: "border-indigo-500/30 text-indigo-400",
        enterprise: "border-amber-500/30 text-amber-400",
      };
      return (
        <Badge variant="outline" className={colors[tier] ?? colors.base}>
          {tier}
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
        active: "border-emerald-500/30 text-emerald-400",
        canceled: "border-red-500/30 text-red-400",
        past_due: "border-amber-500/30 text-amber-400",
        trialing: "border-blue-500/30 text-blue-400",
        paused: "border-zinc-500/30 text-zinc-400",
      };
      return (
        <Badge variant="outline" className={colors[status] ?? "text-zinc-400"}>
          {status}
        </Badge>
      );
    },
  },
  {
    accessorKey: "current_period_start",
    header: "Period Start",
    cell: ({ getValue }) => {
      const val = getValue() as string | null;
      return val ? formatDate(val) : "-";
    },
  },
  {
    accessorKey: "current_period_end",
    header: "Period End",
    cell: ({ getValue }) => {
      const val = getValue() as string | null;
      return val ? formatDate(val) : "-";
    },
  },
  {
    accessorKey: "stripe_subscription_id",
    header: "Stripe ID",
    cell: ({ getValue }) => {
      const val = getValue() as string | null;
      return val ? (
        <span className="font-mono text-xs">{val.slice(0, 20)}...</span>
      ) : (
        "-"
      );
    },
  },
];
