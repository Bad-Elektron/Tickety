"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { DataTable } from "@/components/tables/data-table";
import { userColumns } from "@/components/tables/columns/users";
import type { Profile } from "@/types/database";
import { Skeleton } from "@/components/ui/skeleton";

interface UserRow extends Profile {
  subscription_tier?: string;
}

export default function UsersPage() {
  const [users, setUsers] = useState<UserRow[]>([]);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    async function fetchUsers() {
      const supabase = createClient();
      const { data: profiles } = await supabase
        .from("profiles")
        .select("*")
        .order("email", { ascending: true });

      if (!profiles) {
        setLoading(false);
        return;
      }

      // Fetch subscriptions to join tier
      const { data: subs } = await supabase
        .from("subscriptions")
        .select("user_id, tier");

      const subMap = new Map(
        subs?.map((s) => [s.user_id, s.tier]) ?? []
      );

      const rows: UserRow[] = profiles.map((p) => ({
        ...p,
        subscription_tier: subMap.get(p.id) ?? "base",
      }));

      setUsers(rows);
      setLoading(false);
    }
    fetchUsers();
  }, []);

  if (loading) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-white">Users</h1>
        <Skeleton className="h-96 w-full bg-zinc-800" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-white">Users</h1>
      <DataTable
        columns={userColumns}
        data={users}
        searchKey="email"
        searchPlaceholder="Search by email..."
        exportFilename="users"
        onRowClick={(row) => router.push(`/dashboard/users/${row.id}`)}
      />
    </div>
  );
}
