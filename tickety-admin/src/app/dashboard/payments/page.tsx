"use client";

import { useEffect, useState } from "react";
import { DataTable } from "@/components/tables/data-table";
import { paymentColumns } from "@/components/tables/columns/payments";
import type { Payment } from "@/types/database";
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
import { Undo2 } from "lucide-react";

interface PaymentRow extends Payment {
  user_email?: string;
  event_title?: string;
}

export default function PaymentsPage() {
  const [payments, setPayments] = useState<PaymentRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [refundTarget, setRefundTarget] = useState<PaymentRow | null>(null);
  const [refunding, setRefunding] = useState(false);

  useEffect(() => {
    async function fetchPayments() {
      try {
        const res = await fetch("/api/admin/payments");
        if (!res.ok) {
          setLoading(false);
          return;
        }
        const data = await res.json();
        setPayments(data);
      } catch {
        // Fetch failed
      }
      setLoading(false);
    }
    fetchPayments();
  }, []);

  const handleRefund = async () => {
    if (!refundTarget) return;
    setRefunding(true);
    try {
      const res = await fetch("/api/admin/payments/refund", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ payment_id: refundTarget.id }),
      });
      if (res.ok) {
        setPayments((prev) =>
          prev.map((p) =>
            p.id === refundTarget.id ? { ...p, status: "refunded" } : p
          )
        );
      }
    } finally {
      setRefunding(false);
      setRefundTarget(null);
    }
  };

  // Add refund action column
  const columnsWithAction: ColumnDef<PaymentRow>[] = [
    ...paymentColumns,
    {
      id: "actions",
      header: "",
      cell: ({ row }) => {
        const payment = row.original;
        if (
          payment.status !== "completed" ||
          !payment.stripe_payment_intent_id
        )
          return null;
        return (
          <Button
            variant="ghost"
            size="sm"
            onClick={(e) => {
              e.stopPropagation();
              setRefundTarget(payment);
            }}
            className="text-red-400 hover:text-red-300"
          >
            <Undo2 className="mr-1 h-3 w-3" />
            Refund
          </Button>
        );
      },
    },
  ] as ColumnDef<PaymentRow>[];

  if (loading) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-white">Payments</h1>
        <Skeleton className="h-96 w-full bg-zinc-800" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-white">Payments</h1>
      <DataTable
        columns={columnsWithAction}
        data={payments}
        searchKey="user_email"
        searchPlaceholder="Search by user email..."
        exportFilename="payments"
      />

      <Dialog
        open={!!refundTarget}
        onOpenChange={(open) => !open && setRefundTarget(null)}
      >
        <DialogContent className="border-zinc-800 bg-zinc-900">
          <DialogHeader>
            <DialogTitle className="text-white">Confirm Refund</DialogTitle>
            <DialogDescription className="text-zinc-400">
              Refund payment of{" "}
              <strong>
                ${((refundTarget?.amount_cents ?? 0) / 100).toFixed(2)}
              </strong>{" "}
              for {refundTarget?.user_email}? This action cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setRefundTarget(null)}
              className="border-zinc-700 text-zinc-300"
            >
              Cancel
            </Button>
            <Button
              onClick={handleRefund}
              disabled={refunding}
              className="bg-red-600 hover:bg-red-700"
            >
              {refunding ? "Refunding..." : "Confirm Refund"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
