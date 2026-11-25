"""Loading days of games: the historical load and the daily update.

A day is: the scoreboard (stored raw), every game on it (stored, final or
not), and for each final game not yet stored, its box score (stored raw,
checked, then written). Each day is its own transaction, so a stopped load
keeps every finished day and starts again where it left off.
"""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Callable

from . import ids, store
from .providers.base import Provider
from .providers.espn import ParseError
from .validate import check_box

log = logging.getLogger("nba.ingest")

# Games the engine learns from. Preseason and All-Star games (teams that
# aren't the 30) are left out.
SEASON_TYPES = ("regular", "play-in", "playoffs")


@dataclass
class DayResult:
    day: date
    games: int = 0
    final: int = 0
    loaded: int = 0          # box scores written this run
    skipped: int = 0         # already stored, or not an NBA game we keep
    player_rows: int = 0
    warnings: int = 0
    errors: int = 0
    notes: list[str] = field(default_factory=list)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def season_days(season: int) -> tuple[date, date]:
    """The calendar span searched for a season (named by the year it ends):
    1 October to 30 June, wide enough for every regular season and playoffs."""
    return date(season - 1, 10, 1), date(season, 6, 30)


def ingest_day(provider: Provider, conn, day: date, run_id: str, force: bool = False,
               now: Callable[[], datetime] = _now) -> DayResult:
    r = DayResult(day)
    src = provider.name

    def issue(level: str, key: str | None, msg: str) -> None:
        store.log_issue(conn, run_id, level, src, key, msg, now())
        if level == "warning":
            r.warnings += 1
        elif level == "error":
            r.errors += 1

    with conn.transaction():
        games, raw = provider.scoreboard(day)
        store.save_raw(conn, raw)
        for g in games:
            r.games += 1
            if g.season_type not in SEASON_TYPES:
                r.skipped += 1
                continue
            try:
                store.save_game(conn, src, g, raw.fetched_at, now())
            except ids.UnknownTeam as err:
                r.skipped += 1
                issue("info", g.source_id, f"not an NBA team: {err}")
                continue
            if g.status != "final":
                continue
            r.final += 1
            if not force and store.game_done(conn, src, g.source_id):
                r.skipped += 1
                continue
            try:
                box, braw = provider.box_score(g.source_id)
            except ParseError as err:
                issue("error", g.source_id, f"box score unreadable: {err}")
                continue
            store.save_raw(conn, braw)
            checked = check_box(box)
            for i in checked.issues:
                issue(i.level, g.source_id, i.message)
            if box.game.status != "final" or not box.players:
                issue("error", g.source_id, "box score not final or empty: not stored")
                continue
            r.player_rows += store.save_box(conn, src, box, checked.flags, braw.fetched_at, now())
            r.loaded += 1
    return r


def ingest_range(provider: Provider, connect: Callable, start: date, end: date, run_id: str, force: bool = False,
                 max_days: int | None = None, now: Callable[[], datetime] = _now,
                 kind: str = "ingest") -> list[DayResult]:
    """Loads start..end (inclusive), one transaction per day. Days in July,
    August and September (no NBA games) are skipped without a request."""
    out: list[DayResult] = []
    with connect() as conn:
        conn.autocommit = True  # each day commits in its own transaction
        store.start_run(conn, run_id, kind, now())
        status = "ok"
        try:
            day = start
            while day <= end:
                if max_days is not None and len(out) >= max_days:
                    log.info("stopping after %d days (max-days); run again to continue", max_days)
                    break
                if day.month not in (7, 8, 9):
                    r = ingest_day(provider, conn, day, run_id, force, now)
                    out.append(r)
                    if r.games:
                        log.info("%s: %d games, %d final, %d loaded, %d rows, %d warnings, %d errors",
                                 day, r.games, r.final, r.loaded, r.player_rows, r.warnings, r.errors)
                day += timedelta(days=1)
        except BaseException:
            status = "failed"
            raise
        finally:
            store.finish_run(conn, run_id, status, summarize(out, start, end), now())
    return out


def summarize(results: list[DayResult], start: date, end: date) -> dict:
    return {
        "from": start.isoformat(), "to": end.isoformat(),
        "last_day": results[-1].day.isoformat() if results else None,
        "days": len(results),
        **{k: sum(getattr(r, k) for r in results)
           for k in ("games", "final", "loaded", "skipped", "player_rows", "warnings", "errors")},
    }


def backfill_resume_day(conn) -> date | None:
    """The last day a historical load finished, from its runs' summaries
    (a daily update in between doesn't count: it only loads recent days)."""
    rows = conn.execute("select summary_json from nba.pipeline_runs where kind = 'backfill'").fetchall()
    days = [json.loads(r[0]).get("last_day") for r in rows]
    days = [date.fromisoformat(d) for d in days if d]
    return max(days) if days else None
