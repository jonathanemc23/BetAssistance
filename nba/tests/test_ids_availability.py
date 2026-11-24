from datetime import datetime, timedelta, timezone

import numpy as np
import pytest

from conftest import FIXTURES
from nba_engine.availability import (QUESTIONABLE_PLAY_PROBABILITY, AvailabilityReport, adjust_minutes,
                                     latest_before)
from nba_engine.ids import UnknownTeam, game_id, new_player_id, team_id
from nba_engine.providers.espn import parse_scoreboard

T0 = datetime(2025, 11, 20, 18, 0, tzinfo=timezone.utc)


def test_espn_abbreviations_map_to_official_team_ids():
    assert team_id("GS") == "t_gsw" and team_id("UTAH") == "t_uta" and team_id("WSH") == "t_was"
    assert team_id("lal") == "t_lal"
    with pytest.raises(UnknownTeam):
        team_id("XYZ")


def test_every_espn_team_in_a_real_scoreboard_maps():
    for g in parse_scoreboard((FIXTURES / "espn_scoreboard_20251120.json").read_text()):
        team_id(g.home.abbreviation), team_id(g.away.abbreviation)


def test_game_id_uses_the_eastern_date_so_any_provider_agrees():
    # 00:00 UTC on Nov 21 is 7 pm Eastern on Nov 20.
    tip = datetime(2025, 11, 21, 0, 0, tzinfo=timezone.utc)
    assert game_id(tip, "LAC", "ORL") == "g_20251120_lac_orl"


def test_player_id_is_stable_and_opaque():
    a = new_player_id("espn", "4017837")
    assert a == new_player_id("espn", "4017837") and a.startswith("p_") and "4017837" not in a
    assert a != new_player_id("espn", "4017838")


def _r(status, minutes, **kw):
    return AvailabilityReport("p_1", "g_1", status, T0 + timedelta(minutes=minutes), **kw)


def test_the_latest_report_before_the_prediction_is_used_never_a_later_one():
    reports = [_r("questionable", 0), _r("available", 60), _r("out", 180)]
    assert latest_before(reports, "p_1", "g_1", T0 + timedelta(minutes=90)).status == "available"
    assert latest_before(reports, "p_1", "g_1", T0 - timedelta(minutes=1)) is None
    assert latest_before(reports, "p_2", "g_1", T0 + timedelta(hours=9)) is None


def test_reports_are_checked():
    with pytest.raises(ValueError):
        _r("doubtful", 0)
    with pytest.raises(ValueError):
        _r("restricted", 0)  # needs a cap
    with pytest.raises(ValueError):
        _r("questionable", 0, play_probability=1.5)


def test_minutes_follow_the_report():
    m = np.array([10.0, 24.0, 30.0, 36.0])
    assert adjust_minutes(m, None).play_probability == 1.0
    out = adjust_minutes(m, _r("out", 0))
    assert out.play_probability == 0.0 and out.minutes.size == 0
    q = adjust_minutes(m, _r("questionable", 0))
    assert q.play_probability == QUESTIONABLE_PLAY_PROBABILITY and np.array_equal(q.minutes, m)
    assert adjust_minutes(m, _r("questionable", 0, play_probability=0.8)).play_probability == 0.8
    capped = adjust_minutes(m, _r("restricted", 0, minutes_cap=25))
    assert capped.play_probability == 1.0 and capped.minutes.max() == 25 and capped.minutes.min() == 10
