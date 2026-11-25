"""ESPN's public JSON feed (site.api.espn.com), the phase 1 source.

No key and no published licence: fine for development and personal
analysis, not for selling the data. Kept behind Provider so a licensed
source can replace it. The app already reads the same feed
(lib/data/fixtures.dart).
"""
from __future__ import annotations

import json
from datetime import date, datetime, timezone
from typing import Any, Callable

from .base import BoxScore, Fetched, Game, PlayerLine, Team, TeamLine

BASE = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba"

# ESPN's season types.
_SEASON_TYPES = {1: "preseason", 2: "regular", 3: "playoffs", 5: "play-in"}

_STATUS = {
    "STATUS_SCHEDULED": "scheduled",
    "STATUS_IN_PROGRESS": "live",
    "STATUS_HALFTIME": "live",
    "STATUS_END_PERIOD": "live",
    "STATUS_FINAL": "final",
    "STATUS_FINAL_OT": "final",
    "STATUS_POSTPONED": "postponed",
    "STATUS_CANCELED": "canceled",
    "STATUS_SUSPENDED": "postponed",
}

Getter = Callable[[str], str]


class ParseError(ValueError):
    """The response didn't have the shape we expect."""


def _now() -> datetime:
    return datetime.now(timezone.utc)


def parse_time(s: str) -> datetime:
    """ESPN dates: '2025-11-21T00:00Z' or with seconds."""
    s = s.replace("Z", "+00:00")
    return datetime.fromisoformat(s).astimezone(timezone.utc)


def _int(v: Any) -> int | None:
    if v is None:
        return None
    s = str(v).strip()
    if s in ("", "--", "-"):
        return None
    try:
        return int(s.lstrip("+"))
    except ValueError:
        return None


def _float(v: Any) -> float | None:
    if v is None:
        return None
    s = str(v).strip()
    if s in ("", "--", "-"):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _made_att(v: Any) -> tuple[int | None, int | None]:
    """'7-16' -> (7, 16)."""
    if v is None:
        return None, None
    parts = str(v).split("-")
    if len(parts) != 2:
        return None, None
    return _int(parts[0]), _int(parts[1])


def _status(node: dict) -> str:
    name = (node.get("type") or {}).get("name", "")
    if name in _STATUS:
        return _STATUS[name]
    state = (node.get("type") or {}).get("state")
    return {"pre": "scheduled", "in": "live", "post": "final"}.get(state, "other")


def _team(t: dict) -> Team:
    return Team(source_id=str(t["id"]), abbreviation=t.get("abbreviation", ""), name=t.get("displayName", ""))


def _game(game_id: str, season: dict, comp: dict, status_node: dict) -> Game:
    teams = {c["homeAway"]: c for c in comp.get("competitors", [])}
    if "home" not in teams or "away" not in teams:
        raise ParseError(f"game {game_id}: no home/away teams")
    status = _status(status_node)
    final = status == "final"
    return Game(
        source_id=str(game_id),
        season=int(season["year"]),
        season_type=_SEASON_TYPES.get(int(season.get("type", 0)), "other"),
        tipoff_at=parse_time(comp["date"]),
        status=status,
        home=_team(teams["home"]["team"]),
        away=_team(teams["away"]["team"]),
        home_score=_int(teams["home"].get("score")) if final else None,
        away_score=_int(teams["away"].get("score")) if final else None,
        neutral_site=bool(comp.get("neutralSite", False)),
    )


def parse_scoreboard(body: str) -> list[Game]:
    try:
        data = json.loads(body)
        out = []
        for e in data.get("events", []):
            comp = e["competitions"][0]
            out.append(_game(e["id"], e["season"], comp, e.get("status") or comp.get("status", {})))
        return out
    except (KeyError, IndexError, TypeError, json.JSONDecodeError) as err:
        raise ParseError(f"scoreboard: {err!r}") from err


