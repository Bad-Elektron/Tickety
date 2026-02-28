"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { formatDate } from "@/lib/utils/format";

interface ReferralRow {
  id: string;
  referrer_email: string;
  referrer_name?: string;
  referred_email: string;
  referred_name?: string;
  referred_at: string;
  signed_up_at: string;
}

export const referralColumns: ColumnDef<ReferralRow>[] = [
  {
    accessorKey: "referrer_email",
    header: "Referrer",
    cell: ({ row }) => {
      const name = row.original.referrer_name;
      const email = row.original.referrer_email;
      return (
        <div>
          <span className="text-zinc-200">{name ?? email}</span>
          {name && (
            <span className="ml-2 text-xs text-zinc-500">{email}</span>
          )}
        </div>
      );
    },
  },
  {
    accessorKey: "referred_email",
    header: "Referred User",
    cell: ({ row }) => {
      const name = row.original.referred_name;
      const email = row.original.referred_email;
      return (
        <div>
          <span className="text-zinc-200">{name ?? email}</span>
          {name && (
            <span className="ml-2 text-xs text-zinc-500">{email}</span>
          )}
        </div>
      );
    },
  },
  {
    accessorKey: "referred_at",
    header: "Referred At",
    cell: ({ getValue }) => formatDate(getValue() as string),
  },
  {
    accessorKey: "signed_up_at",
    header: "Signed Up",
    cell: ({ getValue }) => formatDate(getValue() as string),
  },
];
