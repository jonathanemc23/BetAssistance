# NBA Intelligence engine

The statistics engine behind ProBets' NBA Intelligence section: it projects
minutes, points, rebounds and assists for NBA players as probability
distributions, answers Over/Under for a line typed by hand, and measures
itself with time-ordered backtests.

It predicts and measures only. It never reads or changes the bankroll, bets,
units or stakes (those stay in the app, `lib/data/`).

Plan and design: the Phase 1 audit doc in the project; this file tracks what
is built.

## Layout

| Path | What it does |
| --- | --- |
| `nba_engine/providers/base.py` | The types every data provider returns (`Game`, `BoxScore`, `PlayerLine`, `TeamLine`) and the `Provider` interface |
| `nba_engine/providers/espn.py` | ESPN's public JSON feed (scoreboard + game summary) |
| `nba_engine/ids.py` | Our own team, player and game ids; providers' ids are only links to them (`nba.external_ids`) |
| `nba_engine/availability.py` | Hand-entered availability (available, questionable, out, restricted) and how it changes the minutes projection |
| `nba_engine/http.py` | GET with a pause between requests and retries with backoff |
| `nba_engine/config.py` | Settings from environment variables |
| `nba_engine/db.py` | Connection to the server's Postgres, schema `nba` |
| `nba_engine/store.py` | Writes games, players, box scores and raw responses (compressed) into schema `nba`, under our own ids; every write can be repeated |
| `nba_engine/validate.py` | Checks each box score before it is stored: impossible stats, odd minutes, totals that don't add up, duplicates |
| `nba_engine/ingest.py` | Loads days: the historical load (resumable) and the daily update |
| `nba_engine/report.py` | What the database holds, by season, and the problems found |
| `nba_engine/cli.py` | `python -m nba_engine check`, `fetch`, `ingest`, `backfill`, `report` |
| `tests/` | Unit tests, with real ESPN responses in `tests/fixtures/` |

The database schema is `backend/src/main/resources/db/migration/V4__nba.sql`
(and `V5__nba_raw_encoding.sql`), run by the server's Flyway on deploy. The
engine never creates tables.

## Running

```sh
cd nba
pip install -r requirements-dev.txt
python -m pytest -q
python -m nba_engine fetch --date 2025-11-20      # read a day from ESPN, no writes
export DATABASE_URL=postgresql://...
python -m nba_engine check
python -m nba_engine ingest                       # yesterday and today (US Eastern)
python -m nba_engine backfill [--max-days 200]    # from NBA_FIRST_SEASON; resumes where it stopped
python -m nba_engine backfill --from 2025-01-10 --to 2025-01-12 --force   # load some days again
python -m nba_engine report
```

Database tests (`tests/test_ingest.py`) run when `TEST_DATABASE_URL` points
at a Postgres with the server's migrations; they empty schema `nba` first.

| Variable | Default | Meaning |
| --- | --- | --- |
| `DATABASE_URL` | none | Postgres (Neon's `postgresql://...` or the JDBC form) |
| `NBA_PROVIDER` | `espn` | Data provider |
| `NBA_FIRST_SEASON` | `2023` | First season loaded (named by the year it ends: 2023 = 2022-23) |
| `NBA_REQUEST_PAUSE` | `0.5` | Seconds between provider requests |
| `NBA_LOG_LEVEL` | `INFO` | Log level |

CI: `.github/workflows/nba.yml` runs the server migrations on a real
Postgres, the tests, `check`, and a short live load (three days, loaded
twice to show nothing changes the second time).

Data runs: `.github/workflows/nba-data.yml` runs the daily update every
morning at 11:00 UTC against the real database, and the historical load or
the report when started by hand (Actions → NBA data → Run workflow). The
daily run also keeps the free Supabase project from pausing.

## Data rules

- Missing is not zero: a stat the provider didn't report is `None`/`null`.
  A player who didn't play has `did_not_play` and no stats.
- Every stored row records when it was fetched (`fetched_at`) and when the
  information existed (`available_at`, a game's final whistle), so backtests
  only use what was known before each game.
- Raw provider responses are kept in `nba.raw_payloads`, gzip-compressed:
  a scoreboard whole, a game summary's `header`, `boxscore` and `gameInfo`
  sections as sent (the rest, plays and news, is most of the size and isn't
  read). About 8 KB a game, so the whole history fits the free 500 MB.
- A game's rows become available at its final whistle: when we saw it
  final, or for a game loaded later, tip-off + 4 hours (the safe side).
- Problems are flagged, never fixed or dropped: `player_games.flags` and
  `nba.import_log`. Models leave flagged rows out.
- Teams, players and games carry our own ids. Each provider's ids live in
  `nba.external_ids`, so a new provider adds links; models never see a
  provider id.
- Availability reports are insert-only; a prediction uses the latest report
  made before it and stores which one (`availability_id`, `play_probability`).
- Predictions are insert-only, with model name and version, so any past
  prediction can be reproduced.

## Data source and licence

Phase 1 uses ESPN's public JSON feed: free, no key, seasons back to at least
2022-23, with minutes, starters and did-not-play reasons. It has no published
licence and ESPN's terms don't allow commercial use, so it is for
development and analysis only. Before projections are sold (for tokens or
otherwise) a licensed provider replaces it behind `Provider`; nothing else in
the engine changes.

## Stages

| Stage | Status |
| --- | --- |
| 0. Package, settings, logs, ESPN provider, own ids, availability, schema `nba`, CI ([report](reports/stage-0.md)) | Done |
| 1. Historical load and daily update, validation, import log ([report](reports/stage-1.md)) | In review |
| 2. Features (windows, rates, rest, opponent) with time cut-off | |
| 3. Minutes engine and backtest | |
| 4. Points, rebounds, assists, distributions, Over/Under/Push | |
| 5. Server endpoints `/api/nba/*` | |
| 6. NBA Intelligence screens in the app | |
| 7. Documentation and acceptance review | |
