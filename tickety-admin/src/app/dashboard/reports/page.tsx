"use client";

import { useEffect, useState } from "react";
import { DataTable } from "@/components/tables/data-table";
import { reportColumns } from "@/components/tables/columns/reports";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";

interface Report {
  id: string;
  event_id: string;
  event_title: string;
  reporter_email: string;
  reason: string;
  description: string | null;
  status: string;
  created_at: string;
}

export default function ReportsPage() {
  const [reports, setReports] = useState<Report[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const fetchReports = async () => {
    try {
      const res = await fetch("/api/admin/reports");
      if (res.ok) {
        const data = await res.json();
        setReports(data);
      }
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchReports();
  }, []);

  const handleStatusChange = async (reportId: string, newStatus: string) => {
    setActionLoading(reportId);
    try {
      const res = await fetch("/api/admin/reports", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: reportId, status: newStatus }),
      });

      if (res.ok) {
        setReports((prev) =>
          prev.map((r) =>
            r.id === reportId ? { ...r, status: newStatus } : r
          )
        );
      }
    } finally {
      setActionLoading(null);
    }
  };

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-48 bg-zinc-800" />
        <Skeleton className="h-64 w-full bg-zinc-800" />
      </div>
    );
  }

  const openReports = reports.filter((r) => r.status === "open");

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Event Reports</h1>
          <p className="text-sm text-zinc-400">
            {openReports.length} open report{openReports.length !== 1 ? "s" : ""}
          </p>
        </div>
      </div>

      <DataTable
        columns={[
          ...reportColumns,
          {
            id: "actions",
            header: "Actions",
            cell: ({ row }) => {
              const report = row.original;
              if (report.status !== "open") return null;
              return (
                <div className="flex gap-1">
                  <Select
                    onValueChange={(val) =>
                      handleStatusChange(report.id, val)
                    }
                    disabled={actionLoading === report.id}
                  >
                    <SelectTrigger className="h-7 w-[110px] border-zinc-700 bg-zinc-800 text-xs text-zinc-300">
                      <SelectValue placeholder="Review..." />
                    </SelectTrigger>
                    <SelectContent className="border-zinc-700 bg-zinc-800">
                      <SelectItem value="reviewed">Mark Reviewed</SelectItem>
                      <SelectItem value="resolved">Resolve</SelectItem>
                      <SelectItem value="dismissed">Dismiss</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              );
            },
          },
        ]}
        data={reports}
        exportFilename="event-reports"
      />
    </div>
  );
}
