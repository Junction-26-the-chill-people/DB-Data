# Changelog

## [1.0.0] - 2026-11-14

- Initial shared database contract: 15 `wb_*` tables, ten canonical wearable metrics, user ownership, composite foreign keys, RLS, consent guards and alert bookkeeping.
- Migration: `20261114000100_wellbeing_schema.sql`. Already applied and live-tested on the project in `deployments/huvxbsfwyjddbnbpjroh.json`; it must not be rerun there.
- Affected components: wearables/mobility, app usage, social feed, patient onboarding/check-ins, combined assessment, alerting and shared backend.
- Consumer action: use the module contracts, create profiles after Auth signup, obtain separate consent, ingest through a trusted backend, and emit the common versioned assessment shape. No earlier contract exists; no legacy backfill is required.
- Validation: live rollback-only ownership, privileges, consent, constraints, deduplication, alert workflow and account-deletion checks passed. Only metric catalog seeds remain; no test participant rows were retained.
- Repository release adds agent instructions, freshness/version/checksum checks, contract CI and integration documentation. CI does not deploy to Supabase.
