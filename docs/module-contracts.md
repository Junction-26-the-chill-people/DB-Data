# Detection and patient component contracts

Read the version notice in the root README first. All timestamps are `timestamptz`; use explicit UTC offsets. All personal rows carry the same Supabase Auth `user_id`. A `wb_sources` row identifies a provider/account/device stream owned by that user. Do not create identities for each detector.

## Wearables and mobility

- Writes: `wb_wearable_observations`, `wb_sleep_sessions`, optionally `wb_location_samples` through the backend. Register provider/device streams in `wb_sources`.
- Consent: `wearables` for measurements/sleep; separate `location` for GPS; `analysis` for assessment processing. Before reading historical data for analysis, the worker must verify active analysis consent and the team's current scope-withdrawal policy.
- Seeded metrics/units: steps/count, active_energy/kcal, heart_rate/bpm, resting_heart_rate/bpm, hrv_rmssd/ms, hrv_sdnn/ms, respiratory_rate/breaths/min, oxygen_saturation/percent, skin_temperature/degC, skin_temperature_deviation/degC. HRV definitions and absolute temperature vs deviation are different metrics.
- Detector responsibility: personal changes in activity/sleep/physiology, optional mobility regularity. Produce `module = 'wearables'`. An Oura-specific score requires a registered metric with documented scale, not reuse of a different metric.
- Excludes content recommendation analysis and app-duration classification. Do not treat stationary GPS or missing watch samples as proof of a mental-health change.
- Deduplication: unique `(user_id, source_id, external_id, metric_code)` for wearable events; `(user_id, source_id, external_id)` for sleep/location. Cross-provider overlap still needs preferred-source logic. Store intervals, not cumulative snapshots misrepresented as interval totals.

## Screen time / app time

- Writes: `wb_app_usage_intervals` with source/device, stable event ID, app identifier, platform, interval boundaries, foreground seconds and optional opens.
- Consent: `app_usage`, plus `analysis` to assess. Produce `module = 'app_usage'`.
- Detector responsibility: duration/timing, late-night routine changes, fragmentation and app mix relative to baseline. A device-wide total belongs in an explicitly documented app identifier such as `device.total`; never sum it with its constituent app rows.
- Excludes claims about what someone saw or how a recommendation algorithm ranked content. Do not infer content labels from app identity alone.
- `foreground_seconds` must be between zero and the interval duration. Overlapping device/app intervals require documented aggregation. Provider/OS permission availability must be checked before promising collection.

## Social feed / algorithm analysis

- Writes: `wb_social_exposures` with platform, observed time, exposure-event ID, optional content reference, surface, interaction, dwell duration, labels and `labeler_version`.
- Consent: `social_feed`, plus `analysis` to assess. Produce `module = 'social_feed'`.
- Detector responsibility: patterns in content actually observed, exposure repetition, interaction and label distributions. State the sampling limits and collection method in assessment evidence.
- Labels are an object with a documented taxonomy/probability scale. Always identify the labeling model/version when labels are used. Raw feed text/media and account handles are not required by the schema; do not collect them by default.
- Repeated views of the same post are separate exposure events; the post ID alone is not an idempotency key. Missing/unseen content must not become a negative exposure.
- Excludes access to the platform's internal recommendation algorithm. Collection APIs/permissions are an integration question, not something this database grants.

## Patient app / patient-reported data

- Reads: the signed-in user's own accessible rows. Direct writes: own `wb_profiles` insert/update, own `wb_checkins` insert, own `wb_alert_acknowledgements` insert.
- Check-ins: `mood` required 1-5; optional `energy` 1-5 and notes up to 4000 characters. Define the user-facing scale labels consistently (higher = better mood/energy). This is an informal check-in, not an implemented validated questionnaire.
- Profile: optional birth year/gender/country plus timezone. Email/password live in Supabase Auth. There is no clinician/patient relationship model, care-team access, diagnosis table or questionnaire scoring table in v1.0.0.
- Consent UI calls the authenticated backend; it cannot insert consent history directly. Backend records a new grant/withdrawal event and the displayed policy version.
- Acknowledgement means the user acknowledged a message; it does not establish that an intervention succeeded or symptoms improved.
- There is no `patient` assessment enum. A future standalone patient-input detector or clinical instrument requires a new migration and documented interpretation; do not squeeze it into `wearables`.

## Shared assessment output

All detectors register a `wb_model_versions` row (unique name/version) through the backend and write `wb_assessments`:

| Field | Contract |
| --- | --- |
| `user_id`, `model_version_id` | Real owner and registered exact model release |
| `module` | `wearables`, `app_usage`, `social_feed`, or `combined` |
| `window_start`, `window_end` | Explicit assessment interval with end > start |
| `signal` | `insufficient_data`, `no_change`, `change_detected`, `review_suggested` |
| `confidence` | Optional 0-1 model-specific confidence; not a probability of depression unless separately validated |
| `data_coverage` | 0-1; include denominator and expected cadence in evidence |
| `baseline_start`, `baseline_end` | Both absent, or a valid interval ending at/before the assessment window |
| `evidence` | JSON object, conventions below |
| `explanation` | Plain-language account of measured changes, coverage and uncertainty |

Use the unique `(user_id, model_version_id, module, window_start, window_end)` key for idempotent computation. A new computation method gets a new model version. The version registry defaults to `experimental`; do not claim clinical validation by setting a database flag alone.

Recommended evidence shape (a JSON convention, not SQL-enforced fields):

```json
{
  "contract_version": "1.0.0",
  "feature_version": "wearables-features/1",
  "source_ids": ["<SOURCE_UUID>"],
  "input_assessment_ids": [],
  "features": [{"name": "sleep_duration_seconds", "current": 21600, "baseline": 25200, "unit": "s"}],
  "coverage": {"observed": 6, "expected": 7, "definition": "nights with valid sleep sessions"},
  "limitations": ["Illustrative values only; no clinical threshold implied"]
}
```

Do not compare raw confidence values from different models without calibration. Missing/offline data should yield `insufficient_data`; it must not be treated as worsening behavior. Signals are change indicators, not diagnoses or severity categories.

## Combined assessment and alerts

The combined detector uses `module = 'combined'`, its own model version, compatible time windows and evidence references to the module assessments it actually used. It may include patient check-ins, identifying those inputs and their time windows. It preserves original detector outputs and documents missing/conflicting sources rather than silently treating missing inputs as neutral evidence.

The alerting backend applies a separately reviewed policy to assessments. It alone creates `wb_alerts`, writes `wb_alert_deliveries`, checks active notification consent immediately before sends, applies cooldowns/quiet hours, and manages retries with provider idempotency. The DB prevents two alerts for the same user/assessment, but does not enforce cross-assessment cooldowns or send a message automatically. An assessment may justify no alert.

Use `pending`, `sent`, `failed`, `cancelled` accurately; `sent` requires `sent_at`. Failed/cancelled bookkeeping is allowed after withdrawal so jobs can be stopped. Avoid sensitive message text in notification previews; link the user back into their signed-in app.
