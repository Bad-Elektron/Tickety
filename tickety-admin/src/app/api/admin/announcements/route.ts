import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { writeAuditLog } from "@/lib/utils/audit";

export async function GET() {
  const admin = createAdminClient();

  const { data, error } = await admin
    .from("admin_announcements")
    .select("*, author:profiles!admin_announcements_author_id_fkey(display_name, email)")
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json(data);
}

export async function POST(request: NextRequest) {
  const serverClient = await createServerSupabaseClient();
  const {
    data: { session },
  } = await serverClient.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { title, body, audience, severity } = await request.json();

  if (!title || !body) {
    return NextResponse.json(
      { error: "Missing title or body" },
      { status: 400 }
    );
  }

  const admin = createAdminClient();

  // Create the announcement
  const { data: announcement, error: announcementError } = await admin
    .from("admin_announcements")
    .insert({
      author_id: session.user.id,
      title,
      body,
      audience: audience ?? "all",
      severity: severity ?? "info",
    })
    .select()
    .single();

  if (announcementError) {
    return NextResponse.json(
      { error: announcementError.message },
      { status: 500 }
    );
  }

  // If broadcasting to users, create notifications for the target audience
  if (audience === "all" || audience === "organizers" || audience === "subscribers") {
    let query = admin.from("profiles").select("id");

    if (audience === "organizers") {
      // Users who have created at least one event
      const { data: organizerIds } = await admin
        .from("events")
        .select("organizer_id")
        .is("deleted_at", null);
      const uniqueIds = [...new Set(organizerIds?.map((e) => e.organizer_id) ?? [])];
      if (uniqueIds.length > 0) {
        query = query.in("id", uniqueIds);
      }
    } else if (audience === "subscribers") {
      // Users with active paid subscriptions
      const { data: subs } = await admin
        .from("subscriptions")
        .select("user_id")
        .eq("status", "active")
        .neq("tier", "base");
      const subIds = subs?.map((s) => s.user_id) ?? [];
      if (subIds.length > 0) {
        query = query.in("id", subIds);
      }
    }

    const { data: users } = await query;
    const userIds = users?.map((u) => u.id) ?? [];

    if (userIds.length > 0) {
      // Batch insert notifications (max 500 at a time)
      const batchSize = 500;
      let sent = 0;
      for (let i = 0; i < userIds.length; i += batchSize) {
        const batch = userIds.slice(i, i + batchSize);
        const notifications = batch.map((userId) => ({
          user_id: userId,
          type: "announcement",
          title,
          body,
          data: {
            announcement_id: announcement.id,
            severity,
          },
        }));
        const { error: notifError } = await admin
          .from("notifications")
          .insert(notifications);
        if (!notifError) sent += batch.length;
      }

      // Update sent count on announcement
      await admin
        .from("admin_announcements")
        .update({ sent_count: sent })
        .eq("id", announcement.id);
    }
  }

  await writeAuditLog({
    admin_user_id: session.user.id,
    action: "announcement_create",
    target_table: "admin_announcements",
    target_id: announcement.id,
    new_values: { title, audience, severity },
    ip_address: request.headers.get("x-forwarded-for") ?? undefined,
  });

  return NextResponse.json(announcement);
}
