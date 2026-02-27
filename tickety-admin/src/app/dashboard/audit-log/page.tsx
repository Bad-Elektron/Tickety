"use client";

import { useEffect, useState } from "react";
import { DataTable } from "@/components/tables/data-table";
import { auditLogColumns } from "@/components/tables/columns/audit-log";
import type { AuditLog } from "@/types/database";
import { Skeleton } from "@/components/ui/skeleton";

interface AuditLogRow extends AuditLog {
  admin_email?: string;
}

export default function AuditLogPage() {
  const [logs, setLogs] = useState<AuditLogRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/admin/audit-log")
      .then((res) => res.json())
      .then((data) => {
        if (Array.isArray(data)) {
          setLogs(data);
        }
      })
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-white">Audit Log</h1>
        <Skeleton className="h-96 w-full bg-zinc-800" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-white">Audit Log</h1>
      <DataTable
        columns={auditLogColumns}
        data={logs}
        searchKey="action"
        searchPlaceholder="Search by action..."
        exportFilename="audit-log"
      />
    </div>
  );
}
