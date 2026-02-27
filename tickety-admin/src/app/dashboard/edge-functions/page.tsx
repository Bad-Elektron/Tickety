"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { KpiCard } from "@/components/dashboard/kpi-card";
import { RefreshCw, Zap, CheckCircle2, XCircle, Clock } from "lucide-react";

interface FunctionHealth {
  name: string;
  status: "healthy" | "error" | "timeout";
  responseTime: number | null;
  error?: string;
}

interface HealthSummary {
  total: number;
  healthy: number;
  errors: number;
  timeouts: number;
}

export default function EdgeFunctionsPage() {
  const [functions, setFunctions] = useState<FunctionHealth[]>([]);
  const [summary, setSummary] = useState<HealthSummary | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchHealth = async () => {
    setLoading(true);
    try {
      const res = await fetch("/api/admin/edge-functions/health");
      const data = await res.json();
      setFunctions(data.functions ?? []);
      setSummary(data.summary ?? null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchHealth();
  }, []);

  const statusIcon = (status: string) => {
    switch (status) {
      case "healthy":
        return <CheckCircle2 className="h-4 w-4 text-emerald-400" />;
      case "error":
        return <XCircle className="h-4 w-4 text-red-400" />;
      case "timeout":
        return <Clock className="h-4 w-4 text-amber-400" />;
      default:
        return null;
    }
  };

  const statusBadge = (status: string) => {
    const colors: Record<string, string> = {
      healthy: "border-emerald-500/30 text-emerald-400",
      error: "border-red-500/30 text-red-400",
      timeout: "border-amber-500/30 text-amber-400",
    };
    return (
      <Badge variant="outline" className={colors[status] ?? "text-zinc-400"}>
        {status}
      </Badge>
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-white">Edge Functions</h1>
        <Button
          variant="outline"
          size="sm"
          onClick={fetchHealth}
          disabled={loading}
          className="border-zinc-700 bg-zinc-800 text-zinc-300 hover:bg-zinc-700"
        >
          <RefreshCw className={`mr-2 h-3 w-3 ${loading ? "animate-spin" : ""}`} />
          {loading ? "Checking..." : "Run Health Check"}
        </Button>
      </div>

      {summary && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-4">
          <KpiCard
            label="Total Functions"
            value={String(summary.total)}
            icon={Zap}
          />
          <KpiCard
            label="Healthy"
            value={String(summary.healthy)}
            icon={CheckCircle2}
            deltaType="positive"
            delta={summary.healthy === summary.total ? "all clear" : undefined}
          />
          <KpiCard
            label="Errors"
            value={String(summary.errors)}
            icon={XCircle}
            deltaType={summary.errors > 0 ? "negative" : "positive"}
            delta={summary.errors > 0 ? "needs attention" : undefined}
          />
          <KpiCard
            label="Timeouts"
            value={String(summary.timeouts)}
            icon={Clock}
            deltaType={summary.timeouts > 0 ? "negative" : "neutral"}
          />
        </div>
      )}

      {loading && !functions.length ? (
        <div className="space-y-2">
          {Array.from({ length: 8 }).map((_, i) => (
            <Skeleton key={i} className="h-16 w-full bg-zinc-800" />
          ))}
        </div>
      ) : (
        <div className="space-y-2">
          {functions.map((fn) => (
            <Card key={fn.name} className="border-zinc-800 bg-zinc-900">
              <CardContent className="flex items-center justify-between p-4">
                <div className="flex items-center gap-3">
                  {statusIcon(fn.status)}
                  <div>
                    <p className="font-mono text-sm text-white">{fn.name}</p>
                    {fn.error && (
                      <p className="mt-1 text-xs text-red-400">
                        {fn.error}
                      </p>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-4">
                  {fn.responseTime !== null && (
                    <span
                      className={`text-xs ${
                        fn.responseTime > 5000
                          ? "text-amber-400"
                          : fn.responseTime > 2000
                            ? "text-yellow-400"
                            : "text-zinc-500"
                      }`}
                    >
                      {fn.responseTime}ms
                    </span>
                  )}
                  {statusBadge(fn.status)}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
