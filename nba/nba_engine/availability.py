"""Player availability entered by hand: available, questionable, out, or
restricted (a minutes cap). Stored insert-only in nba.player_availability.

A projection uses the latest report made before the prediction time, never a
later one, so backtests can replay exactly what was known.

How a report changes the minutes projection:

- out: the player won't play; P(plays) = 0 and no stat projection is made.
- questionable: P(plays) = the report's own probability, else the default
  (QUESTIONABLE_PLAY_PROBABILITY, to be calibrated on history once reports
  exist). The minutes and stats distributions are those *if he plays*; Over
  and Under are reported conditional on playing, with P(plays) shown beside
  them, since books usually void a prop when the player doesn't play.
- restricted: minutes above the cap are moved to the cap.
- a minutes cap on any other status is applied the same way.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Iterable

import numpy as np

STATUSES = ("available", "questionable", "out", "restricted")

# Prior for a questionable player playing, until history calibrates it.
QUESTIONABLE_PLAY_PROBABILITY = 0.5


@dataclass(frozen=True)
class AvailabilityReport:
    player_id: str
    game_id: str
    status: str
    reported_at: datetime
    minutes_cap: float | None = None
    play_probability: float | None = None
    id: int | None = None

    def __post_init__(self):
        if self.status not in STATUSES:
            raise ValueError(f"unknown status {self.status!r}")
        if self.minutes_cap is not None and not 0 <= self.minutes_cap <= 60:
            raise ValueError("minutes_cap must be between 0 and 60")
        if self.play_probability is not None and not 0 <= self.play_probability <= 1:
            raise ValueError("play_probability must be between 0 and 1")
        if self.status == "restricted" and self.minutes_cap is None:
            raise ValueError("a restricted player needs a minutes_cap")


def latest_before(reports: Iterable[AvailabilityReport], player_id: str, game_id: str,
                  as_of: datetime) -> AvailabilityReport | None:
    """The newest report for this player and game made at or before as_of."""
    best = None
    for r in reports:
        if r.player_id == player_id and r.game_id == game_id and r.reported_at <= as_of:
            if best is None or r.reported_at > best.reported_at:
                best = r
    return best


@dataclass(frozen=True)
class AdjustedMinutes:
    play_probability: float
    minutes: np.ndarray  # minutes samples if he plays (empty when out)


def adjust_minutes(samples: np.ndarray, report: AvailabilityReport | None) -> AdjustedMinutes:
    """Apply a report to simulated minutes (samples drawn assuming he plays)."""
    m = np.asarray(samples, dtype=float)
    if report is None or report.status == "available" and report.minutes_cap is None:
        return AdjustedMinutes(1.0, m)
    if report.status == "out":
        return AdjustedMinutes(0.0, np.empty(0))
    p = 1.0
    if report.status == "questionable":
        p = report.play_probability if report.play_probability is not None else QUESTIONABLE_PLAY_PROBABILITY
    if report.minutes_cap is not None:
        m = np.minimum(m, report.minutes_cap)
    return AdjustedMinutes(p, m)