def _player_line(a: dict, keys: list[str], team_id: str) -> PlayerLine:
    ath = a["athlete"]
    stats = a.get("stats") or []
    dnp = bool(a.get("didNotPlay")) or not stats
    base = dict(
        player_source_id=str(ath["id"]),
        name=ath.get("displayName", ""),
        position=(ath.get("position") or {}).get("abbreviation") or None,
        team_source_id=team_id,
        starter=bool(a.get("starter")),
        did_not_play=dnp,
        dnp_reason=(a.get("reason") or None) if dnp else None,
        ejected=bool(a.get("ejected")),
    )
    if dnp:
        return PlayerLine(**base)
    v = dict(zip(keys, stats))
    fgm, fga = _made_att(v.get("fieldGoalsMade-fieldGoalsAttempted"))
    tpm, tpa = _made_att(v.get("threePointFieldGoalsMade-threePointFieldGoalsAttempted"))
    ftm, fta = _made_att(v.get("freeThrowsMade-freeThrowsAttempted"))
    return PlayerLine(
        **base,
        minutes=_float(v.get("minutes")),
        points=_int(v.get("points")),
        rebounds=_int(v.get("rebounds")),
        oreb=_int(v.get("offensiveRebounds")),
        dreb=_int(v.get("defensiveRebounds")),
        assists=_int(v.get("assists")),
        fgm=fgm, fga=fga, tpm=tpm, tpa=tpa, ftm=ftm, fta=fta,
        turnovers=_int(v.get("turnovers")),
        steals=_int(v.get("steals")),
        blocks=_int(v.get("blocks")),
        fouls=_int(v.get("fouls")),
        plus_minus=_int(v.get("plusMinus")),
    )


def _team_line(t: dict) -> TeamLine:
    v = {s["name"]: s.get("displayValue") for s in t.get("statistics", [])}
    fgm, fga = _made_att(v.get("fieldGoalsMade-fieldGoalsAttempted"))
    tpm, tpa = _made_att(v.get("threePointFieldGoalsMade-threePointFieldGoalsAttempted"))
    ftm, fta = _made_att(v.get("freeThrowsMade-freeThrowsAttempted"))
    return TeamLine(
        team_source_id=str(t["team"]["id"]),
        rebounds=_int(v.get("totalRebounds")),
        oreb=_int(v.get("offensiveRebounds")),
        dreb=_int(v.get("defensiveRebounds")),
        assists=_int(v.get("assists")),
        fgm=fgm, fga=fga, tpm=tpm, tpa=tpa, ftm=ftm, fta=fta,
        # totalTurnovers includes team turnovers, which count for possessions.
        turnovers=_int(v.get("totalTurnovers", v.get("turnovers"))),
        steals=_int(v.get("steals")),
        blocks=_int(v.get("blocks")),
        fouls=_int(v.get("fouls")),
    )


def parse_summary(body: str) -> BoxScore:
    try:
        data = json.loads(body)
        header = data["header"]
        comp = header["competitions"][0]
        game = _game(header["id"], header["season"], comp, comp.get("status", {}))
        players: list[PlayerLine] = []
        for side in data.get("boxscore", {}).get("players", []):
            team_id = str(side["team"]["id"])
            for block in side.get("statistics", []):
                keys = block.get("keys") or []
                for a in block.get("athletes", []):
                    players.append(_player_line(a, keys, team_id))
        scores = {game.home.source_id: game.home_score, game.away.source_id: game.away_score}
        teams = []
        for t in data.get("boxscore", {}).get("teams", []):
            line = _team_line(t)
            teams.append(TeamLine(**{**line.__dict__, "points": scores.get(line.team_source_id)}))
        return BoxScore(game=game, players=players, teams=teams)
    except (KeyError, IndexError, TypeError, json.JSONDecodeError) as err:
        raise ParseError(f"summary: {err!r}") from err


class EspnProvider:
    name = "espn"

    def __init__(self, get: Getter):
        self._get = get

    def scoreboard(self, day: date) -> tuple[list[Game], Fetched]:
        url = f"{BASE}/scoreboard?dates={day:%Y%m%d}"
        body = self._get(url)
        fetched = Fetched(self.name, "scoreboard", day.isoformat(), url, body, _now())
        return parse_scoreboard(body), fetched

    def box_score(self, game_source_id: str) -> tuple[BoxScore, Fetched]:
        url = f"{BASE}/summary?event={game_source_id}"
        body = self._get(url)
        fetched = Fetched(self.name, "summary", str(game_source_id), url, body, _now())
        return parse_summary(body), fetched
