"use client";

import { useEffect, useState } from "react";
import { KpiCard } from "@/components/dashboard/kpi-card";
import { RevenueChart } from "@/components/dashboard/revenue-chart";
import { SignupsChart } from "@/components/dashboard/signups-chart";
import { TierDistribution } from "@/components/dashboard/tier-distribution";
import { EngagementChart } from "@/components/dashboard/engagement-chart";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { formatCents, formatCompact, formatRelative } from "@/lib/utils/format";
import { useRouter } from "next/navigation";
import {
  Users,
  Calendar,
  DollarSign,
  Crown,
  Ticket,
  Percent,
  Eye,
  Clock,
} from "lucide-react";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";

interface Stats {
  totalUsers: number;
  totalEvents: number;
  totalRevenue: number;
  activeSubscriptions: number;
  ticketsSold30d: number;
  platformFees30d: number;
  revenueWeekly: { week: string; revenue: number }[];
  signupsWeekly: { week: string; signups: number }[];
  tierDistribution: { name: string; value: number }[];
}

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

export default function AnalyticsPage() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [statsLoading, setStatsLoading] = useState(true);
  const [engagement, setEngagement] = useState<EngagementData | null>(null);
  const [engagementLoading, setEngagementLoading] = useState(true);
  const [cityFilter, setCityFilter] = useState("");
  const [cities, setCities] = useState<string[]>([]);
  const router = useRouter();

  useEffect(() => {
    fetch("/api/admin/stats")
      .then((res) => res.json())
      .then(setStats)
      .finally(() => setStatsLoading(false));
  }, []);

  useEffect(() => {
    setEngagementLoading(true);
    const params = cityFilter ? `?city=${encodeURIComponent(cityFilter)}` : "";
    fetch(`/api/admin/engagement${params}`)
      .then((res) => res.json())
      .then((json) => {
        setEngagement(json);
        if (!cityFilter && json.city_breakdown) {
          setCities(
            json.city_breakdown
              .map((c: { city: string }) => c.city)
              .filter(Boolean)
          );
        }
      })
      .finally(() => setEngagementLoading(false));
  }, [cityFilter]);

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-white">Analytics</h1>

      <Tabs defaultValue="overview">
        <TabsList className="bg-zinc-800/50 border border-zinc-700">
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="engagement">Engagement</TabsTrigger>
        </TabsList>

        <TabsContent value="overview">
          <div className="space-y-6 pt-2">
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
              <KpiCard
                label="Total Users"
                value={stats ? formatCompact(stats.totalUsers) : ""}
                icon={Users}
                loading={statsLoading}
              />
              <KpiCard
                label="Total Events"
                value={stats ? formatCompact(stats.totalEvents) : ""}
                icon={Calendar}
                loading={statsLoading}
              />
              <KpiCard
                label="Total Revenue"
                value={stats ? formatCents(stats.totalRevenue) : ""}
                icon={DollarSign}
                loading={statsLoading}
              />
              <KpiCard
                label="Paid Subscriptions"
                value={stats ? formatCompact(stats.activeSubscriptions) : ""}
                icon={Crown}
                loading={statsLoading}
              />
              <KpiCard
                label="Tickets (30d)"
                value={stats ? formatCompact(stats.ticketsSold30d) : ""}
                icon={Ticket}
                loading={statsLoading}
              />
              <KpiCard
                label="Fees (30d)"
                value={stats ? formatCents(stats.platformFees30d) : ""}
                icon={Percent}
                loading={statsLoading}
              />
            </div>

            <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
              <RevenueChart data={stats?.revenueWeekly ?? []} />
              <SignupsChart data={stats?.signupsWeekly ?? []} />
            </div>

            <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
              <TierDistribution data={stats?.tierDistribution ?? []} />
            </div>
          </div>
        </TabsContent>

        <TabsContent value="engagement">
          <div className="space-y-6 pt-2">
            <div className="flex items-center justify-end">
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

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <KpiCard
                label="Views (30d)"
                value={
                  engagement
                    ? formatCompact(engagement.total_views_30d)
                    : ""
                }
                icon={Eye}
                loading={engagementLoading}
              />
              <KpiCard
                label="Unique Viewers (30d)"
                value={
                  engagement
                    ? formatCompact(engagement.total_unique_viewers_30d)
                    : ""
                }
                icon={Users}
                loading={engagementLoading}
              />
              <KpiCard
                label="Avg Conversion Rate"
                value={
                  engagement ? `${engagement.avg_conversion_rate}%` : ""
                }
                icon={Percent}
                loading={engagementLoading}
              />
              <KpiCard
                label="Last Refreshed"
                value={
                  engagement?.last_refreshed
                    ? formatRelative(engagement.last_refreshed)
                    : "Never"
                }
                icon={Clock}
                loading={engagementLoading}
              />
            </div>

            <EngagementChart data={engagement?.weekly_views ?? []} />

            <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
              {/* Top Events Table */}
              <Card className="border-zinc-800 bg-zinc-900">
                <CardHeader>
                  <CardTitle className="text-sm font-medium text-zinc-400">
                    Top Events (30d)
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  {engagementLoading ? (
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
                            <th className="pb-2 text-right font-medium">
                              Views
                            </th>
                            <th className="pb-2 text-right font-medium">
                              Unique
                            </th>
                            <th className="pb-2 text-right font-medium">
                              Conv %
                            </th>
                          </tr>
                        </thead>
                        <tbody>
                          {(engagement?.top_events ?? []).map((event) => (
                            <tr
                              key={event.event_id}
                              className="cursor-pointer border-b border-zinc-800/50 hover:bg-zinc-800/30"
                              onClick={() =>
                                router.push(
                                  `/dashboard/events/${event.event_id}`
                                )
                              }
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
                          {(engagement?.top_events ?? []).length === 0 && (
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
                  {engagementLoading ? (
                    <div className="space-y-3">
                      {Array.from({ length: 5 }).map((_, i) => (
                        <div
                          key={i}
                          className="h-8 animate-pulse rounded bg-zinc-800"
                        />
                      ))}
                    </div>
                  ) : (engagement?.top_tags ?? []).length > 0 ? (
                    <ResponsiveContainer width="100%" height={300}>
                      <BarChart
                        data={engagement?.top_tags ?? []}
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
                    <p className="py-8 text-center text-zinc-500">
                      No data yet
                    </p>
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
                  {engagementLoading ? (
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
                            <th className="pb-2 text-right font-medium">
                              Views
                            </th>
                          </tr>
                        </thead>
                        <tbody>
                          {(engagement?.city_breakdown ?? []).map((row) => (
                            <tr
                              key={row.city}
                              className="border-b border-zinc-800/50"
                            >
                              <td className="py-2 text-zinc-200">
                                {row.city}
                              </td>
                              <td className="py-2 text-right text-zinc-300">
                                {formatCompact(row.views)}
                              </td>
                            </tr>
                          ))}
                          {(engagement?.city_breakdown ?? []).length === 0 && (
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
        </TabsContent>
      </Tabs>
    </div>
  );
}
