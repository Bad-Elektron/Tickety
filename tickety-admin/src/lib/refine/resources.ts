import type { ResourceProps } from "@refinedev/core";

export const resources: ResourceProps[] = [
  {
    name: "overview",
    list: "/dashboard/overview",
    meta: { label: "Overview" },
  },
  {
    name: "profiles",
    list: "/dashboard/users",
    show: "/dashboard/users/:id",
    meta: { label: "Users" },
  },
  {
    name: "events",
    list: "/dashboard/events",
    show: "/dashboard/events/:id",
    meta: { label: "Events" },
  },
  {
    name: "tickets",
    list: "/dashboard/tickets",
    meta: { label: "Tickets" },
  },
  {
    name: "payments",
    list: "/dashboard/payments",
    meta: { label: "Payments" },
  },
  {
    name: "subscriptions",
    list: "/dashboard/subscriptions",
    meta: { label: "Subscriptions" },
  },
  {
    name: "resale_listings",
    list: "/dashboard/resale",
    meta: { label: "Resale" },
  },
  {
    name: "referral_earnings",
    list: "/dashboard/referrals",
    meta: { label: "Referrals" },
  },
  {
    name: "admin_audit_log",
    list: "/dashboard/audit-log",
    meta: { label: "Audit Log" },
  },
  {
    name: "webhook_events",
    list: "/dashboard/webhooks",
    meta: { label: "Webhooks" },
  },
  {
    name: "edge_functions",
    list: "/dashboard/edge-functions",
    meta: { label: "Edge Functions" },
  },
  {
    name: "feature_flags",
    list: "/dashboard/feature-flags",
    meta: { label: "Feature Flags" },
  },
  {
    name: "admin_announcements",
    list: "/dashboard/announcements",
    meta: { label: "Announcements" },
  },
];
