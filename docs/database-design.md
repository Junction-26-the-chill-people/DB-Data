# Wellbeing database starter

Target: Supabase project `huvxbsfwyjddbnbpjroh`.

`supabase/migrations/20261114000100_wellbeing_schema.sql` is a one-time, atomic migration (repository-root path). This file being present does not mean it has been applied; see [deployment status](deployment-status.md) for the verified state. The `wb_` prefix keeps this module identifiable in the public schema. Existing matching tables cause the transaction to fail instead of replacing data. Do not run the initial migration again on the existing project. This script does not modify Supabase CLI migration history. Read the root [README](../README.md) and [change workflow](change-workflow.md) before integrating or changing the schema.

## Relationships and responsibilities

Every personal record must belong to a user. Separate modules share that same user ID, rather than creating separate identities.

| Tables | Purpose | Writes |
| --- | --- | --- |
| `auth.users` (existing Supabase table) | Login, email, password handling | Supabase Auth |
| `wb_profiles` | Optional birth year, gender, country; display timezone | Owner or backend |
| `wb_consent_events` | Append-only grant/withdrawal history per scope | Backend |
| `wb_sources` | Provider accounts/devices and sync provenance | Backend |
| `wb_metric_types` | Canonical metric names, units and aggregation hints | Backend |
| `wb_wearable_observations` | Steps, energy, heart rate, HRV, temperature, etc. | Backend |
| `wb_sleep_sessions` | Sleep windows and optional stage totals | Backend |
| `wb_location_samples` | Separate optional GPS collection | Backend |
| `wb_app_usage_intervals` | App/device usage within a measured interval | Backend |
| `wb_social_exposures` | Observed feed exposures/interactions and versioned labels | Backend |
| `wb_checkins` | User-reported mood and energy, 1–5 | Owner insert or backend |
| `wb_model_versions` | Experimental model/version registry | Backend |
| `wb_assessments` | Module or combined change signals, baseline and evidence | Backend |
| `wb_alerts` | User-facing messages attached to an assessment | Backend |
| `wb_alert_deliveries` | Notification attempts, failures and delivery timestamps | Backend |
| `wb_alert_acknowledgements` | User acknowledgement, separate from actual delivery | Owner insert or backend |

Sources link to profiles. Observations link to sources with a composite `(user_id, source_id)` foreign key: a record cannot claim somebody else's device. Assessments link to model versions, alerts to assessments, and delivery attempts/acknowledgements to alerts, with the same ownership protection.

Passwords and email remain in Supabase Auth. Do not build a second password-hash table. Birth year avoids storing a changing age, but gives only an approximate age. If exact age is essential for an eligibility rule, design that explicitly before relying on it. Country is separate from precise location history. Use an IANA timezone such as `Europe/Bucharest`; the backend must validate timezone values.

## Security and consent

All 15 app tables enable row level security. Anonymous clients have no privileges. Authenticated users can read their own records plus the shared metric/model catalogs. They can insert/update their profile, insert check-ins, and acknowledge their own alerts. Ingestion, consent acceptance and assessment/alert writes require a trusted backend. There are no clinician, teammate or researcher data-sharing policies in this starter.

The service role bypasses RLS, so each backend endpoint must authenticate the caller and derive `user_id` from the verified JWT. Never trust a user-supplied ID. Keep the secret key, database password and OAuth tokens out of browser/mobile bundles, source control, logs and the `metadata` JSON. Use the publishable key and the signed-in user's session in clients.

Consent choices use `wearables`, `location`, `app_usage`, `social_feed`, `analysis`, and `notifications`. Accept choices through a backend endpoint that records the actual choice and displayed policy version. The highest event ID is the effective choice for a user/scope. Serialize concurrent updates for a user/scope in the backend; sequence order records acceptance order, not client clock time. App roles cannot update/delete history. Account deletion still cascades through it.

Triggers check consent on insert/update of telemetry, assessments, alerts and deliveries, including service-role writes. Sleep uses wearable consent. Failed/cancelled delivery bookkeeping remains possible after withdrawal. The database records consent decisions but does not validate the consent UI or the user's legal eligibility. Withdrawal blocks new collection/analysis/notification writes; it does not automatically delete historical records, cancel queued notifications, revoke provider tokens, or remove backups. The backend must implement those actions and check current consent immediately before contacting a provider, computing features, or sending a notification. Existing data remains readable by its owner after withdrawal. Check-ins are user-initiated and are not part of passive collection.

