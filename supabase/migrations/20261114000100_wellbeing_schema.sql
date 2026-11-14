-- Run once against Supabase. Atomic; existing wb_* objects cause a safe failure.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create table public.wb_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  birth_year smallint check (birth_year between 1900 and 2100),
  gender text,
  country_code text check (country_code ~ '^[A-Z]{2}$'),
  timezone text not null default 'UTC',
  created_at timestamptz not null default now()
);

-- Append-only audit of choices, accepted by a trusted authenticated backend.
-- Highest id is the current decision for each (user_id, scope).
create table public.wb_consent_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  scope text not null check (scope in ('wearables','location','app_usage','social_feed','analysis','notifications')),
  granted boolean not null,
  policy_version text not null,
  recorded_at timestamptz not null default now()
);
create index on public.wb_consent_events(user_id, scope, id desc);

create table public.wb_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  provider text not null,
  external_account_id text not null,
  device_label text,
  device_timezone text,
  last_synced_at timestamptz,
  disconnected_at timestamptz,
  created_at timestamptz not null default now(),
  unique(user_id, id),
  unique(user_id, provider, external_account_id)
);

create table public.wb_metric_types (
  code text primary key,
  unit text not null,
  description text not null,
  aggregation text not null check (aggregation in ('sum','mean','latest'))
);
insert into public.wb_metric_types values
 ('steps','count','Steps during the interval','sum'),
 ('active_energy','kcal','Active energy expenditure during the interval','sum'),
 ('heart_rate','bpm','Heart rate sample or interval average','mean'),
 ('resting_heart_rate','bpm','Provider resting heart rate estimate','mean'),
 ('hrv_rmssd','ms','Heart rate variability RMSSD; keep separate from SDNN','mean'),
 ('hrv_sdnn','ms','Heart rate variability SDNN','mean'),
 ('respiratory_rate','breaths/min','Respiratory rate','mean'),
 ('oxygen_saturation','percent','Blood oxygen saturation, 0 to 100','mean'),
 ('skin_temperature','degC','Absolute skin temperature','mean'),
 ('skin_temperature_deviation','degC','Deviation from provider baseline','mean');

create table public.wb_wearable_observations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  source_id uuid not null,
  external_id text not null,
  metric_code text not null references public.wb_metric_types(code),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  value double precision not null check (value > '-Infinity'::float8 and value < 'Infinity'::float8),
  quality text not null default 'unknown' check (quality in ('unknown','valid','suspect')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  ingested_at timestamptz not null default now(),
  check (ended_at >= started_at),
  foreign key(user_id, source_id) references public.wb_sources(user_id,id),
  unique(user_id, source_id, external_id, metric_code)
);
create index on public.wb_wearable_observations(user_id, metric_code, started_at desc);
create index on public.wb_wearable_observations(user_id, source_id);

create table public.wb_sleep_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  source_id uuid not null,
  external_id text not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  asleep_seconds integer not null check (asleep_seconds >= 0),
  awake_seconds integer check (awake_seconds >= 0),
  deep_seconds integer check (deep_seconds >= 0),
  rem_seconds integer check (rem_seconds >= 0),
  light_seconds integer check (light_seconds >= 0),
  ingested_at timestamptz not null default now(),
  check (ended_at > started_at),
  check (asleep_seconds <= extract(epoch from ended_at-started_at)),
  check (coalesce(awake_seconds,0) + asleep_seconds <= extract(epoch from ended_at-started_at)),
  check (coalesce(deep_seconds,0) + coalesce(rem_seconds,0) + coalesce(light_seconds,0) <= asleep_seconds),
  foreign key(user_id, source_id) references public.wb_sources(user_id,id),
  unique(user_id, source_id, external_id)
);
create index on public.wb_sleep_sessions(user_id, started_at desc);
create index on public.wb_sleep_sessions(user_id, source_id);

