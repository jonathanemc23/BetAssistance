"""Command line: python -m nba_engine <command>.

  check             settings, provider and database (schema nba) are reachable
  fetch --date D    read one day's games and box scores and print a summary
                    (no database writes)
  ingest [--date D] the daily update: yesterday and today (US Eastern), or one day
  backfill          the historical load from NBA_FIRST_SEASON (resumable:
                    [--from D] [--to D] [--max-days N] [--force])
  report            what the database holds, by season
"""
from __future__ import annotations

import argparse
import sys
from datetime import date, datetime, timedelta, timezone

from . import __version__
from .config import Settings
from .http import PoliteGetter
from .log import new_run_id, setup
from .providers import make_provider


def _provider(s: Settings):
    return make_provider(s.provider, PoliteGetter(s.request_pause, s.request_timeout, s.request_retries))


def cmd_check(s: Settings, log) -> int:
    log.info("nba_engine %s, provider %s, first season %d", __version__, s.provider, s.first_season)
    ok = True
    try:
        games, _ = _provider(s).scoreboard(date.today() - timedelta(days=1))
        log.info("provider ok: %d games yesterday", len(games))
    except Exception as err:  # noqa: BLE001 - report any failure
        log.error("provider failed: %s", err)
        ok = False
    if not s.database_url:
        log.warning("DATABASE_URL not set: database not checked")
    else:
        from .db import connect, missing_columns, missing_tables
        try:
            with connect(s.database_url) as conn:
                missing = missing_tables(conn) + missing_columns(conn)
            if missing:
                log.error("schema nba is missing %s: deploy the server so Flyway runs its migrations", missing)
                ok = False
            else:
                log.info("database ok: schema nba complete")
        except Exception as err:  # noqa: BLE001
            log.error("database failed: %s", err)
            ok = False
    return 0 if ok else 1


def cmd_fetch(s: Settings, log, day: date) -> int:
    p = _provider(s)
    games, _ = p.scoreboard(day)
    log.info("%s: %d games", day, len(games))
    for g in games:
        line = f"{g.away.abbreviation} @ {g.home.abbreviation} {g.status}"
        if g.status == "final":
            box, _ = p.box_score(g.source_id)
            played = sum(1 for pl in box.players if not pl.did_not_play)
            line += f" {g.away_score}-{g.home_score}, {played} players played, {len(box.players) - played} DNP"
        print(line)
    return 0


def _need_db(s: Settings, log) -> bool:
    if not s.database_url:
        log.error("DATABASE_URL is not set")
        return False
    return True


def _today_eastern() -> date:
    from .ids import EASTERN
    return datetime.now(timezone.utc).astimezone(EASTERN).date()


def _print_results(results) -> None:
    from .ingest import summarize
    if results:
        print(summarize(results, results[0].day, results[-1].day))


def cmd_ingest(s: Settings, log, run_id: str, day: date | None) -> int:
    if not _need_db(s, log):
        return 1
    from .db import connect
    from .ingest import ingest_range
    today = _today_eastern()
    start, end = (day, day) if day else (today - timedelta(days=1), today)
    results = ingest_range(_provider(s), lambda: connect(s.database_url), start, end, run_id)
    _print_results(results)
    # Data problems go to nba.import_log (see report); only a failed run fails the job.
    return 0


def cmd_backfill(s: Settings, log, run_id: str, start: date | None, end: date | None, max_days: int | None,
                 force: bool) -> int:
    if not _need_db(s, log):
        return 1
    from .db import connect
    from .ingest import ingest_range, season_days
    resume = start is None and not force
    start = start or season_days(s.first_season)[0]
    end = end or _today_eastern() - timedelta(days=1)
    if resume:
        # Without --from: start from the last day a historical load finished,
        # which is loaded again (cheap: stored games are skipped).
        from .ingest import backfill_resume_day
        with connect(s.database_url) as conn:
            last = backfill_resume_day(conn)
        if last and start < last <= end:
            log.info("resuming at %s (loaded up to there)", last)
            start = last
    results = ingest_range(_provider(s), lambda: connect(s.database_url), start, end, run_id, force, max_days,
                           kind="backfill")
    _print_results(results)
    # Errors are data problems, logged in nba.import_log and shown by report; the load itself went through.
    return 0


def cmd_report(s: Settings, log) -> int:
    if not _need_db(s, log):
        return 1
    from .db import connect
    from .report import render
    with connect(s.database_url) as conn:
        print(render(conn))
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="nba_engine")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    f = sub.add_parser("fetch")
    f.add_argument("--date", type=date.fromisoformat, default=date.today() - timedelta(days=1))
    i = sub.add_parser("ingest")
    i.add_argument("--date", type=date.fromisoformat)
    b = sub.add_parser("backfill")
    b.add_argument("--from", dest="start", type=date.fromisoformat)
    b.add_argument("--to", dest="end", type=date.fromisoformat)
    b.add_argument("--max-days", type=int)
    b.add_argument("--force", action="store_true", help="fetch box scores again even when stored")
    sub.add_parser("report")
    args = ap.parse_args(argv)
    s = Settings.from_env()
    log = setup(s.log_level)
    run_id = new_run_id(args.cmd)
    log.info("run %s", run_id)
    if args.cmd == "check":
        return cmd_check(s, log)
    if args.cmd == "ingest":
        return cmd_ingest(s, log, run_id, args.date)
    if args.cmd == "backfill":
        return cmd_backfill(s, log, run_id, args.start, args.end, args.max_days, args.force)
    if args.cmd == "report":
        return cmd_report(s, log)
    return cmd_fetch(s, log, args.date)


if __name__ == "__main__":
    sys.exit(main())
