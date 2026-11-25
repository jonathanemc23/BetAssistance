"""Our own ids for teams, players and games, independent of any provider.

Models and predictions only ever see these. Each provider's ids are linked
to them in nba.external_ids, so a new provider is a new set of links, not a
new set of ids.

- Teams: t_<official NBA abbreviation>, e.g. t_gsw. Providers' own
  abbreviations (ESPN writes GS, NY, SA, NO, UTAH, WSH) are mapped here.
- Games: g_<YYYYMMDD of tip-off, US Eastern>_<away>_<home>, built from the
  facts of the game, so any provider gives the same id.
- Players: p_<10 hex>, made once when a player is first seen and then only
  looked up; a second provider links to the existing id (by provider id map,
  then name + team + birth date, then by hand).
"""
from __future__ import annotations

import hashlib
from datetime import datetime
from zoneinfo import ZoneInfo

EASTERN = ZoneInfo("America/New_York")

# The 30 teams by official abbreviation.
NBA_TEAMS = {
    "ATL", "BOS", "BKN", "CHA", "CHI", "CLE", "DAL", "DEN", "DET", "GSW",
    "HOU", "IND", "LAC", "LAL", "MEM", "MIA", "MIL", "MIN", "NOP", "NYK",
    "OKC", "ORL", "PHI", "PHX", "POR", "SAC", "SAS", "TOR", "UTA", "WAS",
}

# Providers' abbreviations that differ from the official ones.
ALIASES = {
    "GS": "GSW", "NY": "NYK", "SA": "SAS", "NO": "NOP", "UTAH": "UTA",
    "WSH": "WAS", "BRK": "BKN", "PHO": "PHX", "CHO": "CHA", "NOR": "NOP",
}


class UnknownTeam(ValueError):
    pass


def team_abbreviation(provider_abbr: str) -> str:
    a = provider_abbr.strip().upper()
    a = ALIASES.get(a, a)
    if a not in NBA_TEAMS:
        raise UnknownTeam(provider_abbr)
    return a


def team_id(provider_abbr: str) -> str:
    return "t_" + team_abbreviation(provider_abbr).lower()


def game_id(tipoff_utc: datetime, away_abbr: str, home_abbr: str) -> str:
    day = tipoff_utc.astimezone(EASTERN).strftime("%Y%m%d")
    return f"g_{day}_{team_abbreviation(away_abbr).lower()}_{team_abbreviation(home_abbr).lower()}"


def new_player_id(source: str, source_id: str) -> str:
    """A new player's id. Only made once; afterwards the id is looked up."""
    return "p_" + hashlib.sha1(f"{source}:{source_id}".encode()).hexdigest()[:10]