create table public.wb_location_samples (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  source_id uuid not null,
  external_id text not null,
  observed_at timestamptz not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_m double precision check (accuracy_m >= 0 and accuracy_m < 'Infinity'::float8),
  ingested_at timestamptz not null default now(),
  foreign key(user_id, source_id) references public.wb_sources(user_id,id),
  unique(user_id, source_id, external_id)
);
create index on public.wb_location_samples(user_id, observed_at desc);
create index on public.wb_location_samples(user_id, source_id);

create table public.wb_app_usage_intervals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  source_id uuid not null,
  external_id text not null,
  app_identifier text not null,
  platform text not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  foreground_seconds integer not null check (foreground_seconds >= 0),
  opens integer check (opens >= 0),
  ingested_at timestamptz not null default now(),
  check (ended_at > started_at),
  check (foreground_seconds <= extract(epoch from ended_at-started_at)),
  foreign key(user_id, source_id) references public.wb_sources(user_id,id),
  unique(user_id, source_id, external_id)
);
create index on public.wb_app_usage_intervals(user_id, started_at desc);
create index on public.wb_app_usage_intervals(user_id, source_id);

-- Observed exposure, not access to a platform's internal recommendation model.
create table public.wb_social_exposures (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  source_id uuid not null,
  external_id text not null,
  platform text not null,
  observed_at timestamptz not null,
  content_reference text,
  surface text,
  interaction text not null default 'view',
  dwell_seconds integer check (dwell_seconds >= 0),
  labels jsonb not null default '{}'::jsonb check (jsonb_typeof(labels) = 'object'),
  labeler_version text,
  ingested_at timestamptz not null default now(),
  foreign key(user_id, source_id) references public.wb_sources(user_id,id),
  unique(user_id, source_id, external_id)
);
create index on public.wb_social_exposures(user_id, observed_at desc);
create index on public.wb_social_exposures(user_id, source_id);

create table public.wb_checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  recorded_at timestamptz not null default now(),
  mood smallint not null check (mood between 1 and 5),
  energy smallint check (energy between 1 and 5),
  notes text check (length(notes) <= 4000)
);
create index on public.wb_checkins(user_id, recorded_at desc);

create table public.wb_model_versions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  version text not null,
  description text not null,
  validation_status text not null default 'experimental' check (validation_status in ('experimental','validated','retired')),
  created_at timestamptz not null default now(),
  unique(name, version)
);

-- Each module may produce an assessment; a separate fusion model can combine them.
-- Signals are explicitly not diagnoses. No automatic risk thresholds are seeded.
create table public.wb_assessments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  model_version_id uuid not null references public.wb_model_versions(id),
  module text not null check (module in ('wearables','app_usage','social_feed','combined')),
  window_start timestamptz not null,
  window_end timestamptz not null,
  signal text not null check (signal in ('insufficient_data','no_change','change_detected','review_suggested')),
  confidence double precision check (confidence between 0 and 1),
  data_coverage double precision not null check (data_coverage between 0 and 1),
  baseline_start timestamptz,
  baseline_end timestamptz,
  evidence jsonb not null check (jsonb_typeof(evidence) = 'object'),
  explanation text not null,
  created_at timestamptz not null default now(),
  check (window_end > window_start),
  check ((baseline_start is null and baseline_end is null) or
    (baseline_start is not null and baseline_end is not null and baseline_end > baseline_start and baseline_end <= window_start)),
  unique(user_id,id),
  unique(user_id,model_version_id,module,window_start,window_end)
);
create index on public.wb_assessments(user_id, created_at desc);
create index on public.wb_assessments(model_version_id);

create table public.wb_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  assessment_id uuid not null,
  message text not null,
  created_at timestamptz not null default now(),
  unique(user_id,id),
  unique(user_id,assessment_id),
  foreign key(user_id,assessment_id) references public.wb_assessments(user_id,id)
);
create index on public.wb_alerts(user_id, created_at desc);

create table public.wb_alert_deliveries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  alert_id uuid not null,
  channel text not null check (channel in ('in_app','push','email')),
  attempt integer not null check (attempt > 0),
  status text not null check (status in ('pending','sent','failed','cancelled')),
  provider_message_id text,
  error_code text,
  attempted_at timestamptz not null default now(),
  sent_at timestamptz,
  check ((status = 'sent') = (sent_at is not null)),
  foreign key(user_id,alert_id) references public.wb_alerts(user_id,id),
  unique(user_id,alert_id,channel,attempt)
);
create index on public.wb_alert_deliveries(user_id, attempted_at desc);

