"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { KpiCard } from "@/components/dashboard/kpi-card";
import { formatDateTime } from "@/lib/utils/format";
import { Webhook, RefreshCw, RotateCcw } from "lucide-react";

interface WebhookEvent {
  id: string;
  stripe_event_id: string;
  event_type: string;
  status: string;
  error_message: string | null;
  processing_time_ms: number | null;
  created_at: string;
  processed_at: string | null;
}

interface WebhookStats {
  total: number;
  failed: number;
  last24h: number;
}

export default function WebhooksPage() {
  const [events, setEvents] = useState<WebhookEvent[]>([]);
  const [stats, setStats] = useState<WebhookStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState("all");
  const [replaying, setReplaying] = useState<string | null>(null);

  const fetchData = async () => {
    setLoading(true);
    const res = await fetch(`/api/admin/webhooks?status=${filter}`);
    const data = await res.json();
    setEvents(data.events ?? []);
    setStats(data.stats ?? null);
    setLoading(false);
  };

  useEffect(() => {
    fetchData();
  }, [filter]);

  const handleReplay = async (eventId: string) => {
    setReplaying(eventId);
    try {
      const res = await fetch("/api/admin/webhooks/replay", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ webhook_event_id: eventId }),
      });
      if (res.ok) {
        fetchData();
      }
    } finally {
      setReplaying(null);
    }
  };

  const statusColor: Record<string, string> = {
    received: "border-zinc-500/30 text-zinc-400",
    processing: "border-blue-500/30 text-blue-400",
    succeeded: "border-emerald-500/30 text-emerald-400",
    failed: "border-red-500/30 text-red-400",
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-white">Webhook Events</h1>
        <Button
          variant="outline"
          size="sm"
          onClick={fetchData}
          className="border-zinc-700 bg-zinc-800 text-zinc-300 hover:bg-zinc-700"
        >
          <RefreshCw className="mr-2 h-3 w-3" />
          Refresh
        </Button>
      </div>

      {stats && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <KpiCard label="Total Events" value={String(stats.total)} icon={Webhook} />
          <KpiCard
            label="Failed"
            value={String(stats.failed)}
            icon={Webhook}
            delta={stats.failed > 0 ? "needs attention" : "all clear"}
            deltaType={stats.failed > 0 ? "negative" : "positive"}
          />
          <KpiCard label="Last 24h" value={String(stats.last24h)} icon={Webhook} />
        </div>
      )}

      <div className="flex items-center gap-4">
        <Select value={filter} onValueChange={setFilter}>
          <SelectTrigger className="w-40 border-zinc-700 bg-zinc-800 text-white">
            <SelectValue placeholder="Filter status" />
          </SelectTrigger>
          <SelectContent className="border-zinc-700 bg-zinc-800">
            <SelectItem value="all">All</SelectItem>
            <SelectItem value="succeeded">Succeeded</SelectItem>
            <SelectItem value="failed">Failed</SelectItem>
            <SelectItem value="processing">Processing</SelectItem>
            <SelectItem value="received">Received</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {loading ? (
        <Skeleton className="h-96 w-full bg-zinc-800" />
      ) : events.length === 0 ? (
        <Card className="border-zinc-800 bg-zinc-900">
          <CardContent className="flex h-48 items-center justify-center">
            <p className="text-zinc-500">
              No webhook events yet. Events will appear here once your Stripe
              webhooks start logging to the webhook_events table.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-2">
          {events.map((event) => (
            <Card key={event.id} className="border-zinc-800 bg-zinc-900">
              <CardContent className="flex items-center justify-between p-4">
                <div className="flex items-center gap-4">
                  <Badge
                    variant="outline"
                    className={statusColor[event.status] ?? "text-zinc-400"}
                  >
                    {event.status}
                  </Badge>
                  <div>
                    <p className="text-sm font-medium text-white">
                      {event.event_type}
                    </p>
                    <p className="font-mono text-xs text-zinc-500">
                      {event.stripe_event_id}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-4">
                  {event.processing_time_ms !== null && (
                    <span className="text-xs text-zinc-500">
                      {event.processing_time_ms}ms
                    </span>
                  )}
                  <span className="text-xs text-zinc-500">
                    {formatDateTime(event.created_at)}
                  </span>
                  {event.status === "failed" && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleReplay(event.id)}
                      disabled={replaying === event.id}
                      className="border-zinc-700 bg-zinc-800 text-zinc-300 hover:bg-zinc-700"
                    >
                      <RotateCcw className="mr-1 h-3 w-3" />
                      {replaying === event.id ? "..." : "Replay"}
                    </Button>
                  )}
                </div>
              </CardContent>
              {event.error_message && (
                <CardContent className="-mt-2 px-4 pb-4">
                  <p className="rounded bg-red-950/30 px-3 py-2 text-xs text-red-400">
                    {event.error_message}
                  </p>
                </CardContent>
              )}
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
