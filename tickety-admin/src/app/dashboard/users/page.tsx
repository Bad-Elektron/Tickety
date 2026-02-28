"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
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
      try {
        const res = await fetch("/api/admin/users");
        if (!res.ok) {
          setLoading(false);
          return;
        }
        const data = await res.json();
        setUsers(data);
      } catch {
        // Fetch failed
      }
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