create table public.wb_alert_acknowledgements (
  user_id uuid not null references public.wb_profiles(user_id) on delete cascade,
  alert_id uuid not null,
  acknowledged_at timestamptz not null default now(),
  primary key(user_id,alert_id),
  foreign key(user_id,alert_id) references public.wb_alerts(user_id,id)
);

-- Private helpers are outside the Data API. Trigger checks also apply to service_role.
create schema if not exists wb_private;
revoke all on schema wb_private from public, anon, authenticated;
create function wb_private.require_consent() returns trigger
language plpgsql security definer set search_path = '' as $$
declare allowed boolean;
begin
  -- A withdrawn opt-in must not prevent cancellation/failure bookkeeping.
  if tg_table_name = 'wb_alert_deliveries' then
    if new.status in ('cancelled','failed') then return new; end if;
  end if;
  select granted into allowed from public.wb_consent_events
    where user_id = new.user_id and scope = tg_argv[0] order by id desc limit 1;
  if allowed is distinct from true then
    raise exception 'Active consent required for %', tg_argv[0] using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function wb_private.require_consent() from public, anon, authenticated;

do $$
declare r record;
begin
  for r in select * from (values
    ('wb_wearable_observations','wearables'),('wb_sleep_sessions','wearables'),
    ('wb_location_samples','location'),('wb_app_usage_intervals','app_usage'),
    ('wb_social_exposures','social_feed'),('wb_assessments','analysis'),
    ('wb_alerts','notifications'),('wb_alert_deliveries','notifications')
  ) as x(tbl,scope)
  loop
    execute format('create trigger consent_guard before insert or update on public.%I for each row execute function wb_private.require_consent(%L)', r.tbl,r.scope);
  end loop;
end $$;

-- Explicit privilege reset covers Supabase projects with permissive default grants.
do $$
declare t text;
begin
  foreach t in array array['wb_profiles','wb_consent_events','wb_sources','wb_metric_types',
    'wb_wearable_observations','wb_sleep_sessions','wb_location_samples','wb_app_usage_intervals',
    'wb_social_exposures','wb_checkins','wb_model_versions','wb_assessments',
    'wb_alerts','wb_alert_deliveries','wb_alert_acknowledgements']
  loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public, anon, authenticated, service_role',t);
    execute format('grant select on public.%I to authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
    if t in ('wb_metric_types','wb_model_versions') then
      execute format('create policy read_catalog on public.%I for select to authenticated using (true)',t);
    else
      execute format('create policy read_own on public.%I for select to authenticated using (user_id = (select auth.uid()))',t);
    end if;
  end loop;
end $$;
revoke all on sequence public.wb_consent_events_id_seq from public,anon,authenticated,service_role;
grant usage,select on sequence public.wb_consent_events_id_seq to service_role;
-- Consent history is append only for application roles.
revoke update,delete on public.wb_consent_events from service_role;

grant insert,update on public.wb_profiles to authenticated;
create policy insert_own on public.wb_profiles for insert to authenticated with check (user_id = (select auth.uid()));
create policy update_own on public.wb_profiles for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
grant insert on public.wb_checkins, public.wb_alert_acknowledgements to authenticated;
create policy insert_own on public.wb_checkins for insert to authenticated with check (user_id = (select auth.uid()));
create policy insert_own on public.wb_alert_acknowledgements for insert to authenticated with check (user_id = (select auth.uid()));

comment on table public.wb_profiles is 'App profile; identity, email and password hashes are managed by Supabase Auth. Birth year is optional; exact age is intentionally not stored.';
comment on table public.wb_sources is 'Source provenance only. Keep OAuth tokens in a server-only encrypted secret store.';
comment on table public.wb_assessments is 'Versioned experimental change signals; not a diagnosis or guarantee of relapse prevention.';
notify pgrst, 'reload schema';
commit;
