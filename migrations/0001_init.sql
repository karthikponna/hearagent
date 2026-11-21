-- Hear Agent: Supabase schema.
-- Paste into Supabase Dashboard → SQL Editor → New query, then Run. Safe to run once on a new project.
--
-- Who touches what:
--   * The Mac app signs in with Supabase Auth (Google / Apple) and only ever reads its own rows.
--   * The Cloudflare Worker uses the secret (service_role) key to write subscriptions and spend credits.
--   * Dodo webhooks reach the Worker, never the database directly.

-- ─────────────────────────────────────────────────────────────────────────────
-- Profiles: one row per auth user, created automatically on first sign-in.
-- ─────────────────────────────────────────────────────────────────────────────
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null default '',
  full_name text not null default '',
  avatar_url text,
  created_at timestamptz not null default now()
);

create index profiles_email_idx on public.profiles (lower(email));

alter table public.profiles enable row level security;

create policy "Users read their own profile"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = id);

-- Trigger functions live in a schema the Data API doesn't expose.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Apple only shares the name on the first sign-in and Google can change the email; keep them current.
create function private.handle_user_updated()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set email = coalesce(new.email, email),
      full_name = coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), nullif(new.raw_user_meta_data ->> 'name', ''), full_name),
      avatar_url = coalesce(new.raw_user_meta_data ->> 'avatar_url', avatar_url)
  where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_updated
  after update of email, raw_user_meta_data on auth.users
  for each row execute function private.handle_user_updated();

-- ─────────────────────────────────────────────────────────────────────────────
-- Plans shown on the paywall. Prices here are for display; Dodo charges what the
-- product in Dodo says. Set dodo_product_id once you've created each product.
-- ─────────────────────────────────────────────────────────────────────────────
create table public.plans (
  id text primary key,
  name text not null,
  billing_interval text not null check (billing_interval in ('month', 'year', 'lifetime')),
  price_cents integer not null check (price_cents >= 0),
  -- 1 credit = 1 spoken character. Refilled every month on every plan, lifetime included.
  monthly_credits integer not null check (monthly_credits >= 0),
  dodo_product_id text unique,
  sort_order integer not null default 0,
  active boolean not null default true
);

alter table public.plans enable row level security;

create policy "Anyone can read active plans"
  on public.plans for select
  to anon, authenticated
  using (active);

-- Edit the prices to match your Dodo products before launch.
insert into public.plans (id, name, billing_interval, price_cents, monthly_credits, sort_order) values
  ('monthly',  'Monthly',  'month',     1900, 150000, 1),
  ('yearly',   'Yearly',   'year',     14900, 150000, 2),
  ('lifetime', 'Lifetime', 'lifetime', 29900, 150000, 3);

-- ─────────────────────────────────────────────────────────────────────────────
-- Subscriptions: one row per user. Written only by the Worker.
-- ─────────────────────────────────────────────────────────────────────────────
create table public.subscriptions (
  user_id uuid primary key references auth.users (id) on delete cascade,
  plan_id text not null references public.plans (id),
  -- Dodo's status: active, on_hold, cancelled, failed, expired. Lifetime purchases are 'active'.
  status text not null,
  dodo_subscription_id text unique,
  dodo_payment_id text unique,
  dodo_customer_id text,
  current_period_start timestamptz,
  -- Null for lifetime.
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  credits_total integer not null default 0,
  credits_used integer not null default 0 check (credits_used >= 0),
  -- When credits next refill. Moves forward one month at a time.
  credits_reset_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index subscriptions_plan_idx on public.subscriptions (plan_id);
create index subscriptions_customer_idx on public.subscriptions (dodo_customer_id);

alter table public.subscriptions enable row level security;

create policy "Users read their own subscription"
  on public.subscriptions for select
  to authenticated
  using ((select auth.uid()) = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Webhook ids already processed, so Dodo retries are applied once.
-- RLS on with no policies: only the service role can touch it.
-- ─────────────────────────────────────────────────────────────────────────────
create table public.webhook_events (
  id text primary key,
  type text not null default '',
  received_at timestamptz not null default now()
);

alter table public.webhook_events enable row level security;

-- ─────────────────────────────────────────────────────────────────────────────
-- Credits. Called by the Worker through RPC with the service role only.
-- ─────────────────────────────────────────────────────────────────────────────

-- Returns the user's subscription after applying any monthly refill that is due.
create function public.current_subscription(p_user_id uuid)
returns setof public.subscriptions
language plpgsql
set search_path = ''
as $$
declare
  s public.subscriptions;
begin
  select * into s from public.subscriptions where user_id = p_user_id for update;
  if not found then
    return;
  end if;
  if s.credits_reset_at is not null and s.credits_reset_at <= now() then
    while s.credits_reset_at <= now() loop
      s.credits_reset_at := s.credits_reset_at + interval '1 month';
    end loop;
    update public.subscriptions
    set credits_used = 0, credits_reset_at = s.credits_reset_at, updated_at = now()
    where user_id = p_user_id
    returning * into s;
  end if;
  return next s;
end;
$$;

-- Spends credits atomically. ok = false (and nothing spent) when not enough remain.
create function public.spend_credits(p_user_id uuid, p_amount integer)
returns table (ok boolean, credits_remaining integer, credits_total integer, credits_reset_at timestamptz)
language plpgsql
set search_path = ''
as $$
declare
  s public.subscriptions;
begin
  if p_amount < 0 then
    raise exception 'amount must not be negative';
  end if;
  select * into s from public.current_subscription(p_user_id);
  if s.user_id is null then
    return query select false, 0, 0, null::timestamptz;
    return;
  end if;
  if s.credits_used + p_amount > s.credits_total then
    return query select false, greatest(s.credits_total - s.credits_used, 0), s.credits_total, s.credits_reset_at;
    return;
  end if;
  update public.subscriptions
  set credits_used = credits_used + p_amount, updated_at = now()
  where user_id = p_user_id;
  return query select true, s.credits_total - s.credits_used - p_amount, s.credits_total, s.credits_reset_at;
end;
$$;

-- Gives credits back when a voice line fails after they were spent.
create function public.refund_credits(p_user_id uuid, p_amount integer)
returns void
language sql
set search_path = ''
as $$
  update public.subscriptions
  set credits_used = greatest(credits_used - greatest(p_amount, 0), 0), updated_at = now()
  where user_id = p_user_id;
$$;

-- Finds the user a Dodo webhook belongs to: our metadata first, then the subscription, then the email.
create function public.webhook_user(p_user_id uuid, p_subscription_id text, p_email text)
returns uuid
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select id from public.profiles where id = p_user_id),
    (select user_id from public.subscriptions where dodo_subscription_id = p_subscription_id),
    (select id from public.profiles where lower(email) = lower(p_email) order by created_at limit 1)
  );
$$;

revoke execute on function public.current_subscription(uuid) from public, anon, authenticated;
revoke execute on function public.spend_credits(uuid, integer) from public, anon, authenticated;
revoke execute on function public.refund_credits(uuid, integer) from public, anon, authenticated;
revoke execute on function public.webhook_user(uuid, text, text) from public, anon, authenticated;
grant execute on function public.current_subscription(uuid) to service_role;
grant execute on function public.spend_credits(uuid, integer) to service_role;
grant execute on function public.refund_credits(uuid, integer) to service_role;
grant execute on function public.webhook_user(uuid, text, text) to service_role;
