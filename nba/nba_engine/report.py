"""What is in the database, by season: the import report.

Counts games, box scores, player rows and flagged rows, and looks for gaps
(final games without a box score, teams with too few or too many games),
so a load can be judged before anything is built on it.
"""
from __future__ import annotations

# Regular-season games per team. 82 for every season loaded (2022-23 on).
REGULAR_GAMES_PER_TEAM = 82


def season_report(conn) -> list[dict]:
    rows = conn.execute(
        """select g.season,
                  count(*) filter (where g.season_type = 'regular' and g.status = 'final') as regular,
                  count(*) filter (where g.season_type = 'play-in' and g.status = 'final') as play_in,
                  count(*) filter (where g.season_type = 'playoffs' and g.status = 'final') as playoffs,
                  count(*) filter (where g.status = 'final') as final,
                  count(*) filter (where g.status = 'final'
                                   and not exists (select 1 from nba.player_games p where p.game_id = g.game_id)) as no_box,
                  count(*) filter (where g.status in ('postponed', 'canceled')) as postponed
           from nba.games g group by g.season order by g.season""").fetchall()
    out = []
    for season, regular, play_in, playoffs, final, no_box, postponed in rows:
        p = conn.execute(
            """select count(*), count(*) filter (where pg.did_not_play),
                      count(*) filter (where pg.flags <> ''),
                      count(*) filter (where not pg.did_not_play and pg.minutes is null),
                      count(distinct pg.player_id)
               from nba.player_games pg join nba.games g on g.game_id = pg.game_id where g.season = %s""",
            (season,)).fetchone()
        teams = conn.execute(
            """select t, count(*) from (
                 select home_team_id t from nba.games where season = %s and season_type = 'regular' and status = 'final'
                 union all
                 select away_team_id from nba.games where season = %s and season_type = 'regular' and status = 'final'
               ) x group by t""", (season, season)).fetchall()
        counts = sorted(c for _, c in teams)
        out.append({
            "season": season, "regular": regular, "play_in": play_in, "playoffs": playoffs, "final": final,
            "final_without_box": no_box, "postponed_or_canceled": postponed,
            "player_rows": p[0], "dnp_rows": p[1], "flagged_rows": p[2], "played_without_minutes": p[3],
            "players": p[4], "teams": len(teams),
            "team_games_min": counts[0] if counts else 0, "team_games_max": counts[-1] if counts else 0,
        })
    return out


def flag_counts(conn) -> list[tuple[str, int]]:
    return conn.execute(
        """select f, count(*) from (
             select unnest(string_to_array(flags, ',')) f from nba.player_games where flags <> ''
           ) x group by f order by 2 desc""").fetchall()


def issue_counts(conn) -> list[tuple[str, int]]:
    return conn.execute("select level, count(*) from nba.import_log group by level order by level").fetchall()


def storage(conn) -> list[tuple[str, int]]:
    return conn.execute(
        """select c.relname, pg_total_relation_size(c.oid) from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'nba' and c.relkind = 'r' order by 2 desc""").fetchall()


def render(conn) -> str:
    lines = ["Final games by season. A postponed game is listed again on its new date.", "",
             "Season | Regular | Play-in | Playoffs | Final w/o box | Player rows | DNP | Flagged | Players | Team games (min-max)",
             "--- | --- | --- | --- | --- | --- | --- | --- | --- | ---"]
    problems = []
    for s in season_report(conn):
        lines.append(f"{s['season'] - 1}-{s['season'] % 100:02d} | {s['regular']} | {s['play_in']} | {s['playoffs']} | "
                     f"{s['final_without_box']} | {s['player_rows']} | {s['dnp_rows']} | {s['flagged_rows']} | "
                     f"{s['players']} | {s['team_games_min']}-{s['team_games_max']}")
        if s["final_without_box"]:
            problems.append(f"{s['season']}: {s['final_without_box']} final games without a box score")
        if s["played_without_minutes"]:
            problems.append(f"{s['season']}: {s['played_without_minutes']} rows played without minutes")
        if s["team_games_max"] > REGULAR_GAMES_PER_TEAM + 1:
            # The NBA Cup final is listed as a regular-season game but isn't one of the 82.
            problems.append(f"{s['season']}: a team has {s['team_games_max']} regular-season games (82, +1 for the Cup final)")
    lines += ["", "Flags: " + (", ".join(f"{f} {n}" for f, n in flag_counts(conn)) or "none"),
              "Import log: " + (", ".join(f"{lv} {n}" for lv, n in issue_counts(conn)) or "empty")]
    total = sum(n for _, n in storage(conn))
    lines.append(f"Storage (schema nba): {total / 1e6:.1f} MB")
    lines += ["", "Problems: " + ("; ".join(problems) if problems else "none")]
    return "\n".join(lines)
