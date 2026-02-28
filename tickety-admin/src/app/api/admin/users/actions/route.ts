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

  const { action, user_id, reason } = await request.json();

  if (!action || !user_id) {
    return NextResponse.json({ error: "Missing action or user_id" }, { status: 400 });
  }

  const admin = createAdminClient();
  const ip = request.headers.get("x-forwarded-for") ?? undefined;

  switch (action) {
    case "suspend": {
      const { error } = await admin
        .from("profiles")
        .update({
          suspended_at: new Date().toISOString(),
          suspended_reason: reason ?? "Suspended by admin",
          suspended_by: session.user.id,
        })
        .eq("id", user_id);

      if (error) return NextResponse.json({ error: error.message }, { status: 500 });

      await writeAuditLog({
        admin_user_id: session.user.id,
        action: "user_suspend",
        target_table: "profiles",
        target_id: user_id,
        new_values: { suspended_reason: reason },
        ip_address: ip,
      });
      return NextResponse.json({ success: true });
    }

    case "unsuspend": {
      const { error } = await admin
        .from("profiles")
        .update({
          suspended_at: null,
          suspended_reason: null,
          suspended_by: null,
        })
        .eq("id", user_id);

      if (error) return NextResponse.json({ error: error.message }, { status: 500 });

      await writeAuditLog({
        admin_user_id: session.user.id,
        action: "user_unsuspend",
        target_table: "profiles",
        target_id: user_id,
        ip_address: ip,
      });
      return NextResponse.json({ success: true });
    }

    case "verify_email": {
      // Use Supabase admin API to update user email confirmation
      const { error } = await admin.auth.admin.updateUserById(user_id, {
        email_confirm: true,
      });

      if (error) return NextResponse.json({ error: error.message }, { status: 500 });

      await writeAuditLog({
        admin_user_id: session.user.id,
        action: "user_verify_email",
        target_table: "auth.users",
        target_id: user_id,
        ip_address: ip,
      });
      return NextResponse.json({ success: true });
    }

    case "reset_password": {
      // Get user email first
      const { data: profile } = await admin
        .from("profiles")
        .select("email")
        .eq("id", user_id)
        .single();

      if (!profile?.email) {
        return NextResponse.json({ error: "User email not found" }, { status: 404 });
      }

      // Generate password reset link via admin API
      const { data, error } = await admin.auth.admin.generateLink({
        type: "recovery",
        email: profile.email,
      });

      if (error) return NextResponse.json({ error: error.message }, { status: 500 });

      await writeAuditLog({
        admin_user_id: session.user.id,
        action: "user_reset_password",
        target_table: "auth.users",
        target_id: user_id,
        ip_address: ip,
      });

      return NextResponse.json({
        success: true,
        // Return the action link so admin can share it if needed
        recovery_link: data.properties?.action_link,
      });
    }

    case "manual_verify": {
      const { error } = await admin
        .from("profiles")
        .update({
          identity_verification_status: "verified",
          identity_verified_at: new Date().toISOString(),
          payout_delay_days: 2,
        })
        .eq("id", user_id);

      if (error) return NextResponse.json({ error: error.message }, { status: 500 });

      // Also auto-approve any pending_review events by this user
      await admin
        .from("events")
        .update({
          status: "active",
          status_reason: "Auto-approved: organizer manually verified by admin",
        })
        .eq("organizer_id", user_id)
        .eq("status", "pending_review");

      await writeAuditLog({
        admin_user_id: session.user.id,
        action: "user_manual_verify",
        target_table: "profiles",
        target_id: user_id,
        ip_address: ip,
      });
      return NextResponse.json({ success: true });
    }

    default:
      return NextResponse.json({ error: "Unknown action" }, { status: 400 });
  }
}
