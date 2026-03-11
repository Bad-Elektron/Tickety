export type AppRole = "admin" | "moderator" | "support";

export interface Profile {
  id: string;
  display_name: string | null;
  email: string | null;
  stripe_customer_id: string | null;
  stripe_connect_account_id: string | null;
  stripe_connect_onboarded: boolean;
  referral_code: string | null;
  referred_by: string | null;
  referred_at: string | null;
  handle: string | null;
}

export interface Event {
  id: string;
  organizer_id: string;
  title: string;
  subtitle: string | null;
  description: string | null;
  date: string;
  location: string | null;
  venue: string | null;
  city: string | null;
  country: string | null;
  imageUrl: string | null;
  noiseSeed: number | null;
  category: string | null;
  tags: string[] | null;
  priceInCents: number | null;
  currency: string;
  hide_location: boolean;
  max_tickets: number | null;
  cash_sales_enabled: boolean;
  status: "active" | "pending_review" | "suspended" | null;
  status_reason: string | null;
  nft_enabled: boolean;
  nft_policy_id: string | null;
  deleted_at: string | null;
  // Joined fields
  organizer?: Profile;
}

export interface EventTicketType {
  id: string;
  event_id: string;
  name: string;
  description: string | null;
  price_cents: number;
  currency: string;
  max_quantity: number | null;
  sold_count: number;
  sort_order: number;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Ticket {
  id: string;
  event_id: string;
  ticket_number: string;
  owner_email: string | null;
  owner_name: string | null;
  owner_wallet_address: string | null;
  ticket_type_id: string | null;
  price_paid_cents: number;
  currency: string;
  status: "valid" | "used" | "cancelled" | "refunded";
  ticket_mode: "standard" | "private" | "public";
  offer_id: string | null;
  sold_by: string | null;
  sold_at: string;
  checked_in_at: string | null;
  checked_in_by: string | null;
  payment_method: string;
  delivery_method: string | null;
  listing_status: string;
  listing_price_cents: number | null;
  metadata: Record<string, unknown> | null;
  // Joined fields
  event?: Event;
  ticket_type?: EventTicketType;
}

export interface Payment {
  id: string;
  user_id: string;
  ticket_id: string | null;
  event_id: string;
  amount_cents: number;
  platform_fee_cents: number;
  currency: string;
  status: "pending" | "processing" | "completed" | "failed" | "refunded";
  type: string;
  stripe_payment_intent_id: string | null;
  stripe_charge_id: string | null;
  receipt_url: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
  updated_at: string;
  // Joined fields
  user?: Profile;
  event?: Event;
}

export interface Subscription {
  id: string;
  user_id: string;
  tier: "base" | "pro" | "enterprise";
  status: "active" | "canceled" | "past_due" | "trialing" | "paused";
  stripe_subscription_id: string | null;
  stripe_price_id: string | null;
  current_period_start: string | null;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  created_at: string;
  updated_at: string;
  // Joined fields
  user?: Profile;
}

export interface ResaleListing {
  id: string;
  ticket_id: string;
  seller_id: string;
  price_cents: number;
  currency: string;
  status: "active" | "sold" | "cancelled";
  sold_by: string | null;
  created_at: string;
  updated_at: string;
  // Joined fields
  ticket?: Ticket;
  seller?: Profile;
}

export interface SellerBalance {
  id: string;
  user_id: string;
  stripe_account_id: string;
  available_balance_cents: number;
  pending_balance_cents: number;
  currency: string;
  payouts_enabled: boolean;
  details_submitted: boolean;
  last_synced_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface CashTransaction {
  id: string;
  event_id: string;
  seller_id: string;
  ticket_id: string;
  amount_cents: number;
  platform_fee_cents: number;
  currency: string;
  status: "pending" | "collected" | "disputed";
  fee_charged: boolean;
  customer_name: string | null;
  customer_email: string | null;
  delivery_method: string | null;
  created_at: string;
  updated_at: string;
  reconciled_at: string | null;
  reconciled_by: string | null;
}

export interface UserRole {
  id: string;
  user_id: string;
  role: AppRole;
  granted_by: string | null;
  granted_at: string;
}

export interface AuditLog {
  id: string;
  admin_user_id: string;
  action: string;
  target_table: string | null;
  target_id: string | null;
  old_values: Record<string, unknown> | null;
  new_values: Record<string, unknown> | null;
  details: Record<string, unknown> | null;
  ip_address: string | null;
  created_at: string;
  // Joined fields
  admin?: Profile;
}

export interface TicketOffer {
  id: string;
  event_id: string;
  organizer_id: string;
  recipient_email: string;
  recipient_user_id: string | null;
  price_cents: number;
  currency: string;
  ticket_mode: "private" | "public";
  message: string | null;
  status: "pending" | "accepted" | "declined" | "cancelled" | "expired";
  ticket_id: string | null;
  ticket_type_id: string | null;
  expires_at: string;
  created_at: string;
  updated_at: string;
}

export interface ReferralEarning {
  id: string;
  referrer_id: string;
  referred_user_id: string;
  payment_id: string | null;
  platform_fee_cents: number;
  discount_cents: number;
  earning_cents: number;
  discount_percent_applied: number;
  revenue_share_percent_applied: number;
  status: "pending" | "paid" | "cancelled";
  created_at: string;
  // Joined
  referrer?: Profile;
  referred_user?: Profile;
}

export interface ReferralConfig {
  id: number;
  referee_discount_percent: number;
  referrer_revenue_share_percent: number;
  benefit_duration_days: number;
  referral_enabled: boolean;
  updated_at: string;
}

export interface Notification {
  id: string;
  user_id: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  read: boolean;
  created_at: string;
}

export interface EventStaff {
  id: string;
  event_id: string;
  user_id: string;
  role: string;
  invited_email: string | null;
  accepted_at: string | null;
  created_at: string;
}

export interface FeatureFlag {
  id: string;
  key: string;
  enabled: boolean;
  description: string | null;
  updated_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface AdminAnnouncement {
  id: string;
  author_id: string;
  title: string;
  body: string;
  audience: "all" | "organizers" | "subscribers";
  severity: "info" | "warning" | "critical" | "success";
  sent_count: number;
  created_at: string;
  // Joined
  author?: Profile;
}
