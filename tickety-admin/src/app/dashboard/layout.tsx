import { Suspense } from "react";
import { Sidebar } from "@/components/layout/sidebar";
import { Header } from "@/components/layout/header";

export const dynamic = "force-dynamic";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <Sidebar />
      <div className="pl-64">
        <Header />
        <main className="p-6">
          <Suspense fallback={<DashboardSkeleton />}>{children}</Suspense>
        </main>
      </div>
    </div>
  );
}

function DashboardSkeleton() {
  return (
    <div className="space-y-4">
      <div className="h-8 w-48 animate-pulse rounded bg-zinc-800" />
      <div className="h-96 w-full animate-pulse rounded bg-zinc-800" />
    </div>
  );
}
