"use client";

import { useEffect, useState } from "react";
import { DataTable } from "@/components/tables/data-table";
import { referralColumns } from "@/components/tables/columns/referrals";
import { Skeleton } from "@/components/ui/skeleton";

interface ReferralRow {
  id: string;
  referrer_email: string;
  referrer_name?: string;
  referred_email: string;
  referred_name?: string;
  referred_at: string;
  signed_up_at: string;
}

export default function ReferralsPage() {
  const [referrals, setReferrals] = useState<ReferralRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchReferrals() {
      try {
        const res = await fetch("/api/admin/referrals");
        if (!res.ok) {
          setLoading(false);
          return;
        }
        const data = await res.json();
        setReferrals(data);
      } catch {
        // Fetch failed
      }
      setLoading(false);
    }
    fetchReferrals();
  }, []);

  if (loading) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-white">Referrals</h1>
        <Skeleton className="h-96 w-full bg-zinc-800" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-white">Referrals</h1>
      <DataTable
        columns={referralColumns}
        data={referrals}
        searchKey="referrer_email"
        searchPlaceholder="Search by referrer email..."
        exportFilename="referrals"
      />
    </div>
  );
}
