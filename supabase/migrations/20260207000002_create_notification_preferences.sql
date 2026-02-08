-- Create notification_preferences table for per-user notification settings.
-- Uses upsert pattern: clients INSERT ON CONFLICT to auto-create default rows.

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  push_enabled boolean not null default true,
  email_enabled boolean not null default true,
  staff_added boolean not null default true,
  ticket_purchased boolean not null default true,
  ticket_used boolean not null default true,
  event_reminders boolean not null default true,
  event_updates boolean not null default true,
  marketing boolean not null default false,
  updated_at timestamptz not null default now()
);

-- Enable RLS
alter table public.notification_preferences enable row level security;

-- Users can read their own preferences
create policy "Users can read own notification preferences"
  on public.notification_preferences
  for select
  using (auth.uid() = user_id);

-- Users can insert their own preferences (for upsert on first access)
create policy "Users can insert own notification preferences"
  on public.notification_preferences
  for insert
  with check (auth.uid() = user_id);

-- Users can update their own preferences
create policy "Users can update own notification preferences"
  on public.notification_preferences
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Auto-update updated_at on changes
create or replace function public.update_notification_preferences_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger set_notification_preferences_updated_at
  before update on public.notification_preferences
  for each row
  execute function public.update_notification_preferences_updated_at();
