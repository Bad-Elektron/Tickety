"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { Badge } from "@/components/ui/badge";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { formatDate } from "@/lib/utils/format";
import type { Profile } from "@/types/database";

interface UserRow extends Profile {
  subscription_tier?: string;
}

export const userColumns: ColumnDef<UserRow>[] = [
  {
    accessorKey: "display_name",
    header: "User",
    cell: ({ row }) => {
      const name = row.original.display_name ?? "Unknown";
      const initials = name
        .split(" ")
        .map((n) => n[0])
        .join("")
        .slice(0, 2)
        .toUpperCase();
      return (
        <div className="flex items-center gap-3">
          <Avatar className="h-8 w-8 bg-zinc-700">
            <AvatarFallback className="bg-zinc-700 text-xs text-zinc-300">
              {initials || "?"}
            </AvatarFallback>
          </Avatar>
          <div>
            <p className="font-medium text-white">{name}</p>
            <p className="text-xs text-zinc-500">{row.original.handle}</p>
          </div>
        </div>
      );
    },
  },
  {
    accessorKey: "email",
    header: "Email",
  },
  {
    accessorKey: "subscription_tier",
    header: "Tier",
    cell: ({ getValue }) => {
      const tier = (getValue() as string) ?? "base";
      const colors: Record<string, string> = {
        base: "border-zinc-600 text-zinc-400",
        pro: "border-indigo-500/30 text-indigo-400",
        enterprise: "border-amber-500/30 text-amber-400",
      };
      return (
        <Badge variant="outline" className={colors[tier] ?? colors.base}>
          {tier}
        </Badge>
      );
    },
  },
  {
    accessorKey: "referral_code",
    header: "Referral Code",
  },
  {
    accessorKey: "referred_at",
    header: "Joined",
    cell: ({ getValue }) => {
      const val = getValue() as string | null;
      return val ? formatDate(val) : "-";
    },
  },
];
