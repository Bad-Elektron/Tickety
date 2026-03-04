"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import {
  LayoutDashboard,
  Users,
  Calendar,
  Ticket,
  CreditCard,
  Crown,
  Repeat,
  Share2,
  FileText,
  Webhook,
  Zap,
  Flag,
  Megaphone,
  AlertTriangle,
  Activity,
} from "lucide-react";

const navItems = [
  { label: "Overview", href: "/dashboard/overview", icon: LayoutDashboard },
  { label: "Users", href: "/dashboard/users", icon: Users },
  { label: "Events", href: "/dashboard/events", icon: Calendar },
  { label: "Tickets", href: "/dashboard/tickets", icon: Ticket },
  { label: "Payments", href: "/dashboard/payments", icon: CreditCard },
  { label: "Subscriptions", href: "/dashboard/subscriptions", icon: Crown },
  { label: "Resale", href: "/dashboard/resale", icon: Repeat },
  { label: "Referrals", href: "/dashboard/referrals", icon: Share2 },
  { label: "Reports", href: "/dashboard/reports", icon: AlertTriangle },
  { label: "Engagement", href: "/dashboard/engagement", icon: Activity },
  { label: "Audit Log", href: "/dashboard/audit-log", icon: FileText },
  { label: "Webhooks", href: "/dashboard/webhooks", icon: Webhook },
  { label: "Edge Functions", href: "/dashboard/edge-functions", icon: Zap },
  { label: "Feature Flags", href: "/dashboard/feature-flags", icon: Flag },
  { label: "Announcements", href: "/dashboard/announcements", icon: Megaphone },
];

export function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="fixed left-0 top-0 z-30 flex h-screen w-64 flex-col border-r border-zinc-800 bg-zinc-950">
      <div className="flex h-16 items-center border-b border-zinc-800 px-6">
        <Link href="/dashboard/overview" className="flex items-center gap-2">
          <span className="text-xl font-bold text-white">Tickety</span>
          <span className="rounded bg-indigo-600 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-white">
            Admin
          </span>
        </Link>
      </div>
      <nav className="flex-1 space-y-1 px-3 py-4">
        {navItems.map((item) => {
          const isActive =
            pathname === item.href ||
            (item.href !== "/dashboard/overview" &&
              pathname.startsWith(item.href));
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                isActive
                  ? "bg-indigo-600/10 text-indigo-400"
                  : "text-zinc-400 hover:bg-zinc-800/50 hover:text-zinc-200"
              )}
            >
              <item.icon className="h-4 w-4" />
              {item.label}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}
