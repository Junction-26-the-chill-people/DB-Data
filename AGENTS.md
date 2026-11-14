# Instructions for all agents working with this database

These instructions apply to the whole repository and to integrations based on it.

## First actions on every task

1. Read the version/freshness notice at the TOP of `README.md`, `schema-version.json`, and the newest `CHANGELOG.md` entry.
2. Run `python scripts/check_freshness.py`. It fetches `origin/main`, compares ancestry and reports stale/diverged copies. It never pulls, resets, deploys or edits files. If it fails, establish the current upstream state before proposing a DB change. Network failure is NOT evidence that a checkout is current. Preserve local work; never reset it to hide divergence.
3. Run `python scripts/check_contract.py` and read `docs/module-contracts.md`, `docs/integration.md`, and `docs/change-workflow.md`.
4. State which module you own. Integration reports must include the schema version and Git commit SHA used. If docs were copied into another repository, retain the source repository URL, version and commit and fetch a fresh copy before making DB assumptions.

## Mandatory database-change contract

For ANY change to tables, columns, metric definitions, enums/checks, foreign keys, indexes, functions, triggers, RLS, grants or shared data meanings:

- Add a NEW forward migration under `supabase/migrations/` with a unique increasing UTC timestamp filename. Never alter or delete a released migration, including the initial schema.
- Update `schema-version.json`: bump SemVer, set `updated_at`, update `latest_migration`, and append the new file with its SHA-256. Major = breaking contract; minor = compatible additions; patch = compatible fixes. New meaning for an existing field can be breaking even if SQL types stay unchanged.
- Update the version, migration ID and date in the notice at the TOP of `README.md`.
- Add a newest-first `CHANGELOG.md` entry with the same version/date. Include migration IDs, affected modules, compatibility, consumer changes, data/backfill requirements, validation and deployment status. Never describe an unapplied change as deployed.
- Update every affected integration contract/example and meaningful verification. Update this AGENTS file if the working rules change. A docs-only change still needs a changelog entry, but need not bump the schema version.
- Run `python scripts/check_contract.py`; CI also checks release bundles against the base revision and rejects edits to released migrations or incomplete version/docs updates.
- Keep code and corresponding docs in the SAME commit/PR. Do not defer shared-contract documentation to another agent.
- Apply database changes only within the current user's authorization. A request to integrate an app or edit docs alone is not blanket authorization to change a shared live database. If a manual emergency change is authorized, immediately capture the exact SQL in a new migration and complete this documentation bundle in the same task; otherwise the task is unfinished.
- After an authorized deployment, run relevant live checks, update the deployment snapshot and changelog/status with the ACTUAL applied version and evidence, then commit/push those records. Never advance a deployment snapshot merely because a migration file exists.

## Module boundaries

- Wearables owns physiological/activity/sleep data and optional consented location. Its assessment module is `wearables`.
- App usage owns duration/timing/app routines; module `app_usage`.
- Social feed owns observed content/interaction labels and exposure patterns; module `social_feed`. Do not infer content sentiment from app duration alone.
- Patient UX owns profile/check-in/acknowledgement interaction and consent presentation. There is no `patient` assessment enum: adding one requires a new contract migration. Patient data can contribute to a documented `combined` model.
- Combined owns fusion and cross-module alignment; module `combined`. Keep original module assessments intact.
- Alerting alone owns alert policy and delivery. No individual detector may send notifications as a side effect of storing an assessment.
- Shared backend owns identity verification, consent acceptance, source/model registration and privileged data validation.

## Invariants you must preserve

- Use `auth.users.id` as shared identity and Supabase Auth for passwords/email. No duplicate password table.
- Keep user ownership, composite owner/parent foreign keys, RLS and least-privilege grants. Never expose a secret/service key or turn off RLS to fix an integration problem.
- Derive user identity from a verified session or server-established provider linkage. A secret-key request bypasses RLS; a caller-supplied `user_id` is not trusted.
- Register distinct provenance, normalize units/timestamps, and preserve stable idempotency keys. Do not sum overlapping provider totals or treat absent data as low activity/depression.
- Obtain active scope consent before collecting/processing/sending. DB triggers are a backstop, not permission to skip backend checks. Withdrawal also requires stopping workers and handling queued notifications/provider access.
- Validate model signals as experimental, version models/features/labels, include coverage and personal-baseline context. Do not introduce unreviewed clinical thresholds or prevention guarantees.
- Keep real participant data, database dumps, OAuth tokens, passwords and secret keys out of commits, fixtures, logs and examples. Use placeholders and synthetic rollback-only fixtures.

## Completion criteria

Report changed modules, schema version, compatibility, tests actually run, migration application status, and commit/PR. If blocked by access, say what remains unapplied/unverified. Git freshness and deployment snapshots do not prove the live database has no manual drift.
