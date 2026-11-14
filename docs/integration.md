# Integration guide

Run the root README freshness checks before using these contracts. See `module-contracts.md` for module ownership and `database-design.md` for table details.

## Identity and write permissions

Use the publishable key with the user's Supabase Auth session on the frontend. Use server-only credentials for privileged workers/endpoints. Every backend must verify the caller and derive the owner from the authenticated session or an established provider-account mapping, including signed webhook validation; never accept an arbitrary owner ID supplied by a client. Service-role access bypasses RLS.

1. After Auth signup/sign-in yields a session, upsert `wb_profiles` using that Auth user ID. No Auth signup trigger creates a profile automatically.
2. Backend accepts separately presented consent scopes: `wearables`, `location`, `app_usage`, `social_feed`, `analysis`, `notifications`. Append to `wb_consent_events` with the exact policy version. Serialize decisions per user/scope; highest event ID is effective. Preserve history.
3. Backend registers `wb_sources`, keeps OAuth credentials encrypted outside these tables, normalizes provider units and stable external event IDs, and ingests through the correct module's tables.
4. Backend registers exact detector releases in `wb_model_versions`, checks analysis permission and writes module assessments. Combined and alerting components consume those contracts separately.
5. Client can read its own results and insert its own check-ins/acknowledgements. Frontend cannot write telemetry, accept its own consent directly into the DB, create alerts, or assign model validation status.

Example frontend profile/check-in writes (the session is already verified by Supabase Auth; handle every error):

```js
const { data: { user }, error: authError } = await supabase.auth.getUser();
if (authError || !user) throw authError ?? new Error('Sign in first');
const { error: profileError } = await supabase.from('wb_profiles')
  .upsert({ user_id: user.id, timezone: 'Europe/Bucharest' });
if (profileError) throw profileError;
const { error: checkinError } = await supabase.from('wb_checkins')
  .insert({ user_id: user.id, mood: 3, energy: 3 });
if (checkinError) throw checkinError;
```

Example normalized backend wearable event (after consent/source registration):

```js
const { error } = await serverSupabase.from('wb_wearable_observations').upsert({
  user_id: verifiedOwnerId,
  source_id: ownedSourceId,
  external_id: stableProviderSampleId,
  metric_code: 'steps',
  started_at: '2026-11-14T08:00:00Z',
  ended_at: '2026-11-14T09:00:00Z',
  value: 1240
}, { onConflict: 'user_id,source_id,external_id,metric_code' });
if (error) throw error;
```

`serverSupabase` must never be exported to the browser. These snippets are examples, not a ready-made ingestion or consent API. Apply model/metric registry changes via documented migrations so every team's agents learn the same meanings.

## Error and time handling

- PostgreSQL `42501`: permission/consent failure; check role, verified user and current consent, never retry with weaker security.
- `23503`: missing profile/source/model or cross-owner reference. Register dependencies in order and verify ownership.
- `23505`: duplicate key. Use the declared stable conflict target; do not generate a fresh event ID just to bypass it.
- `23514`: invalid interval, range or enum. Normalize and validate the payload against the current migration/contract.
- Use explicit-offset ISO timestamps. A provider's local daily total needs actual local midnight boundaries converted to UTC, including daylight-saving changes. Sleep spanning midnight remains one session.
- Database ingestion timestamps are metadata. They are not the measurement time or a substitute for provider clock validation.

## Withdrawal, deletion and operations

DB consent guards prevent new protected writes, including from service-role workers. They do not stop remote API calls, ongoing computations, already queued notifications or token refreshes. Backend jobs must check consent before those actions and cancel/disconnect as needed. Previously stored data remains readable by the owner; retention/deletion policies are separate.

Delete an account through a trusted Auth-admin workflow; app records cascade from the Auth user. Handle provider revocation, notification systems, exports and backup retention separately. Do not let clients delete a profile while background collection continues.

There are no clinician/teammate sharing policies. Do not create shared service credentials for client apps or give team agents unrestricted participant-data access just to integrate.
