"use client";

import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import type { LucideIcon } from "lucide-react";

interface KpiCardProps {
  label: string;
  value: string;
  delta?: string;
  deltaType?: "positive" | "negative" | "neutral";
  icon: LucideIcon;
  loading?: boolean;
}

export function KpiCard({
  label,
  value,
  delta,
  deltaType = "neutral",
  icon: Icon,
  loading,
}: KpiCardProps) {
  if (loading) {
    return (
      <Card className="border-zinc-800 bg-zinc-900">
        <CardContent className="p-6">
          <Skeleton className="mb-2 h-4 w-24 bg-zinc-800" />
          <Skeleton className="h-8 w-32 bg-zinc-800" />
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="border-zinc-800 bg-zinc-900">
      <CardContent className="p-6">
        <div className="flex items-center justify-between">
          <p className="text-sm font-medium text-zinc-400">{label}</p>
          <Icon className="h-4 w-4 text-zinc-500" />
        </div>
        <div className="mt-2 flex items-baseline gap-2">
          <p className="text-2xl font-bold text-white">{value}</p>
          {delta && (
            <span
              className={cn(
                "text-xs font-medium",
                deltaType === "positive" && "text-emerald-400",
                deltaType === "negative" && "text-red-400",
                deltaType === "neutral" && "text-zinc-400"
              )}
            >
              {delta}
            </span>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
