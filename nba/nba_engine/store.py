"""Writes provider data into schema nba, under our own ids.

Every write is idempotent: running a day again replaces that day's games
with the same rows, so a load can stop and restart anywhere.
"""
from __future__ import annotations

import base64
import gzip
import hashlib
import json
from datetime import date, datetime, timedelta

from . import ids
from .providers.base import BoxScore, Fetched, Game, PlayerLine, Team, TeamLine

# When a past game's result became known, if we only fetched it later: the
# latest a game ends (tip-off + 4 hours). Later is the safe side: a backtest
# then waits longer before using the game, never less.
FINAL_AFTER_TIPOFF = timedelta(hours=4)

# The parts of an ESPN game summary the engine reads; the rest (plays,
# news, odds, ...) is most of the size and is not kept.
SUMMARY_KEEP = ("header", "boxscore", "gameInfo")


def trim_body(f: Fetched) -> str:
    """What is kept of a raw response: the whole of a scoreboard, the box
    score sections of a summary, as the provider sent them."""
    if f.kind != "summary":
        return f.body
    data = json.loads(f.body)
    return json.dumps({k: data[k] for k in SUMMARY_KEEP if k in data}, separators=(",", ":"), ensure_ascii=False)


def encode(text: str) -> str:
    return base64.b64encode(gzip.compress(text.encode(), 9, mtime=0)).decode()


def decode(body: str, encoding: str) -> str:
    if encoding == "identity":
        return body
    if encoding == "gzip+base64":
        return gzip.decompress(base64.b64decode(body)).decode()
    raise ValueError(f"unknown encoding {encoding!r}")


def save_raw(conn, f: Fetched) -> None:
    text = trim_body(f)
    digest = hashlib.sha256(text.encode()).hexdigest()
    conn.execute(
        """insert into nba.raw_payloads (source, kind, source_key, url, sha256, body, body_encoding, fetched_at)
           values (%s, %s, %s, %s, %s, %s, 'gzip+base64', %s)
           on conflict (source, kind, source_key, sha256) do nothing""",
        (f.source, f.kind, f.source_key, f.url, digest, encode(text), f.fetched_at))


def log_issue(conn, run_id: str, level: str, source: str, source_key: str | None, message: str, now: datetime) -> None:
    conn.execute(
        "insert into nba.import_log (run_id, level, source, source_key, message, created_at) values (%s, %s, %s, %s, %s, %s)",
        (run_id, level, source, source_key, message[:1000], now))


def _link(conn, entity: str, source: str, source_id: str) -> str | None:
    row = conn.execute(
        "select internal_id from nba.external_ids where entity = %s and source = %s and source_id = %s",
        (entity, source, source_id)).fetchone()
    return row[0] if row else None


def _add_link(conn, entity: str, source: str, source_id: str, internal_id: str, method: str, now: datetime) -> None:
    conn.execute(
        """insert into nba.external_ids (entity, source, source_id, internal_id, linked_at, link_method)
           values (%s, %s, %s, %s, %s, %s) on conflict do nothing""",
        (entity, source, source_id, internal_id, now, method))


def team_id(conn, source: str, t: Team, now: datetime) -> str:
    """Our id for a provider's team, creating the team the first time."""
    tid = _link(conn, "team", source, t.source_id)
    if tid:
        return tid
    tid = ids.team_id(t.abbreviation)
    conn.execute(
        """insert into nba.teams (team_id, abbreviation, name) values (%s, %s, %s)
           on conflict (team_id) do update set name = excluded.name""",
        (tid, ids.team_abbreviation(t.abbreviation), t.name))
    _add_link(conn, "team", source, t.source_id, tid, "exact", now)
    return tid


def player_id(conn, source: str, p: PlayerLine, day: date, now: datetime) -> str:
    """Our id for a provider's player, creating the player the first time.

    A second provider would match an existing player here (name + team +
    birth date) before creating one; with one provider, the link is all."""
    pid = _link(conn, "player", source, p.player_source_id)
    if pid is None:
        pid = ids.new_player_id(source, p.player_source_id)
        conn.execute(
            """insert into nba.players (player_id, name, position, first_seen, last_seen)
               values (%s, %s, %s, %s, %s) on conflict (player_id) do nothing""",
            (pid, p.name, p.position, day, day))
        _add_link(conn, "player", source, p.player_source_id, pid, "created", now)
    else:
        conn.execute(
            """update nba.players set
                 name = %s, position = coalesce(%s, position),
                 first_seen = least(first_seen, %s), last_seen = greatest(last_seen, %s)
               where player_id = %s""",
            (p.name, p.position, day, day, pid))
    return pid


def note_team(conn, pid: str, tid: str, day: date) -> None:
    """Keeps nba.player_team_spells: a new spell when a player shows up for
    another team. Days must come in order (the loaders go forward)."""
    open_ = conn.execute(
        "select team_id, from_date from nba.player_team_spells where player_id = %s and to_date is null",
        (pid,)).fetchone()
    if open_ and open_[0] == tid:
        return
    if open_ and day <= open_[1]:
        # A day before the open spell (a reload of the past): leave spells as they are.
        return
    if open_:
        conn.execute(
            "update nba.player_team_spells set to_date = %s where player_id = %s and team_id = %s and from_date = %s",
            (day - timedelta(days=1), pid, open_[0], open_[1]))
    conn.execute(
        "insert into nba.player_team_spells (player_id, team_id, from_date) values (%s, %s, %s) on conflict do nothing",
        (pid, tid, day))


