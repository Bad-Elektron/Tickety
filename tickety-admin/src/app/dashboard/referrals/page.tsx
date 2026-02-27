"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { DataTable } from "@/components/tables/data-table";
import { referralColumns } from "@/components/tables/columns/referrals";
import type { ReferralEarning } from "@/types/database";
import { Skeleton } from "@/components/ui/skeleton";

interface ReferralRow extends ReferralEarning {
  referrer_email?: string;
  referred_email?: string;
}

export default function ReferralsPage() {
  const [referrals, setReferrals] = useState<ReferralRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchReferrals() {
      const supabase = createClient();
      const { data } = await supabase
        .from("referral_earnings")
        .select(
          "*, referrer:profiles!referral_earnings_referrer_id_fkey(email), referred:profiles!referral_earnings_referred_user_id_fkey(email)"
        )
        .order("created_at", { ascending: false })
        .limit(500);

      if (!data) {
        setLoading(false);
        return;
      }

      const rows: ReferralRow[] = data.map((r) => ({
        ...r,
        referrer_email: (r.referrer as unknown as { email: string })?.email,
        referred_email: (r.referred as unknown as { email: string })?.email,
        referrer: undefined,
        referred: undefined,
      }));

      setReferrals(rows);
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
