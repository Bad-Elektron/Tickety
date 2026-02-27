import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { writeAuditLog } from "@/lib/utils/audit";

export async function POST(request: NextRequest) {
  const serverClient = await createServerSupabaseClient();
  const {
    data: { session },
  } = await serverClient.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json();
  const { payment_id } = body;

  if (!payment_id) {
    return NextResponse.json(
      { error: "Missing payment_id" },
      { status: 400 }
    );
  }

  const admin = createAdminClient();

  // Get the payment
  const { data: payment, error: fetchError } = await admin
    .from("payments")
    .select("*")
    .eq("id", payment_id)
    .single();

  if (fetchError || !payment) {
    return NextResponse.json({ error: "Payment not found" }, { status: 404 });
  }

  if (payment.status === "refunded") {
    return NextResponse.json(
      { error: "Payment already refunded" },
      { status: 400 }
    );
  }

  if (!payment.stripe_payment_intent_id) {
    return NextResponse.json(
      { error: "No Stripe payment intent to refund" },
      { status: 400 }
    );
  }

  // Call the existing process-refund Edge Function
  const { data: refundResult, error: refundError } =
    await admin.functions.invoke("process-refund", {
      body: {
        payment_intent_id: payment.stripe_payment_intent_id,
        payment_id: payment.id,
      },
    });

  if (refundError) {
    return NextResponse.json(
      { error: refundError.message ?? "Refund failed" },
      { status: 500 }
    );
  }

  await writeAuditLog({
    admin_user_id: session.user.id,
    action: "payment_refund",
    target_table: "payments",
    target_id: payment_id,
    old_values: { status: payment.status },
    new_values: { status: "refunded" },
    details: { stripe_payment_intent_id: payment.stripe_payment_intent_id },
    ip_address: request.headers.get("x-forwarded-for") ?? undefined,
  });

  return NextResponse.json({ success: true, refund: refundResult });
}
