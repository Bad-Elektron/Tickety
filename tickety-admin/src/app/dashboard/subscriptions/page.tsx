"use client";

import { useEffect, useState } from "react";
import { DataTable } from "@/components/tables/data-table";
import { subscriptionColumns } from "@/components/tables/columns/subscriptions";
import type { Subscription } from "@/types/database";
import { Skeleton } from "@/components/ui/skeleton";

interface SubscriptionRow extends Subscription {
  user_email?: string;
}

export default function SubscriptionsPage() {
  const [subscriptions, setSubscriptions] = useState<SubscriptionRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchSubscriptions() {
      try {
        const res = await fetch("/api/admin/subscriptions");
        if (!res.ok) {
          setLoading(false);
          return;
        }
        const data = await res.json();
        setSubscriptions(data);
      } catch {
        // Fetch failed
      }
      setLoading(false);
    }
    fetchSubscriptions();
  }, []);

  if (loading) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-white">Subscriptions</h1>
        <Skeleton className="h-96 w-full bg-zinc-800" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-white">Subscriptions</h1>
      <DataTable
        columns={subscriptionColumns}
        data={subscriptions}
        searchKey="user_email"
        searchPlaceholder="Search by email..."
        exportFilename="subscriptions"
      />
    </div>
  );
}
