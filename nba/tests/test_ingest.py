"""Loading into a real Postgres with the server's migrations applied.

Runs when TEST_DATABASE_URL is set (CI sets it); the tables of schema nba
are emptied first, so never point it at a database whose data you need.
"""
import os
from datetime import date, datetime, timedelta, timezone

import pytest

from conftest import FIXTURES
from nba_engine import store
from nba_engine.ingest import backfill_resume_day, ingest_range
from nba_engine.providers.base import Fetched
from nba_engine.providers.espn import ParseError, parse_scoreboard, parse_summary
from nba_engine.report import render, season_report

URL = os.environ.get("TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not URL, reason="TEST_DATABASE_URL not set")

DAY = date(2025, 11, 20)
NOW = datetime(2026, 1, 1, tzinfo=timezone.utc)


class FakeEspn:
    """Real ESPN responses from tests/fixtures; game 401810121 has none and fails to parse."""
    name = "espn"

    def __init__(self):
        self.box_calls = []

    def scoreboard(self, day):
        body = (FIXTURES / "espn_scoreboard_20251120.json").read_text() if day == DAY else '{"events": []}'
        return parse_scoreboard(body), Fetched("espn", "scoreboard", day.isoformat(), "u", body, NOW)

    def box_score(self, gid):
        self.box_calls.append(gid)
        f = FIXTURES / f"espn_summary_{gid}.json"
        if not f.exists():
            raise ParseError("no fixture")
        body = f.read_text()
        return parse_summary(body), Fetched("espn", "summary", gid, "u", body, NOW)


def connect():
    import psycopg
    return psycopg.connect(URL)


@pytest.fixture(autouse=True)
def empty():
    with connect() as c:
        tables = [r[0] for r in c.execute(
            "select table_name from information_schema.tables where table_schema = 'nba'").fetchall()]
        c.execute("truncate " + ", ".join(f"nba.{t}" for t in tables) + " cascade")


_runs = iter(range(10**6))


def load(provider, start=DAY, end=DAY, **kw):
    return ingest_range(provider, connect, start, end, f"test-{next(_runs)}", now=lambda: NOW, **kw)


def q(sql, *args):
    with connect() as c:
        return c.execute(sql, args).fetchall()


def test_a_day_loads_games_players_and_team_lines_under_our_ids():
    r = load(FakeEspn())[0]
    assert (r.games, r.final, r.loaded, r.errors) == (3, 3, 2, 1)
    assert sorted(x[0] for x in q("select game_id from nba.games")) == [
        "g_20251120_lac_orl", "g_20251120_phi_mil", "g_20251120_sac_mem"]
    n = q("select count(*) from nba.player_games where game_id = 'g_20251120_sac_mem'")[0][0]
    assert n == len(parse_summary((FIXTURES / "espn_summary_401810120.json").read_text()).players)
    assert q("select count(*) from nba.team_games")[0][0] == 4
    # Provider ids only live in external_ids.
    assert q("select count(*) from nba.players where player_id not like 'p\\_%%'")[0][0] == 0
    assert q("select count(*) from nba.external_ids where entity = 'player'")[0][0] == q(
        "select count(*) from nba.players")[0][0]


def test_a_box_score_that_cant_be_read_is_logged_and_the_rest_still_loads():
    load(FakeEspn())
    log = q("select level, source_key, message from nba.import_log")
    assert ("error", "401810121") == log[0][:2] and "unreadable" in log[0][2]
    # Its game is kept, final but without a box score, and the report says so.
    assert season_report(connect())[0]["final_without_box"] == 1


def test_loading_again_fetches_nothing_and_changes_nothing():
    p = FakeEspn()
    load(p)
    before = q("select count(*), sum(coalesce(points, 0)) from nba.player_games")
    p.box_calls.clear()
    r = load(p)[0]
    assert p.box_calls == ["401810121"]  # only the one still missing
    assert r.loaded == 0
    assert q("select count(*), sum(coalesce(points, 0)) from nba.player_games") == before
    # The same responses are stored once.
    assert q("select count(*) from nba.raw_payloads")[0][0] == 3


def test_force_reloads_stored_games_with_the_same_rows():
    p = FakeEspn()
    load(p)
    before = q("select game_id, player_id, minutes, points from nba.player_games order by 1, 2")
    load(p, force=True)
    assert q("select game_id, player_id, minutes, points from nba.player_games order by 1, 2") == before


def test_rows_are_available_only_after_the_game_and_missing_is_not_zero():
    load(FakeEspn())
    tip, fin = q("select tipoff_at, final_at from nba.games where game_id = 'g_20251120_sac_mem'")[0]
    assert fin == tip + timedelta(hours=4)
    assert {r[0] for r in q("select available_at from nba.player_games where game_id = 'g_20251120_sac_mem'")} == {fin}
    dnp = q("select minutes, points, rebounds, assists from nba.player_games where did_not_play")
    assert dnp and all(row == (None, None, None, None) for row in dnp)


def test_raw_responses_are_kept_compressed_and_come_back_as_sent():
    load(FakeEspn())
    body, enc, sha = q("select body, body_encoding, sha256 from nba.raw_payloads where source_key = '401810120'")[0]
    assert enc == "gzip+base64"
    text = store.decode(body, enc)
    import hashlib
    import json
    assert hashlib.sha256(text.encode()).hexdigest() == sha
    original = json.loads((FIXTURES / "espn_summary_401810120.json").read_text())
    assert json.loads(text) == {k: original[k] for k in store.SUMMARY_KEEP if k in original}


def test_a_player_changing_teams_closes_one_spell_and_opens_another():
    load(FakeEspn())
    with connect() as c:
        pid = c.execute("select player_id from nba.player_games where team_id = 't_sac' limit 1").fetchone()[0]
        store.note_team(c, pid, "t_mem", DAY + timedelta(days=10))
        spells = c.execute("select team_id, from_date, to_date from nba.player_team_spells where player_id = %s"
                           " order by from_date", (pid,)).fetchall()
    assert spells == [("t_sac", DAY, DAY + timedelta(days=9)), ("t_mem", DAY + timedelta(days=10), None)]


def test_runs_are_recorded_and_the_historical_load_resumes_where_it_stopped():
    load(FakeEspn(), DAY - timedelta(days=2), DAY + timedelta(days=1), kind="backfill")
    load(FakeEspn(), DAY + timedelta(days=30), DAY + timedelta(days=31))  # a daily update
    runs = q("select kind, status from nba.pipeline_runs order by started_at, kind")
    assert sorted(runs) == [("backfill", "ok"), ("ingest", "ok")]
    with connect() as c:
        assert backfill_resume_day(c) == DAY + timedelta(days=1)


def test_the_report_counts_by_season():
    load(FakeEspn())
    text = render(connect())
    assert "2025-26 | 3 | 0 | 0 | 1 |" in text  # final games: 3 regular, 1 without a box score
    assert "final games without a box score" in text