def final_at(g: Game, fetched_at: datetime) -> datetime | None:
    if g.status != "final":
        return None
    return min(fetched_at, g.tipoff_at + FINAL_AFTER_TIPOFF)


def save_game(conn, source: str, g: Game, fetched_at: datetime, now: datetime) -> str:
    home, away = team_id(conn, source, g.home, now), team_id(conn, source, g.away, now)
    gid = _link(conn, "game", source, g.source_id) or ids.game_id(g.tipoff_at, g.away.abbreviation, g.home.abbreviation)
    fin = final_at(g, fetched_at)
    conn.execute(
        """insert into nba.games (game_id, season, season_type, home_team_id, away_team_id, tipoff_at, status,
                                  home_score, away_score, final_at, source, fetched_at)
           values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
           on conflict (game_id) do update set
             season = excluded.season, season_type = excluded.season_type, tipoff_at = excluded.tipoff_at,
             status = excluded.status, home_score = excluded.home_score, away_score = excluded.away_score,
             final_at = coalesce(nba.games.final_at, excluded.final_at),
             source = excluded.source, fetched_at = excluded.fetched_at""",
        (gid, g.season, g.season_type, home, away, g.tipoff_at, g.status, g.home_score, g.away_score, fin,
         source, fetched_at))
    _add_link(conn, "game", source, g.source_id, gid, "exact", now)
    return gid


def game_done(conn, source: str, game_source_id: str) -> bool:
    """Whether a game is final with its box score stored (nothing to fetch)."""
    row = conn.execute(
        """select 1 from nba.external_ids x join nba.games g on g.game_id = x.internal_id
           where x.entity = 'game' and x.source = %s and x.source_id = %s and g.status = 'final'
             and exists (select 1 from nba.player_games pg where pg.game_id = g.game_id)""",
        (source, game_source_id)).fetchone()
    return row is not None


def possessions(t: TeamLine) -> float | None:
    """The usual estimate: FGA + 0.44 FTA - OREB + TOV."""
    if None in (t.fga, t.fta, t.oreb, t.turnovers):
        return None
    return t.fga + 0.44 * t.fta - t.oreb + t.turnovers


_STATS = ("minutes", "points", "rebounds", "oreb", "dreb", "assists", "fgm", "fga", "tpm", "tpa", "ftm", "fta",
          "turnovers", "steals", "blocks", "fouls", "plus_minus")


def save_box(conn, source: str, box: BoxScore, flags: dict[str, list[str]], fetched_at: datetime, now: datetime) -> int:
    """Replaces a final game's player and team lines. Returns the player rows written."""
    g = box.game
    gid = save_game(conn, source, g, fetched_at, now)
    available = conn.execute("select final_at from nba.games where game_id = %s", (gid,)).fetchone()[0]
    day = g.tipoff_at.astimezone(ids.EASTERN).date()
    side = {g.home.source_id: (team_id(conn, source, g.home, now), team_id(conn, source, g.away, now), True),
            g.away.source_id: (team_id(conn, source, g.away, now), team_id(conn, source, g.home, now), False)}
    conn.execute("delete from nba.player_games where game_id = %s", (gid,))
    conn.execute("delete from nba.team_games where game_id = %s", (gid,))
    n = 0
    minutes_by_team: dict[str, float] = {}
    for p in box.players:
        if p.team_source_id not in side:
            continue
        tid, opp, home = side[p.team_source_id]
        pid = player_id(conn, source, p, day, now)
        note_team(conn, pid, tid, day)
        f = list(dict.fromkeys(flags.get(p.player_source_id, [])))
        if p.ejected:
            f.append("ejected")
        conn.execute(
            f"""insert into nba.player_games (game_id, player_id, team_id, opponent_id, home, starter, did_not_play,
                   dnp_reason, {", ".join(_STATS)}, flags, available_at, source, fetched_at)
                values (%s, %s, %s, %s, %s, %s, %s, %s, {", ".join(["%s"] * len(_STATS))}, %s, %s, %s, %s)
                on conflict (game_id, player_id) do nothing""",
            (gid, pid, tid, opp, home, p.starter, p.did_not_play, p.dnp_reason,
             *[getattr(p, k) for k in _STATS], ",".join(f), available, source, fetched_at))
        n += 1
        if p.minutes is not None:
            minutes_by_team[tid] = minutes_by_team.get(tid, 0.0) + p.minutes
    for t in box.teams:
        if t.team_source_id not in side:
            continue
        tid, opp, home = side[t.team_source_id]
        mins = minutes_by_team.get(tid)
        conn.execute(
            """insert into nba.team_games (game_id, team_id, opponent_id, home, minutes, points, rebounds, oreb, dreb,
                   assists, fgm, fga, tpm, tpa, ftm, fta, turnovers, possessions, available_at)
               values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (gid, tid, opp, home, round(mins / 5) if mins else None, t.points, t.rebounds, t.oreb, t.dreb,
             t.assists, t.fgm, t.fga, t.tpm, t.tpa, t.ftm, t.fta, t.turnovers, possessions(t), available))
    return n


def start_run(conn, run_id: str, kind: str, now: datetime) -> None:
    conn.execute("insert into nba.pipeline_runs (run_id, kind, started_at, status) values (%s, %s, %s, 'running')",
                 (run_id, kind, now))


def finish_run(conn, run_id: str, status: str, summary: dict, now: datetime) -> None:
    conn.execute("update nba.pipeline_runs set finished_at = %s, status = %s, summary_json = %s where run_id = %s",
                 (now, status, json.dumps(summary, sort_keys=True), run_id))
