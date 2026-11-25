"""Checks on one game's box score before it is stored.

Nothing is corrected or dropped: a problem becomes a flag on the player's
row (nba.player_games.flags) and a line in nba.import_log, so models can
leave flagged rows out and anyone can see what was odd.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .providers.base import BoxScore, PlayerLine

# A regulation game is 48 minutes; each overtime adds 5. A player can't log
# more than the game's length (allow a little rounding).
MAX_MINUTES = 48 + 5 * 6


@dataclass
class Issue:
    level: str          # info, warning, error
    message: str
    player_source_id: str | None = None


@dataclass
class Checked:
    issues: list[Issue] = field(default_factory=list)
    # player source id -> flags for that player's row
    flags: dict[str, list[str]] = field(default_factory=dict)

    def flag(self, p: PlayerLine, name: str, level: str, message: str) -> None:
        self.flags.setdefault(p.player_source_id, []).append(name)
        self.issues.append(Issue(level, f"{p.name} ({p.player_source_id}): {message}", p.player_source_id))

    @property
    def errors(self) -> list[Issue]:
        return [i for i in self.issues if i.level == "error"]


def _made_att(p: PlayerLine, made: str, att: str, c: Checked) -> None:
    m, a = getattr(p, made), getattr(p, att)
    if m is not None and a is not None and m > a:
        c.flag(p, "impossible", "error", f"{made} {m} > {att} {a}")


def check_player(p: PlayerLine, c: Checked) -> None:
    if p.did_not_play:
        has = [k for k in ("minutes", "points", "rebounds", "assists") if getattr(p, k) is not None]
        if has:
            c.flag(p, "dnp_with_stats", "warning", f"did not play but has {', '.join(has)}")
        return
    if p.minutes is None:
        c.flag(p, "no_minutes", "warning", "played but minutes missing")
    elif p.minutes < 0 or p.minutes > MAX_MINUTES:
        c.flag(p, "odd_minutes", "error", f"minutes {p.minutes}")
    for k in ("points", "rebounds", "assists", "oreb", "dreb", "steals", "blocks", "turnovers", "fouls",
              "fgm", "fga", "tpm", "tpa", "ftm", "fta"):
        v = getattr(p, k)
        if v is not None and v < 0:
            c.flag(p, "impossible", "error", f"{k} {v} < 0")
    _made_att(p, "fgm", "fga", c)
    _made_att(p, "tpm", "tpa", c)
    _made_att(p, "ftm", "fta", c)
    if p.tpm is not None and p.fgm is not None and p.tpm > p.fgm:
        c.flag(p, "impossible", "error", f"3PM {p.tpm} > FGM {p.fgm}")
    if None not in (p.points, p.fgm, p.tpm, p.ftm) and p.points != 2 * p.fgm + p.tpm + p.ftm:
        c.flag(p, "points_mismatch", "warning", f"points {p.points} != 2*FGM+3PM+FTM {2 * p.fgm + p.tpm + p.ftm}")
    if None not in (p.rebounds, p.oreb, p.dreb) and p.rebounds != p.oreb + p.dreb:
        c.flag(p, "rebounds_mismatch", "warning", f"rebounds {p.rebounds} != OREB+DREB {p.oreb + p.dreb}")
    if p.fouls is not None and p.fouls > 6:
        c.flag(p, "impossible", "error", f"fouls {p.fouls} > 6")
    if p.minutes == 0 and any(getattr(p, k) for k in ("points", "rebounds", "assists")):
        c.flag(p, "stats_without_minutes", "warning", "0 minutes but has points, rebounds or assists")


def check_box(box: BoxScore) -> Checked:
    """All checks for one final game."""
    c = Checked()
    g = box.game
    if g.status != "final":
        c.issues.append(Issue("error", f"game {g.source_id} is {g.status}, not final"))
        return c
    seen: set[str] = set()
    for p in box.players:
        if p.player_source_id in seen:
            c.flag(p, "duplicate", "error", "listed twice in the box score")
        seen.add(p.player_source_id)
        check_player(p, c)
    for side in (g.home, g.away):
        rows = [p for p in box.players if p.team_source_id == side.source_id]
        played = [p for p in rows if not p.did_not_play]
        if len(played) < 5:
            c.issues.append(Issue("error", f"{side.abbreviation}: only {len(played)} players played"))
            continue
        score = g.home_score if side is g.home else g.away_score
        pts = [p.points for p in played]
        if score is not None and None not in pts and sum(pts) != score:
            c.issues.append(Issue("warning", f"{side.abbreviation}: players' points {sum(pts)} != score {score}"))
        mins = [p.minutes for p in played]
        if None not in mins:
            total = sum(mins)
            # 240 team minutes in regulation, +25 per overtime; ESPN rounds
            # each player's minutes, so allow a few either way.
            expected = 240 + 25 * max(0, round((total - 240) / 25))
            if abs(total - expected) > 6:
                c.issues.append(Issue("warning", f"{side.abbreviation}: team minutes {total:g}, expected about {expected}"))
    if len(box.teams) != 2:
        c.issues.append(Issue("warning", f"{len(box.teams)} team lines, expected 2"))
    return c
