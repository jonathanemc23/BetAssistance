"""What every NBA data provider hands the engine.

The engine only ever sees these types, so swapping ESPN for a licensed
provider means writing one new class, not touching the models.

Missing is not zero: a stat the provider didn't report is None; a stat
reported as 0 is 0. A player who didn't play has did_not_play=True and no
stats (all None).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Protocol


@dataclass(frozen=True)
class Team:
    source_id: str
    abbreviation: str
    name: str


@dataclass(frozen=True)
class Game:
    source_id: str
    season: int            # the year the season ends: 2026 = 2025-26
    season_type: str       # preseason, regular, playoffs, play-in, other
    tipoff_at: datetime    # UTC
    status: str            # scheduled, live, final, postponed, canceled
    home: Team
    away: Team
    home_score: int | None = None
    away_score: int | None = None
    neutral_site: bool = False


@dataclass(frozen=True)
class PlayerLine:
    """One player's box score line in one game."""
    player_source_id: str
    name: str
    position: str | None
    team_source_id: str
    starter: bool
    did_not_play: bool
    dnp_reason: str | None = None
    ejected: bool = False
    minutes: float | None = None
    points: int | None = None
    rebounds: int | None = None
    oreb: int | None = None
    dreb: int | None = None
    assists: int | None = None
    fgm: int | None = None
    fga: int | None = None
    tpm: int | None = None
    tpa: int | None = None
    ftm: int | None = None
    fta: int | None = None
    turnovers: int | None = None
    steals: int | None = None
    blocks: int | None = None
    fouls: int | None = None
    plus_minus: int | None = None


@dataclass(frozen=True)
class TeamLine:
    """A team's totals in one game."""
    team_source_id: str
    points: int | None = None
    rebounds: int | None = None
    oreb: int | None = None
    dreb: int | None = None
    assists: int | None = None
    fgm: int | None = None
    fga: int | None = None
    tpm: int | None = None
    tpa: int | None = None
    ftm: int | None = None
    fta: int | None = None
    turnovers: int | None = None
    steals: int | None = None
    blocks: int | None = None
    fouls: int | None = None


@dataclass(frozen=True)
class BoxScore:
    game: Game
    players: list[PlayerLine] = field(default_factory=list)
    teams: list[TeamLine] = field(default_factory=list)


@dataclass(frozen=True)
class Fetched:
    """A raw provider response, kept as it came (nba.raw_payloads)."""
    source: str
    kind: str
    source_key: str
    url: str
    body: str
    fetched_at: datetime


class Provider(Protocol):
    """A source of NBA games and box scores."""

    name: str

    def scoreboard(self, day: date) -> tuple[list[Game], Fetched]:
        """The games on a day (US Eastern calendar day, as the league counts it)."""
        ...

    def box_score(self, game_source_id: str) -> tuple[BoxScore, Fetched]:
        """One game's box score."""
        ...
