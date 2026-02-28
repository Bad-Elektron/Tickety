"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { Badge } from "@/components/ui/badge";
import { formatDate } from "@/lib/utils/format";

interface ReportRow {
  id: string;
  event_id: string;
  event_title: string;
  reporter_email: string;
  reason: string;
  description: string | null;
  status: string;
  created_at: string;
}

const statusColors: Record<string, string> = {
  open: "border-amber-500/30 text-amber-400",
  reviewed: "border-blue-500/30 text-blue-400",
  resolved: "border-emerald-500/30 text-emerald-400",
  dismissed: "border-zinc-600 text-zinc-400",
};

const reasonLabels: Record<string, string> = {
  impersonation: "Impersonation",
  scam: "Scam / Fraud",
  inappropriate: "Inappropriate",
  duplicate: "Duplicate",
  other: "Other",
};

export const reportColumns: ColumnDef<ReportRow>[] = [
  {
    accessorKey: "event_title",
    header: "Event",
    cell: ({ getValue }) => (
      <span className="font-medium text-white">{getValue() as string}</span>
    ),
  },
  {
    accessorKey: "reporter_email",
    header: "Reporter",
  },
  {
    accessorKey: "reason",
    header: "Reason",
    cell: ({ getValue }) => {
      const reason = getValue() as string;
      return (
        <Badge variant="outline" className="border-zinc-600 text-zinc-400">
          {reasonLabels[reason] ?? reason}
        </Badge>
      );
    },
  },
  {
    accessorKey: "description",
    header: "Description",
    cell: ({ getValue }) => {
      const desc = getValue() as string | null;
      return desc ? (
        <span className="max-w-[200px] truncate text-sm text-zinc-400">
          {desc}
        </span>
      ) : (
        "-"
      );
    },
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ getValue }) => {
      const status = getValue() as string;
      return (
        <Badge
          variant="outline"
          className={statusColors[status] ?? "border-zinc-600 text-zinc-400"}
        >
          {status}
        </Badge>
      );
    },
  },
  {
    accessorKey: "created_at",
    header: "Reported",
    cell: ({ getValue }) => formatDate(getValue() as string),
  },
];
