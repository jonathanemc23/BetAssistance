"""Command line: python -m nba_engine <command>.

  check             settings, provider and database (schema nba) are reachable
  fetch --date D    read one day's games and box scores and print a summary
                    (no database writes; ingestion comes in stage 1)
"""
from __future__ import annotations

import argparse
import sys
from datetime import date, timedelta

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
        from .db import connect, missing_tables
        try:
            with connect(s.database_url) as conn:
                missing = missing_tables(conn)
            if missing:
                log.error("schema nba is missing tables %s: deploy the server so Flyway runs V4__nba.sql", missing)
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


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="nba_engine")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    f = sub.add_parser("fetch")
    f.add_argument("--date", type=date.fromisoformat, default=date.today() - timedelta(days=1))
    args = ap.parse_args(argv)
    s = Settings.from_env()
    log = setup(s.log_level)
    log.info("run %s", new_run_id(args.cmd))
    if args.cmd == "check":
        return cmd_check(s, log)
    return cmd_fetch(s, log, args.date)


if __name__ == "__main__":
    sys.exit(main())
