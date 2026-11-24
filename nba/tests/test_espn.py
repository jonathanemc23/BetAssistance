from datetime import date, datetime, timezone

import pytest

from conftest import FIXTURES
from nba_engine.providers.espn import EspnProvider, ParseError, parse_scoreboard, parse_summary

SUMMARY = (FIXTURES / "espn_summary_401810119.json").read_text()
SUMMARY_DNP = (FIXTURES / "espn_summary_401810120.json").read_text()
SCOREBOARD = (FIXTURES / "espn_scoreboard_20251120.json").read_text()


def test_scoreboard_reads_games_teams_and_finals():
    games = parse_scoreboard(SCOREBOARD)
    assert len(games) == 3
    g = games[0]
    assert g.source_id == "401810119"
    assert (g.away.abbreviation, g.home.abbreviation) == ("LAC", "ORL")
    assert g.status == "final" and g.season == 2026 and g.season_type == "regular"
    assert g.tipoff_at == datetime(2025, 11, 21, 0, 0, tzinfo=timezone.utc)
    assert (g.away_score, g.home_score) == (101, 129)


def test_summary_reads_every_player_with_full_line():
    box = parse_summary(SUMMARY)
    assert box.game.source_id == "401810119"
    zubac = next(p for p in box.players if p.name == "Ivica Zubac")
    assert zubac.team_source_id == "12" and zubac.starter and not zubac.did_not_play
    assert zubac.position == "C"
    assert (zubac.minutes, zubac.points, zubac.rebounds, zubac.oreb, zubac.dreb) == (32, 14, 19, 5, 14)
    assert (zubac.fgm, zubac.fga, zubac.tpm, zubac.tpa, zubac.ftm, zubac.fta) == (7, 16, 0, 0, 0, 0)
    assert zubac.assists == 0 and zubac.plus_minus == -8


@pytest.mark.parametrize("body", [SUMMARY, SUMMARY_DNP])
def test_rebounds_add_up_and_points_match_shots(body):
    box = parse_summary(body)
    for p in box.players:
        if p.did_not_play:
            continue
        assert p.oreb + p.dreb == p.rebounds, p.name
        assert 2 * (p.fgm - p.tpm) + 3 * p.tpm + p.ftm == p.points, p.name


def test_players_who_did_not_play_have_no_stats_not_zeros():
    box = parse_summary(SUMMARY_DNP)
    dnp = [p for p in box.players if p.did_not_play]
    assert {p.name for p in dnp} >= {"Doug McDermott", "Dario Saric", "Devin Carter"}
    for p in dnp:
        assert p.minutes is None and p.points is None and p.rebounds is None
        assert p.dnp_reason == "COACH'S DECISION"
    # ESPN puts a reason on players who did play too; it is dropped for them.
    assert all(p.dnp_reason is None for p in box.players if not p.did_not_play)


@pytest.mark.parametrize("body", [SUMMARY, SUMMARY_DNP])
def test_team_totals_match_the_sum_of_players(body):
    box = parse_summary(body)
    for t in box.teams:
        mine = [p for p in box.players if p.team_source_id == t.team_source_id and not p.did_not_play]
        assert sum(p.points for p in mine) == t.points
        assert sum(p.fga for p in mine) == t.fga
        assert sum(p.assists for p in mine) == t.assists


def test_a_broken_response_is_a_parse_error():
    with pytest.raises(ParseError):
        parse_summary('{"header": {}}')
    with pytest.raises(ParseError):
        parse_scoreboard("not json")


def test_provider_asks_the_right_urls():
    asked = []

    def get(url):
        asked.append(url)
        return SCOREBOARD if "scoreboard" in url else SUMMARY

    p = EspnProvider(get)
    games, raw = p.scoreboard(date(2025, 11, 20))
    box, raw2 = p.box_score(games[0].source_id)
    assert asked[0].endswith("/scoreboard?dates=20251120")
    assert asked[1].endswith("/summary?event=401810119")
    assert raw.kind == "scoreboard" and raw.body == SCOREBOARD and raw.source_key == "2025-11-20"
    assert raw2.kind == "summary" and box.game.home.abbreviation == "ORL"
