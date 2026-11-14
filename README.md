# Shared wellbeing database

> **SCHEMA CONTRACT: 1.0.0 | Latest migration: 20261114000100 | Updated: 2026-11-14**
>
> **Agents: check freshness before integrating or changing anything.** Run `python scripts/check_freshness.py`, then `python scripts/check_contract.py`. Read [AGENTS.md](AGENTS.md), the newest [CHANGELOG](CHANGELOG.md) entry, and your module contract. Every database change MUST ship with a new migration, a version-manifest update, this header, a changelog entry, and updated integration docs/tests in the same commit. Never edit an applied migration. A deployment snapshot is historical evidence; it is not a live drift check.

This repository is the shared Supabase database contract for the team. Every personal record belongs to the same Supabase Auth user. Modules own different inputs and assessment logic, while sharing identity, consent, provenance and the assessment output contract.

The initial schema is **already deployed** to project `huvxbsfwyjddbnbpjroh`. **Do not rerun the initial migration on that project.** No collection connectors, detection algorithms or notification services are included.

## Which component owns what?

| Component | Input tables | Detection responsibility | Assessment module |
| --- | --- | --- | --- |
| Wearables / mobility (our module) | `wb_wearable_observations`, `wb_sleep_sessions`, optional `wb_location_samples` | Changes in activity, sleep, physiology and consented mobility relative to the person's baseline | `wearables` |
| Screen time / app time | `wb_app_usage_intervals` | Usage duration, timing, fragmentation, app mix and changes in routines | `app_usage` |
| Social feed / algorithm analysis | `wb_social_exposures` | Patterns in observed recommended content and interactions; content labels must be versioned | `social_feed` |
| Patient app / onboarding | `wb_profiles`, `wb_checkins`, consent UI, `wb_alert_acknowledgements` | User-reported mood/energy and feedback; no independent detector enum currently exists for this component | None; patient input may be used by `combined` |
| Combined assessment | Existing assessments plus permitted source data/check-ins | Aligns windows, handles missingness/conflicting signals, combines evidence; does not overwrite module outputs | `combined` |
| Alerting / delivery | `wb_assessments`, then `wb_alerts`, `wb_alert_deliveries` | Applies separately reviewed alert policy, cooldowns, notification opt-in and delivery retries | None |
| Shared platform/backend | `auth.users`, `wb_sources`, `wb_consent_events`, `wb_metric_types`, `wb_model_versions` | Authentication, consent, ingestion validation, provenance and model registration | None |

Table ownership here defines engineering responsibilities. It does not grant new database roles: all privileged workers currently use a trusted backend, so that backend must enforce module permissions. Teammates do not automatically get participant-data access.

## Agent/team handoff

Give your agent this repository and a module assignment:

```text
Integrate the <wearables | app_usage | social_feed | patient | combined | alerting> module
with https://github.com/Junction-26-the-chill-people/DB-Data.
Read AGENTS.md first, check repository freshness, then read docs/module-contracts.md
and docs/integration.md. Report the schema version and commit you integrated against.
Use existing tables and ownership/consent rules. If the contract must change, add a
forward migration and update the version manifest, README header, CHANGELOG,
integration documentation and relevant tests together. Do not silently change the
live database or store secrets in this repository.
```

## Start here

1. Clone this repository and run the freshness/contract checks above (Python 3.10+; standard library only).
2. Read [module contracts](docs/module-contracts.md) and [integration guide](docs/integration.md).
3. Use Supabase Auth for signup/login; create the app profile once the user is signed in. Accept separate consent choices through a trusted backend.
4. Register sources and model versions through the backend. Normalize measurements, use stable source event IDs and check all API errors.
5. Write your own module's assessments using the common contract. Only the alerting component creates/delivers alerts.
6. Follow the [change and deployment workflow](docs/change-workflow.md) before changing the shared contract.

## Repository map

- `supabase/migrations/`: immutable, ordered SQL migrations; the initial file matches the deployed SQL bytes.
- `schema-version.json`: repository schema version, migration inventory and SHA-256 checksums.
- `CHANGELOG.md`: newest release first, including compatibility impact and integration actions.
- `deployments/`: project-specific historical deployment snapshots; update only after verified application.
- `docs/database-design.md`: schema relationships, constraints, security and wearable example.
- `docs/module-contracts.md`: boundaries and the shared assessment/evidence shape.
- `docs/integration.md`: frontend/backend write permissions and integration examples.
- `docs/change-workflow.md`: freshness, migrations, deployment and drift investigation.
- `docs/deployment-status.md`: initial deployment and live verification evidence.
- `tests/verify_access.sql`: rollback-only live ownership, consent and alert-flow checks.
- `scripts/`: local/CI contract checks and remote freshness check.

## Security and operating limits

All 15 app tables have row level security. Signed-in users can read their own rows, edit their profile, add check-ins and acknowledge their own alerts. Telemetry, consent acceptance, model assessments and alerts require backend writes. Secrets and database credentials belong in your team's secret manager, never this repository. `.env.example` contains names/placeholders only.

Health and behavior signals are experimental change indicators. The database does not diagnose depression or guarantee relapse prevention. Provider permissions determine available data; social-feed storage does not give access to a platform's internal recommendation algorithm. Retention policy, participant eligibility, clinical validation and support operations still need team decisions.