## Integration sequence

1. Sign up/sign in with Supabase Auth. After an authenticated session exists, upsert `wb_profiles` with `user_id = session.user.id`. No signup trigger is installed, so profile errors cannot break Auth signup.
2. Show separate opt-ins and save decisions via the trusted backend.
3. Connect a provider, keep credentials in a server-only encrypted store, and insert `wb_sources`. Use a separate source for each device/account stream where possible.
4. Normalize provider data to the registry units. Use UTC offsets/timestamptz for every measurement. Preserve provider-specific quality information without copying unnecessary personal payloads.
5. Upsert observations using `(user_id, source_id, external_id, metric_code)`; use `(user_id, source_id, external_id)` for sleep, location, usage and feed events. `external_id` must identify the stable provider sample or exposure event, not merely a post ID or sync request. For observations without provider IDs, derive a stable ID from the source, metric, interval and provider sample discriminator.
6. Choose a preferred source per metric and deduplicate overlapping streams before computing features. Apple Health may contain data already imported from a watch/Oura. Unique keys prevent retries from duplicating the same source event; they do not deduplicate across providers. Never blindly sum overlapping samples or cumulative snapshots.
7. Compute coverage and a personal baseline in a backend worker, then write versioned assessments. Missing/offline data must produce an insufficient-data outcome rather than being interpreted as worsening mood. Store source choices, feature versions and evidence/sample references in `evidence`.
8. A separately reviewed alerting policy decides whether to create an alert. The worker enforces cooldowns, notification opt-in, quiet hours and retry limits. Delivery attempts must be idempotent at the notification provider. An alert row does not send anything by itself.

No connectors, scoring model, jobs, push/email service or alert thresholds are deployed by this schema. Model, assessment, alert and delivery tables start empty. No real users are created by the migration.

## Wearable example

This is a backend example after profile, consent and source creation. Replace every placeholder. The source must belong to that user. Units come from `wb_metric_types`.

```sql
insert into public.wb_wearable_observations
  (user_id, source_id, external_id, metric_code, started_at, ended_at, value)
values
  ('<USER_UUID>', '<SOURCE_UUID>', 'provider-sample-123', 'steps',
   '2026-11-14T08:00:00Z', '2026-11-14T09:00:00Z', 1240)
on conflict (user_id, source_id, external_id, metric_code)
do update set value = excluded.value,
              started_at = excluded.started_at,
              ended_at = excluded.ended_at;
```

For instant samples, set start=end. For daily totals, convert the provider's actual local-day boundaries to UTC; daylight-saving days are not always 24 hours. `sum`/`mean` in the metric catalog is a hint, not an aggregation implementation. Irregular samples may need time weighting. Provider-specific scores need their own metric code, unit/scale and documented meaning.

An authenticated frontend can query its wearable history using its regular Supabase client:

```js
const { data, error } = await supabase
  .from('wb_wearable_observations')
  .select('metric_code,started_at,ended_at,value,source_id,quality')
  .eq('metric_code', 'steps')
  .order('started_at', { ascending: false })
  .limit(100);
```

RLS restricts the query to that signed-in user. All API errors must be checked.

## Before collecting real participant data

This is an engineering starter for change monitoring, not a validated relapse detector. Sleep/activity changes have multiple explanations. Establish the clinical purpose, validation method, false-positive/false-negative handling, and supportive alert copy with qualified specialists. Do not imply that a watch can diagnose depression or guarantee prevention. A monitored, consented human support pathway needs its own operating process.

Confirm what data each provider/OS actually makes available and under which permissions. A schema does not grant access to Instagram's internal algorithm or to unrestricted iOS/Android app usage. Prefer derived features and coarse location where they suffice; precise routes and raw feed content should require a specific justified need.

Decide the participant age range, supported countries, retention periods, deletion/export workflow, and team access before launch. No retention periods are invented or purge job enabled here. Account deletion through a server-only Auth admin endpoint cascades the app records; disconnect/revoke external providers and handle notification systems, exported data and backup retention separately. Avoid deleting profiles directly while leaving active collection running.

At higher volume, assess partitioning of large event tables, batching, and daily feature materialization using measured query plans. Do not add partitioning merely to start the MVP.

References: [Supabase user data](https://supabase.com/docs/guides/auth/managing-user-data), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [API key handling](https://supabase.com/docs/guides/getting-started/api-keys), [NICE relapse prevention guidance](https://www.nice.org.uk/guidance/ng222/chapter/Recommendations).
