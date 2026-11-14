# Freshness, migrations and deployment

## Check your local version first

```sh
python scripts/check_freshness.py
python scripts/check_contract.py
git rev-parse HEAD
```

The freshness script fetches `origin/main`. Exit 0 means HEAD includes that remote branch; it prints whether HEAD is equal or ahead. Exit 1 means stale/diverged. Exit 2 means it could not verify (for example network/auth failure). It does not pull or modify local files. A dirty working tree is reported; commit/stash your own work intentionally before reconciling. Ahead commits are not automatically shared or deployed.

The offline contract script checks the migration inventory/checksums, README notice and changelog version. CI uses `--base-ref` to additionally reject modification/removal of released migrations and require a complete documentation/version bundle for new migrations. Neither check connects to a database.

Copied docs can go stale. Record the upstream URL, schema version and commit in the consuming application's integration notes. Before starting work, fetch upstream and read changelog entries since that commit. Pin a commit for reproducible integrations; do not assume a local copy's date makes it current.

## Propose and release a contract change

1. Start from current upstream without discarding other contributors' work. Determine affected modules and compatibility/backfill needs.
2. Add `supabase/migrations/<UTC_TIMESTAMP>_<description>.sql`. Timestamp IDs are 14 digits and must sort after the newest migration. Avoid destructive data changes; describe explicit backfill/rollback or forward-repair plans when necessary.
3. Keep all released SQL bytes unchanged. Compute the new SHA-256, append to `schema-version.json`, bump SemVer and update its date/latest ID.
4. Update the TOP README notice, newest CHANGELOG entry, and affected docs/contracts/examples/tests together. Document new required fields, units, consent scopes, enums and RLS differences, including action required by every affected team.
5. Run offline contract checks and meaningful SQL verification on an isolated Supabase/local test database. Run `python scripts/check_contract.py --base-ref origin/main` before proposing the change.
6. Commit/PR the complete bundle. Repository CI validates metadata and release immutability; it does not apply SQL or evaluate clinical logic.
7. Within an authorized live-deployment task, inspect the target, apply only pending migrations through the team's chosen migration runner and run relevant verification. Then update `deployments/<project_ref>.json` and deployment notes with actual results, and commit/push the evidence. A merged migration can be ahead of a deployed project.

### Existing project's initial baseline

`20261114000100_wellbeing_schema.sql` was applied manually before repository creation. It is the same bytes as the deployed original. It was NOT registered in `supabase_migrations.schema_migrations`.

Do not blindly run `supabase db push` on the existing project: the CLI may try to recreate the initial tables. A deployment owner must inspect the live schema and migration history, confirm the baseline, then reconcile/repair migration history using the chosen tool's current documented process before adopting it. Do not mark a migration applied unless its actual effects were verified. This repository does not include a linked project config or an auto-deployment workflow.

For a brand-new Supabase test project, apply the initial SQL once, followed by later migrations in order. It requires Supabase's Auth schema and roles; an arbitrary empty PostgreSQL instance does not supply those dependencies. The initial migration owns its transaction; do not wrap it in a conflicting runner transaction without checking runner behavior.

## Run the SQL verification

Against an authorized test/staging database with Supabase roles/Auth installed, use a trusted PostgreSQL connection and certificate verification:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/verify_access.sql
```

Set `PGSSLMODE=verify-full` and `PGSSLROOTCERT` to the correct public CA file. Never place actual credentials in shell history, committed files or chat examples. A password prompt or secret-injected environment is preferable. The script creates temporary Auth fixtures, impersonates application roles, verifies access/consent/constraints/alert relationships and rolls back. It must run as a sufficiently privileged test operator. It sends no notifications. As the schema evolves, update fixtures and assertions in the same release.

## What is actually deployed?

`schema-version.json` is the REPOSITORY contract. `deployments/*.json` records the last verified target state. Neither is a live database version endpoint. No dedicated live version table/RPC was added to the deployed schema.

To investigate drift, compare the target's migration history plus actual columns/constraints/functions/triggers/policies/grants against the committed migration effects, using authorized read-only inspection or schema diff tooling. A timestamp, a successful fetch or the presence of table names alone is insufficient. Reconcile manually applied changes into forward migrations and evidence; do not rewrite history/checksums to hide them. New deployment snapshots must identify the checked version and evidence, and must not contain secrets or participant rows.
