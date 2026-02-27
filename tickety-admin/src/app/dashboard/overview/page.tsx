"use client";

import { useEffect, useState } from "react";
import { KpiCard } from "@/components/dashboard/kpi-card";
import { RevenueChart } from "@/components/dashboard/revenue-chart";
import { SignupsChart } from "@/components/dashboard/signups-chart";
import { TierDistribution } from "@/components/dashboard/tier-distribution";
import { formatCents, formatCompact } from "@/lib/utils/format";
import {
  Users,
  Calendar,
  DollarSign,
  Crown,
  Ticket,
  Percent,
} from "lucide-react";

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

export default function OverviewPage() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/admin/stats")
      .then((res) => res.json())
      .then(setStats)
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-white">Overview</h1>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
        <KpiCard
          label="Total Users"
          value={stats ? formatCompact(stats.totalUsers) : ""}
          icon={Users}
          loading={loading}
        />
        <KpiCard
          label="Total Events"
          value={stats ? formatCompact(stats.totalEvents) : ""}
          icon={Calendar}
          loading={loading}
        />
        <KpiCard
          label="Total Revenue"
          value={stats ? formatCents(stats.totalRevenue) : ""}
          icon={DollarSign}
          loading={loading}
        />
        <KpiCard
          label="Paid Subscriptions"
          value={stats ? formatCompact(stats.activeSubscriptions) : ""}
          icon={Crown}
          loading={loading}
        />
        <KpiCard
          label="Tickets (30d)"
          value={stats ? formatCompact(stats.ticketsSold30d) : ""}
          icon={Ticket}
          loading={loading}
        />
        <KpiCard
          label="Fees (30d)"
          value={stats ? formatCents(stats.platformFees30d) : ""}
          icon={Percent}
          loading={loading}
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
  );
}
