# Stage 1 report: historical load, daily update, validation

Date: 2026-11-25. Status: built and tested; the load into Supabase runs
after the merge (Actions → NBA data → Run workflow, mode backfill).

## What was built

- `nba_engine/store.py`: writes games, teams, players, box scores and team
  totals into schema `nba` under our own ids, with each provider id linked
  in `nba.external_ids`. Every write can be repeated: a day loaded twice
  gives the same rows. Team changes are kept in `nba.player_team_spells`.
- Raw responses in `nba.raw_payloads`, gzip-compressed (new column
  `body_encoding`, migration `V5__nba_raw_encoding.sql`). A game summary
  keeps the sections the engine reads (`header`, `boxscore`, `gameInfo`) as
  ESPN sent them; plays and news, most of the size, are left out.
- `nba_engine/validate.py`: checks every box score before it is stored.
  Errors: negative stats, made > attempted, 3PM > FGM, more than 6 fouls,
  minutes below 0 or above 78, a player listed twice. Warnings: points not
  2·FGM + 3PM + FTM, rebounds not OREB + DREB, played without minutes,
  stats with 0 minutes, a DNP with stats, team points not the score, team
  minutes not 240 + 25 per overtime. Nothing is fixed or dropped: problems
  become flags on the row (`player_games.flags`) and lines in
  `nba.import_log`.
- `nba_engine/ingest.py`: a day = scoreboard, every game (final or not),
  and the box score of each final game not yet stored. One transaction per
  day, so a stopped load keeps what it finished. Only regular season,
  play-in and playoffs; preseason and All-Star games are skipped (logged).
  A box score that can't be read is logged as an error and the rest of the
  day still loads.
- Time rule: a game's rows become available at its final whistle. When we
  see a game final, that moment; for a game loaded later, tip-off + 4 hours
  (the safe side: a backtest waits longer, never less).
- Commands: `ingest` (yesterday and today, US Eastern), `backfill` (from
  2022-23; without `--from` it resumes from the last day a historical load
  finished), `report` (by season: games, rows, DNPs, flags, gaps, storage).
  Each run is recorded in `nba.pipeline_runs`.
- `.github/workflows/nba-data.yml`: the daily update every morning at
  11:00 UTC against the real database, and the historical load or the
  report by hand. The report goes to the run's summary. The daily run also
  keeps the free Supabase project from pausing.
- CI (`nba.yml`): migrations on Postgres 16, then the tests (now including
  database tests), `check`, and a live load of three days loaded twice (the
  second load must fetch nothing new).

## Tests

38 engine tests pass, 9 of them against Postgres with the server's
migrations (`tests/test_ingest.py`): ids, idempotency, a forced reload
giving the same rows, a broken box score, availability times, DNPs stored
as missing rather than zero, raw payloads round-trip, team changes, run
records and resume, the report. The server's 18 tests pass with V5 (H2).

## Trial load: the 2024-25 season (local Postgres)

| | |
| --- | --- |
| Time | 5.5 minutes (273 days, 0.2 s between requests) |
| Final games | 1,231 regular (1,230 + the NBA Cup final), 6 play-in, 84 playoffs |
| Final games without a box score | 0 |
| Player rows | 35,198 (6,850 did not play), 580 players |
| Team regular-season games | 82 each; OKC and MIL 83 (the Cup final, which doesn't count in the standings) |
| Errors | 0 |
| Warnings | 95: 83 rows played without minutes (end-of-bench players with all stats 0), 12 with 0 minutes and some stats |
| Postponed | 5 games, each also listed on its new date |
| Storage | about 28 MB a season, so 2022-23 to now is about 120 MB of the 500 MB |

The 95 flagged rows are 0.27% of the rows and are left out of model
training. No critical errors.

## Not yet done

- The load into Supabase: after the merge, run NBA data → backfill. It is
  expected to take about 25 minutes for four seasons at 0.5 s between
  requests. Then add its report here.
- Player matching for a second provider (name + team + birth date) waits
  until there is a second provider.

## Next: stage 2

Features with a time cut-off: rolling windows, per-minute rates, rest days,
back-to-backs, opponent and pace, all built only from games available
before each prediction time.
