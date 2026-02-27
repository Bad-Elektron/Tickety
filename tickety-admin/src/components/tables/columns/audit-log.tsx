"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { Badge } from "@/components/ui/badge";
import { formatDateTime } from "@/lib/utils/format";
import type { AuditLog } from "@/types/database";

interface AuditLogRow extends AuditLog {
  admin_email?: string;
}

export const auditLogColumns: ColumnDef<AuditLogRow>[] = [
  {
    accessorKey: "admin_email",
    header: "Admin",
  },
  {
    accessorKey: "action",
    header: "Action",
    cell: ({ getValue }) => (
      <Badge variant="outline" className="border-zinc-600 text-zinc-300">
        {getValue() as string}
      </Badge>
    ),
  },
  {
    accessorKey: "target_table",
    header: "Target",
    cell: ({ row }) => {
      const table = row.original.target_table;
      const id = row.original.target_id;
      if (!table) return "-";
      return (
        <span className="text-xs">
          {table}
          {id && (
            <span className="ml-1 font-mono text-zinc-500">
              {id.slice(0, 8)}
            </span>
          )}
        </span>
      );
    },
  },
  {
    accessorKey: "details",
    header: "Details",
    cell: ({ getValue }) => {
      const details = getValue() as Record<string, unknown> | null;
      if (!details) return "-";
      return (
        <span className="max-w-[200px] truncate text-xs text-zinc-500">
          {JSON.stringify(details)}
        </span>
      );
    },
  },
  {
    accessorKey: "created_at",
    header: "Date",
    cell: ({ getValue }) => formatDateTime(getValue() as string),
  },
];
