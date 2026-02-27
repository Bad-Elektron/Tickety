"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
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
      const supabase = createClient();
      const { data } = await supabase
        .from("subscriptions")
        .select("*, profiles!subscriptions_user_id_fkey(email)")
        .order("created_at", { ascending: false });

      if (!data) {
        setLoading(false);
        return;
      }

      const rows: SubscriptionRow[] = data.map((s) => ({
        ...s,
        user_email: (s.profiles as unknown as { email: string })?.email,
        profiles: undefined,
      }));

      setSubscriptions(rows);
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
