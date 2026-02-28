"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Separator } from "@/components/ui/separator";
import { DataTable } from "@/components/tables/data-table";
import { paymentColumns } from "@/components/tables/columns/payments";
import { formatCents, formatDate, formatDateTime, formatRelative } from "@/lib/utils/format";
import type { Profile, Subscription, Payment, Event, Ticket } from "@/types/database";
import {
  ArrowLeft,
  Save,
  Ban,
  ShieldCheck,
  KeyRound,
  MailCheck,
  CreditCard,
  Ticket as TicketIcon,
  Calendar,
  Repeat,
  Crown,
  UserCheck,
  LogIn,
} from "lucide-react";
import Link from "next/link";

interface UserDetail {
  profile: Profile & {
    suspended_at?: string | null;
    suspended_reason?: string | null;
    identity_verification_status?: string | null;
    identity_verified_at?: string | null;
    payout_delay_days?: number | null;
  };
  subscription: Subscription | null;
  payments: (Payment & { user_email?: string; event_title?: string })[];
  events: Event[];
  tickets: Ticket[];
  referredBy: Profile | null;
  referrals: Profile[];
}

interface TimelineEvent {
  type: string;
  title: string;
  detail: string;
  timestamp: string;
}

export default function UserDetailPage() {
  const params = useParams();
  const userId = params.id as string;
  const [data, setData] = useState<UserDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [newTier, setNewTier] = useState<string>("");
  const [saving, setSaving] = useState(false);
  const [timeline, setTimeline] = useState<TimelineEvent[]>([]);
  const [timelineLoading, setTimelineLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [suspendOpen, setSuspendOpen] = useState(false);
  const [suspendReason, setSuspendReason] = useState("");
  const [recoveryLink, setRecoveryLink] = useState<string | null>(null);

  useEffect(() => {
    async function fetchUser() {
      try {
        const res = await fetch(`/api/admin/users/${userId}`);
        if (!res.ok) {
          setLoading(false);
          return;
        }
        const json = await res.json();
        setData(json);
        setNewTier(json.subscription?.tier ?? "base");
      } catch {
        // Fetch failed
      }
      setLoading(false);
    }
    fetchUser();
  }, [userId]);

  // Fetch timeline
  useEffect(() => {
    fetch(`/api/admin/users/${userId}/timeline`)
      .then((res) => res.json())
      .then((data) => {
        if (Array.isArray(data)) setTimeline(data);
      })
      .finally(() => setTimelineLoading(false));
  }, [userId]);

  const handleTierChange = async () => {
    if (!newTier || newTier === data?.subscription?.tier) return;
    setSaving(true);
    try {
      const res = await fetch("/api/admin/subscriptions/override", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: userId, new_tier: newTier }),
      });
      if (res.ok) {
        setData((prev) =>
          prev
            ? {
                ...prev,
                subscription: prev.subscription
                  ? { ...prev.subscription, tier: newTier as Subscription["tier"] }
                  : null,
              }
            : prev
        );
      }
    } finally {
      setSaving(false);
    }
  };

  const handleAction = async (action: string, reason?: string) => {
    setActionLoading(action);
    try {
      const res = await fetch("/api/admin/users/actions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, user_id: userId, reason }),
      });
      const result = await res.json();

      if (res.ok) {
        if (action === "manual_verify") {
          setData((prev) =>
            prev
              ? {
                  ...prev,
                  profile: {
                    ...prev.profile,
                    identity_verification_status: "verified",
                    identity_verified_at: new Date().toISOString(),
                    payout_delay_days: 2,
                  },
                }
              : prev
          );
        } else if (action === "suspend") {
          setData((prev) =>
            prev
              ? {
                  ...prev,
                  profile: {
                    ...prev.profile,
                    suspended_at: new Date().toISOString(),
                    suspended_reason: reason ?? "Suspended by admin",
                  },
                }
              : prev
          );
          setSuspendOpen(false);
        } else if (action === "unsuspend") {
          setData((prev) =>
            prev
              ? {
                  ...prev,
                  profile: {
                    ...prev.profile,
                    suspended_at: null,
                    suspended_reason: null,
                  },
                }
              : prev
          );
        } else if (action === "reset_password" && result.recovery_link) {
          setRecoveryLink(result.recovery_link);
        }
      }
    } finally {
      setActionLoading(null);
    }
  };

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-48 bg-zinc-800" />
        <Skeleton className="h-64 w-full bg-zinc-800" />
      </div>
    );
  }

  if (!data) {
    return <p className="text-zinc-400">User not found.</p>;
  }

  const { profile, subscription, payments, events, tickets, referredBy, referrals } = data;
  const isSuspended = !!profile.suspended_at;

  const timelineIcons: Record<string, typeof CreditCard> = {
    payment: CreditCard,
    ticket: TicketIcon,
    checkin: LogIn,
    event_created: Calendar,
    resale: Repeat,
    subscription: Crown,
    signup: UserCheck,
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Link href="/dashboard/users">
          <Button variant="ghost" size="sm" className="text-zinc-400">
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back
          </Button>
        </Link>
        <h1 className="text-2xl font-bold text-white">
          {profile.display_name ?? profile.email}
        </h1>
        {isSuspended && (
          <Badge variant="outline" className="border-red-500/30 text-red-400">
            Suspended
          </Badge>
        )}
      </div>

      {/* Account Actions */}
      <Card className="border-zinc-800 bg-zinc-900">
        <CardHeader>
          <CardTitle className="text-sm text-zinc-400">Account Actions</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          {isSuspended ? (
            <Button
              size="sm"
              variant="outline"
              onClick={() => handleAction("unsuspend")}
              disabled={actionLoading === "unsuspend"}
              className="border-emerald-500/30 text-emerald-400 hover:bg-emerald-950/30"
            >
              <ShieldCheck className="mr-2 h-3 w-3" />
              {actionLoading === "unsuspend" ? "..." : "Unsuspend"}
            </Button>
          ) : (
            <Button
              size="sm"
              variant="outline"
              onClick={() => setSuspendOpen(true)}
              className="border-red-500/30 text-red-400 hover:bg-red-950/30"
            >
              <Ban className="mr-2 h-3 w-3" />
              Suspend
            </Button>
          )}
          <Button
            size="sm"
            variant="outline"
            onClick={() => handleAction("verify_email")}
            disabled={actionLoading === "verify_email"}
            className="border-zinc-700 text-zinc-300 hover:bg-zinc-800"
          >
            <MailCheck className="mr-2 h-3 w-3" />
            {actionLoading === "verify_email" ? "..." : "Verify Email"}
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => handleAction("reset_password")}
            disabled={actionLoading === "reset_password"}
            className="border-zinc-700 text-zinc-300 hover:bg-zinc-800"
          >
            <KeyRound className="mr-2 h-3 w-3" />
            {actionLoading === "reset_password" ? "..." : "Reset Password"}
          </Button>
        </CardContent>
        {isSuspended && profile.suspended_reason && (
          <CardContent className="-mt-2">
            <p className="rounded bg-red-950/30 px-3 py-2 text-xs text-red-400">
              Reason: {profile.suspended_reason}
            </p>
          </CardContent>
        )}
        {recoveryLink && (
          <CardContent className="-mt-2">
            <p className="text-xs text-zinc-400">Recovery link generated:</p>
            <code className="mt-1 block break-all rounded bg-zinc-800 px-3 py-2 text-xs text-emerald-400">
              {recoveryLink}
            </code>
          </CardContent>
        )}
      </Card>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        {/* Profile Info */}
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm text-zinc-400">Profile</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <InfoRow label="ID" value={profile.id} mono />
            <InfoRow label="Email" value={profile.email} />
            <InfoRow label="Handle" value={profile.handle} />
            <InfoRow label="Display Name" value={profile.display_name} />
            <InfoRow label="Referral Code" value={profile.referral_code} />
            <InfoRow label="Stripe Customer" value={profile.stripe_customer_id} mono />
            <InfoRow label="Stripe Connect" value={profile.stripe_connect_account_id} mono />
            <Separator className="bg-zinc-800" />
            <InfoRow label="Verification">
              <Badge
                variant="outline"
                className={
                  profile.identity_verification_status === "verified"
                    ? "border-emerald-500/30 text-emerald-400"
                    : profile.identity_verification_status === "pending"
                      ? "border-amber-500/30 text-amber-400"
                      : profile.identity_verification_status === "failed"
                        ? "border-red-500/30 text-red-400"
                        : "border-zinc-600 text-zinc-400"
                }
              >
                {profile.identity_verification_status ?? "none"}
              </Badge>
            </InfoRow>
            {profile.identity_verified_at && (
              <InfoRow
                label="Verified At"
                value={formatDate(profile.identity_verified_at)}
              />
            )}
            <InfoRow
              label="Payout Delay"
              value={`${profile.payout_delay_days ?? 14} days`}
            />
            {profile.identity_verification_status !== "verified" && (
              <Button
                size="sm"
                variant="outline"
                onClick={() => handleAction("manual_verify")}
                disabled={actionLoading === "manual_verify"}
                className="mt-2 border-emerald-500/30 text-emerald-400 hover:bg-emerald-950/30"
              >
                <ShieldCheck className="mr-2 h-3 w-3" />
                {actionLoading === "manual_verify" ? "..." : "Manually Verify"}
              </Button>
            )}
          </CardContent>
        </Card>

        {/* Subscription */}
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm text-zinc-400">Subscription</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {subscription ? (
              <>
                <InfoRow label="Tier">
                  <Badge
                    variant="outline"
                    className={
                      subscription.tier === "enterprise"
                        ? "border-amber-500/30 text-amber-400"
                        : subscription.tier === "pro"
                          ? "border-indigo-500/30 text-indigo-400"
                          : "border-zinc-600 text-zinc-400"
                    }
                  >
                    {subscription.tier}
                  </Badge>
                </InfoRow>
                <InfoRow label="Status">
                  <Badge
                    variant="outline"
                    className={
                      subscription.status === "active"
                        ? "border-emerald-500/30 text-emerald-400"
                        : "border-red-500/30 text-red-400"
                    }
                  >
                    {subscription.status}
                  </Badge>
                </InfoRow>
                <InfoRow
                  label="Period End"
                  value={
                    subscription.current_period_end
                      ? formatDate(subscription.current_period_end)
                      : null
                  }
                />
                <InfoRow label="Stripe Sub ID" value={subscription.stripe_subscription_id} mono />
                <Separator className="bg-zinc-800" />
                <div className="space-y-2">
                  <p className="text-xs text-zinc-500">Change Tier</p>
                  <div className="flex gap-2">
                    <Select value={newTier} onValueChange={setNewTier}>
                      <SelectTrigger className="border-zinc-700 bg-zinc-800 text-white">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent className="border-zinc-700 bg-zinc-800">
                        <SelectItem value="base">Base</SelectItem>
                        <SelectItem value="pro">Pro</SelectItem>
                        <SelectItem value="enterprise">Enterprise</SelectItem>
                      </SelectContent>
                    </Select>
                    <Button
                      size="sm"
                      onClick={handleTierChange}
                      disabled={saving || newTier === subscription.tier}
                      className="bg-indigo-600 hover:bg-indigo-700"
                    >
                      <Save className="mr-1 h-3 w-3" />
                      {saving ? "..." : "Save"}
                    </Button>
                  </div>
                </div>
              </>
            ) : (
              <p className="text-sm text-zinc-500">No subscription</p>
            )}
          </CardContent>
        </Card>

        {/* Referral Info */}
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm text-zinc-400">Referrals</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <InfoRow
              label="Referred By"
              value={referredBy ? `${referredBy.display_name ?? referredBy.email}` : null}
            />
            <InfoRow
              label="Referred At"
              value={profile.referred_at ? formatDate(profile.referred_at) : null}
            />
            <Separator className="bg-zinc-800" />
            <p className="text-xs text-zinc-500">Referred {referrals.length} user(s)</p>
            {referrals.slice(0, 5).map((r) => (
              <p key={r.id} className="text-sm text-zinc-300">
                {r.display_name ?? r.email}
              </p>
            ))}
            {referrals.length > 5 && (
              <p className="text-xs text-zinc-500">+{referrals.length - 5} more</p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Activity Timeline */}
      <Card className="border-zinc-800 bg-zinc-900">
        <CardHeader>
          <CardTitle className="text-sm text-zinc-400">Activity Timeline</CardTitle>
        </CardHeader>
        <CardContent>
          {timelineLoading ? (
            <div className="space-y-3">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-10 w-full bg-zinc-800" />
              ))}
            </div>
          ) : timeline.length === 0 ? (
            <p className="text-sm text-zinc-500">No activity yet.</p>
          ) : (
            <div className="relative space-y-0">
              <div className="absolute left-[15px] top-2 bottom-2 w-px bg-zinc-800" />
              {timeline.slice(0, 30).map((event, i) => {
                const Icon = timelineIcons[event.type] ?? UserCheck;
                return (
                  <div key={i} className="relative flex items-start gap-4 py-2 pl-1">
                    <div className="z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-zinc-800">
                      <Icon className="h-3.5 w-3.5 text-zinc-400" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="text-sm text-white">{event.title}</p>
                      {event.detail && (
                        <p className="truncate text-xs text-zinc-500">{event.detail}</p>
                      )}
                    </div>
                    <span className="shrink-0 text-xs text-zinc-600">
                      {formatRelative(event.timestamp)}
                    </span>
                  </div>
                );
              })}
              {timeline.length > 30 && (
                <p className="pl-12 text-xs text-zinc-500">
                  +{timeline.length - 30} more events
                </p>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Events organized */}
      {events.length > 0 && (
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm text-zinc-400">
              Events Organized ({events.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {events.map((e) => (
                <Link
                  key={e.id}
                  href={`/dashboard/events/${e.id}`}
                  className="flex items-center justify-between rounded-lg p-2 hover:bg-zinc-800/50"
                >
                  <span className="text-sm text-white">{e.title}</span>
                  <span className="text-xs text-zinc-500">{formatDate(e.date)}</span>
                </Link>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Tickets owned */}
      {tickets.length > 0 && (
        <Card className="border-zinc-800 bg-zinc-900">
          <CardHeader>
            <CardTitle className="text-sm text-zinc-400">Tickets ({tickets.length})</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {tickets.map((t) => (
                <div key={t.id} className="flex items-center justify-between rounded-lg p-2">
                  <span className="font-mono text-xs text-white">{t.ticket_number}</span>
                  <div className="flex items-center gap-2">
                    <Badge
                      variant="outline"
                      className={
                        t.status === "valid"
                          ? "border-emerald-500/30 text-emerald-400"
                          : "border-zinc-600 text-zinc-400"
                      }
                    >
                      {t.status}
                    </Badge>
                    <span className="text-xs text-zinc-500">
                      {formatCents(t.price_paid_cents)}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Payments */}
      {payments.length > 0 && (
        <div className="space-y-2">
          <h2 className="text-lg font-semibold text-white">Payment History</h2>
          <DataTable columns={paymentColumns} data={payments} exportFilename="user-payments" />
        </div>
      )}

      {/* Suspend Dialog */}
      <Dialog open={suspendOpen} onOpenChange={setSuspendOpen}>
        <DialogContent className="border-zinc-800 bg-zinc-900">
          <DialogHeader>
            <DialogTitle className="text-white">Suspend User</DialogTitle>
            <DialogDescription className="text-zinc-400">
              Suspend {profile.display_name ?? profile.email}? They will not be
              able to access the platform.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label className="text-zinc-300">Reason</Label>
            <Input
              value={suspendReason}
              onChange={(e) => setSuspendReason(e.target.value)}
              placeholder="Reason for suspension..."
              className="border-zinc-700 bg-zinc-800 text-white"
            />
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setSuspendOpen(false)}
              className="border-zinc-700 text-zinc-300"
            >
              Cancel
            </Button>
            <Button
              onClick={() => handleAction("suspend", suspendReason)}
              disabled={actionLoading === "suspend"}
              className="bg-red-600 hover:bg-red-700"
            >
              {actionLoading === "suspend" ? "Suspending..." : "Confirm Suspend"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function InfoRow({
  label,
  value,
  mono,
  children,
}: {
  label: string;
  value?: string | null;
  mono?: boolean;
  children?: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-xs text-zinc-500">{label}</span>
      {children ?? (
        <span
          className={`text-sm text-zinc-300 ${mono ? "font-mono text-xs" : ""} max-w-[180px] truncate`}
        >
          {value ?? "-"}
        </span>
      )}
    </div>
  );
}
