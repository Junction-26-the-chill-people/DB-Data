# Deployment status

Successfully deployed on 14 November 2026 to Supabase project `huvxbsfwyjddbnbpjroh`.

Connected through the supplied Session pooler with TLS certificate-chain and hostname verification, using the user-provided Supabase Root 2021 CA. PostgreSQL server version: 17.11. The public schema had no pre-existing tables at inspection.

Applied the original SQL, now preserved byte-for-byte as `supabase/migrations/20261114000100_wellbeing_schema.sql`, in one committed transaction. All 15 app tables exist with RLS enabled. Ten canonical wearable metric definitions are seeded. No personal data or test fixtures remain in the app tables. Supabase Auth continues to manage identity, email and password hashing; its schema was not changed by the migration. This is a historical verification snapshot, not a live drift check.

Live verification using the SQL now stored at `tests/verify_access.sql` passed:

- Anonymous SELECT/INSERT privileges denied on all app tables.
- Authenticated users can read their own profiles/sources and insert their own check-ins; cross-user records are hidden and cross-user inserts denied.
- Client telemetry and consent writes denied; those require a trusted backend.
- Service-role ingestion without consent denied, permitted after grant, and denied after withdrawal.
- Consent history cannot be edited by the service role.
- Cross-user source and assessment references denied by foreign keys.
- Duplicate source events and invalid time ranges rejected.
- Assessment, alert, delivery and acknowledgement workflow exercised.
- Notification withdrawal blocks marking delivery sent, while cancellation remains possible.
- Other users cannot read alerts or acknowledge an alert through a foreign user/alert link.
- Auth account deletion cascades through observations and alert delivery records.

All test data, including temporary Auth rows, was created inside a transaction and rolled back. The final inventory confirmed 15 RLS-protected tables, 10 metric definitions, and no retained app fixtures. Tests did not contact wearable providers or send notifications.

Migration SHA-256: `1AAA8ABBAA344D1C6C0B1B6FAB18FBF4D451923614F9EFD5212DD5D251405136`.

This setup deploys database storage, constraints and access controls. Provider integrations, consent UI/backend endpoints, clinically evaluated detection logic, notification workers, retention/export/deletion services and operational monitoring remain application work. See the root [README](../README.md) and [integration guide](integration.md).

Rotate the database password and secret API key shared in chat, and update server-side configuration with their replacements. No secret credentials are included in the delivered files.
