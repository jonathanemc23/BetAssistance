# Stage 0 report: foundation

Date: 2026-11-24. Pull request: #54.

## What was built

- `nba/` Python package: settings from environment variables, logs with a
  run id, an HTTP getter that pauses between requests and retries with
  backoff, the `Provider` interface and the ESPN provider.
- Provider independence: teams, players and games get our own ids
  (`nba_engine/ids.py`); each provider's ids are links in `nba.external_ids`.
  ESPN's team abbreviations (GS, NY, SA, NO, UTAH, WSH) map to the official
  ones.
- Hand-entered availability (`nba_engine/availability.py`,
  `nba.player_availability`): available, questionable, out, restricted with a
  minutes cap. Insert-only; a prediction uses the latest report made before
  it. Out = no projection; restricted = minutes capped; questionable = P(plays)
  shown, 50% until calibrated.
- Schema `nba` (`backend/.../V4__nba.sql`), additive, owned by the server's
  Flyway. Every row carries `fetched_at` / `available_at`; predictions are
  insert-only and record model version, availability report and P(plays);
  backtest metrics carry 95% confidence intervals.
- CI: `.github/workflows/nba.yml` (tests, migrations on Postgres 16, engine
  check against the database and the live feed);
  `.github/workflows/server-diagnosis.yml` (read-only server checks).

## Server failure (Cloud Run)

- Cause, confirmed by the diagnosis run: Neon refuses connections with
  "Your account or project has exceeded the quota". The Cloud Scheduler tick
  read the database every minute, so Neon never scaled to zero and used up
  the free plan's compute hours. The live server answers 500; the new
  revision can't start because Flyway can't connect.
- Fix in this PR: the alert job doesn't read the database while no followed
  match is near (wakes 30 minutes before the next kick-off, or when a phone
  saves its matches); the connection pool keeps no idle connections. The
  deploy now checks the database first and prints the failed revision's log.
- Still needed: Neon reactivated (paid plan or the monthly reset). The
  deploy account also needs `roles/logging.viewer` to read logs.

## Tests

| Suite | Result |
| --- | --- |
| `nba` pytest | 23 passed |
| Server `mvn verify` (H2) | 19 passed, including the new quiet-mode test |
| Migrations V1-V4 on Postgres 16 | Applied; `nba_engine check` reports the schema complete |
| Quiet-mode test with the fix switched off | Fails, so the test does guard the fix |

## Known issues

- No critical errors in stage 0.
- ESPN has no commercial licence; fine for internal testing only.
- Potential Assists, time of possession and lineup data aren't in the source.

## Next: stage 1

Historical load from 2022-23 and the daily update, with validation
(duplicates, impossible stats, missing vs zero, team changes, odd minutes)
and an import report. It needs Neon running again.
