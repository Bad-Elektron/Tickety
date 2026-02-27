"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { DataTable } from "@/components/tables/data-table";
import { resaleColumns } from "@/components/tables/columns/resale";
import type { ResaleListing } from "@/types/database";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { type ColumnDef } from "@tanstack/react-table";
import { XCircle } from "lucide-react";

interface ResaleRow extends ResaleListing {
  seller_email?: string;
  event_title?: string;
  ticket_number?: string;
}

export default function ResalePage() {
  const [listings, setListings] = useState<ResaleRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [delistTarget, setDelistTarget] = useState<ResaleRow | null>(null);
  const [delisting, setDelisting] = useState(false);

  useEffect(() => {
    async function fetchListings() {
      const supabase = createClient();
      const { data } = await supabase
        .from("resale_listings")
        .select(
          "*, profiles!resale_listings_seller_id_fkey(email), tickets!resale_listings_ticket_id_fkey(ticket_number, events(title))"
        )
        .order("created_at", { ascending: false })
        .limit(500);

      if (!data) {
        setLoading(false);
        return;
      }

      const rows: ResaleRow[] = data.map((r) => {
        const ticket = r.tickets as unknown as {
          ticket_number: string;
          events: { title: string };
        };
        return {
          ...r,
          seller_email: (r.profiles as unknown as { email: string })?.email,
          ticket_number: ticket?.ticket_number,
          event_title: ticket?.events?.title,
          profiles: undefined,
          tickets: undefined,
        };
      });

      setListings(rows);
      setLoading(false);
    }
    fetchListings();
  }, []);

  const handleDelist = async () => {
    if (!delistTarget) return;
    setDelisting(true);
    try {
      const supabase = createClient();
      const { error } = await supabase
        .from("resale_listings")
        .update({ status: "cancelled" })
        .eq("id", delistTarget.id);

      if (!error) {
        setListings((prev) =>
          prev.map((l) =>
            l.id === delistTarget.id ? { ...l, status: "cancelled" } : l
          )
        );
      }
    } finally {
      setDelisting(false);
      setDelistTarget(null);
    }
  };

  const columnsWithAction: ColumnDef<ResaleRow>[] = [
    ...resaleColumns,
    {
      id: "actions",
      header: "",
      cell: ({ row }) => {
        if (row.original.status !== "active") return null;
        return (
          <Button
            variant="ghost"
            size="sm"
            onClick={(e) => {
              e.stopPropagation();
              setDelistTarget(row.original);
            }}
            className="text-red-400 hover:text-red-300"
          >
            <XCircle className="mr-1 h-3 w-3" />
            Delist
          </Button>
        );
      },
    },
  ] as ColumnDef<ResaleRow>[];

  if (loading) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-white">Resale Listings</h1>
        <Skeleton className="h-96 w-full bg-zinc-800" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-white">Resale Listings</h1>
      <DataTable
        columns={columnsWithAction}
        data={listings}
        searchKey="seller_email"
        searchPlaceholder="Search by seller email..."
        exportFilename="resale-listings"
      />

      <Dialog
        open={!!delistTarget}
        onOpenChange={(open) => !open && setDelistTarget(null)}
      >
        <DialogContent className="border-zinc-800 bg-zinc-900">
          <DialogHeader>
            <DialogTitle className="text-white">Confirm Delist</DialogTitle>
            <DialogDescription className="text-zinc-400">
              Remove listing for ticket {delistTarget?.ticket_number} by{" "}
              {delistTarget?.seller_email}?
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setDelistTarget(null)}
              className="border-zinc-700 text-zinc-300"
            >
              Cancel
            </Button>
            <Button
              onClick={handleDelist}
              disabled={delisting}
              className="bg-red-600 hover:bg-red-700"
            >
              {delisting ? "Delisting..." : "Confirm Delist"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
