from dataclasses import replace

from conftest import FIXTURES
from nba_engine.providers.espn import parse_summary
from nba_engine.validate import check_box


def box(name="espn_summary_401810120.json"):
    return parse_summary((FIXTURES / name).read_text())


def test_real_box_scores_pass_every_check():
    for name in ("espn_summary_401810119.json", "espn_summary_401810120.json"):
        c = check_box(box(name))
        assert c.errors == [], c.issues
        assert c.flags == {}


def _with_player(b, i, **changes):
    players = list(b.players)
    players[i] = replace(players[i], **changes)
    return replace(b, players=players)


def _first_played(b):
    return next(i for i, p in enumerate(b.players) if not p.did_not_play)


def test_impossible_lines_are_flagged_not_dropped():
    b = box()
    i = _first_played(b)
    pid = b.players[i].player_source_id
    c = check_box(_with_player(b, i, minutes=90.0, fgm=9, fga=4))
    assert set(c.flags[pid]) == {"odd_minutes", "impossible", "points_mismatch"}
    assert len(c.errors) == 2


def test_missing_minutes_and_dnp_with_stats_are_warnings():
    b = box()
    i = _first_played(b)
    j = next(k for k, p in enumerate(b.players) if p.did_not_play)
    b = _with_player(_with_player(b, i, minutes=None), j, points=3)
    c = check_box(b)
    assert c.flags[b.players[i].player_source_id] == ["no_minutes"]
    assert c.flags[b.players[j].player_source_id] == ["dnp_with_stats"]
    assert c.errors == []


def test_a_player_listed_twice_is_an_error():
    b = box()
    i = _first_played(b)
    c = check_box(replace(b, players=list(b.players) + [b.players[i]]))
    assert "duplicate" in c.flags[b.players[i].player_source_id]


def test_points_that_dont_add_up_to_the_score_are_reported():
    b = box()
    c = check_box(replace(b, game=replace(b.game, home_score=(b.game.home_score or 0) + 2)))
    assert any("!= score" in i.message for i in c.issues)


def test_a_game_that_isnt_final_is_not_checked_as_one():
    b = box()
    c = check_box(replace(b, game=replace(b.game, status="live")))
    assert c.errors and "not final" in c.errors[0].message
