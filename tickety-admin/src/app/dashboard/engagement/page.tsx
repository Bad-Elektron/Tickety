"use client";

import { useEffect, useState } from "react";
import { KpiCard } from "@/components/dashboard/kpi-card";
import { EngagementChart } from "@/components/dashboard/engagement-chart";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatCompact, formatRelative } from "@/lib/utils/format";
import { useRouter } from "next/navigation";
import { Eye, Users, Percent, Clock } from "lucide-react";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";

interface EngagementData {
  total_views_30d: number;
  total_unique_viewers_30d: number;
  avg_conversion_rate: number;
  weekly_views: { week_start: string; views: number }[];
  top_events: {
    event_id: string;
    title: string;
    total_views: number;
    unique_viewers: number;
    conversion_rate: number;
  }[];
  top_tags: { tag: string; views: number }[];
  city_breakdown: { city: string; views: number }[];
  last_refreshed: string | null;
}

export default function EngagementPage() {
  const [data, setData] = useState<EngagementData | null>(null);
  const [loading, setLoading] = useState(true);
  const [cityFilter, setCityFilter] = useState("");
  const router = useRouter();
  // Store cities from the unfiltered response so the dropdown stays stable
  const [cities, setCities] = useState<string[]>([]);

  useEffect(() => {
    setLoading(true);
    const params = cityFilter ? `?city=${encodeURIComponent(cityFilter)}` : "";
    fetch(`/api/admin/engagement${params}`)
      .then((res) => res.json())
      .then((json) => {
        setData(json);
        // Only update city list from unfiltered responses
        if (!cityFilter && json.city_breakdown) {
          setCities(json.city_breakdown.map((c: { city: string }) => c.city).filter(Boolean));
        }
      })
      .finally(() => setLoading(false));
  }, [cityFilter]);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-white">Engagement</h1>
        <select
          value={cityFilter}
          onChange={(e) => setCityFilter(e.target.value)}
          className="rounded-lg border border-zinc-700 bg-zinc-800 px-3 py-2 text-sm text-zinc-200 focus:border-indigo-500 focus:outline-none"
        >
          <option value="">All Cities</option>
          {cities.map((city) => (
            <option key={city} value={city}>
              {city}
            </option>
          ))}
        </select>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Views (30d)"
          value={data ? formatCompact(data.total_views_30d) : ""}
          icon={Eye}
          loading={loading}
        />
        <KpiCard
          label="Unique Viewers (30d)"
          value={data ? formatCompact(data.total_unique_viewers_30d) : ""}
          icon={Users}
          loading={loading}
        />
        <KpiCard
          label="Avg Conversion Rate"
          value={data ? `${data.avg_conversion_rate}%` : ""}
          icon={Percent}
          loading={loading}
        />
        <KpiCard
          label="Last Refreshed"
          value={
            data?.last_refreshed ? formatRelative(data.last_refreshed) : "Never"
          }
          icon={Clock}
          loading={loading}
        />
      </div>

      {/* Weekly Views Chart */}
      <EngagementChart data={data?.weekly_views ?? []} />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* Top Events Table */}
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm font-medium text-zinc-400">
              Top Events (30d)
            </CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="space-y-3">
                {Array.from({ length: 5 }).map((_, i) => (
                  <div
                    key={i}
                    className="h-8 animate-pulse rounded bg-zinc-800"
                  />
                ))}
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-zinc-800 text-left text-zinc-500">
                      <th className="pb-2 font-medium">Event</th>
                      <th className="pb-2 text-right font-medium">Views</th>
                      <th className="pb-2 text-right font-medium">Unique</th>
                      <th className="pb-2 text-right font-medium">Conv %</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(data?.top_events ?? []).map((event) => (
                      <tr
                        key={event.event_id}
                        className="cursor-pointer border-b border-zinc-800/50 hover:bg-zinc-800/30"
                        onClick={() => router.push(`/dashboard/events/${event.event_id}`)}
                      >
                        <td
                          className="max-w-[200px] truncate py-2 text-zinc-200"
                          title={event.title}
                        >
                          {event.title}
                        </td>
                        <td className="py-2 text-right text-zinc-300">
                          {formatCompact(event.total_views)}
                        </td>
                        <td className="py-2 text-right text-zinc-300">
                          {formatCompact(event.unique_viewers)}
                        </td>
                        <td className="py-2 text-right text-zinc-300">
                          {event.conversion_rate}%
                        </td>
                      </tr>
                    ))}
                    {(data?.top_events ?? []).length === 0 && (
                      <tr>
                        <td
                          colSpan={4}
                          className="py-4 text-center text-zinc-500"
                        >
                          No data yet
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Top Tags Bar Chart */}
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm font-medium text-zinc-400">
              Top Tags by Views (30d)
            </CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="space-y-3">
                {Array.from({ length: 5 }).map((_, i) => (
                  <div
                    key={i}
                    className="h-8 animate-pulse rounded bg-zinc-800"
                  />
                ))}
              </div>
            ) : (data?.top_tags ?? []).length > 0 ? (
              <ResponsiveContainer width="100%" height={300}>
                <BarChart
                  data={data?.top_tags ?? []}
                  layout="vertical"
                  margin={{ left: 80 }}
                >
                  <CartesianGrid
                    strokeDasharray="3 3"
                    stroke="#27272a"
                    horizontal={false}
                  />
                  <XAxis
                    type="number"
                    stroke="#71717a"
                    fontSize={12}
                    tickLine={false}
                  />
                  <YAxis
                    type="category"
                    dataKey="tag"
                    stroke="#71717a"
                    fontSize={12}
                    tickLine={false}
                    width={75}
                  />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: "#18181b",
                      border: "1px solid #27272a",
                      borderRadius: "8px",
                      color: "#fff",
                    }}
                    formatter={(value) => [
                      Number(value).toLocaleString(),
                      "Views",
                    ]}
                  />
                  <Bar
                    dataKey="views"
                    fill="#6366f1"
                    radius={[0, 4, 4, 0]}
                  />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <p className="py-8 text-center text-zinc-500">No data yet</p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* City Breakdown Table */}
      {!cityFilter && (
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm font-medium text-zinc-400">
              City Breakdown (30d)
            </CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="space-y-3">
                {Array.from({ length: 5 }).map((_, i) => (
                  <div
                    key={i}
                    className="h-8 animate-pulse rounded bg-zinc-800"
                  />
                ))}
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-zinc-800 text-left text-zinc-500">
                      <th className="pb-2 font-medium">City</th>
                      <th className="pb-2 text-right font-medium">Views</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(data?.city_breakdown ?? []).map((row) => (
                      <tr
                        key={row.city}
                        className="border-b border-zinc-800/50"
                      >
                        <td className="py-2 text-zinc-200">{row.city}</td>
                        <td className="py-2 text-right text-zinc-300">
                          {formatCompact(row.views)}
                        </td>
                      </tr>
                    ))}
                    {(data?.city_breakdown ?? []).length === 0 && (
                      <tr>
                        <td
                          colSpan={2}
                          className="py-4 text-center text-zinc-500"
                        >
                          No data yet
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
