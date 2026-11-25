from datetime import date

import pytest
import requests

from nba_engine.config import Settings, season_of
from nba_engine.db import EXPECTED_TABLES, normalize_url
from nba_engine.http import FetchError, PoliteGetter
from nba_engine.providers import make_provider


def test_settings_from_env_and_defaults():
    s = Settings.from_env({})
    assert s.provider == "espn" and s.first_season == 2023 and s.database_url is None
    s = Settings.from_env({"DATABASE_URL": "postgresql://x", "NBA_FIRST_SEASON": "2024", "NBA_LOG_LEVEL": "debug"})
    assert s.database_url == "postgresql://x" and s.first_season == 2024 and s.log_level == "DEBUG"


def test_season_is_named_by_the_year_it_ends():
    assert season_of(date(2025, 10, 21)) == 2026
    assert season_of(date(2026, 4, 12)) == 2026
    assert season_of(date(2026, 6, 15)) == 2026


def test_database_url_accepts_neon_and_jdbc_forms():
    assert normalize_url("postgres://u:p@h/db?sslmode=require") == "postgresql://u:p@h/db?sslmode=require"
    assert normalize_url("jdbc:postgresql://h/db?sslmode=require&channelBinding=require") == "postgresql://h/db?sslmode=require"


def test_unknown_provider_is_refused():
    with pytest.raises(ValueError):
        make_provider("nope", lambda u: "")


class _Resp:
    def __init__(self, code, text=""):
        self.status_code, self.text = code, text


class _Session:
    def __init__(self, answers):
        self.answers, self.headers, self.urls = list(answers), {}, []

    def get(self, url, timeout):
        self.urls.append(url)
        a = self.answers.pop(0)
        if isinstance(a, Exception):
            raise a
        return a


def test_getter_retries_busy_answers_and_network_errors():
    s = _Session([_Resp(503), requests.ConnectionError("reset"), _Resp(200, "ok")])
    slept = []
    g = PoliteGetter(pause=0, retries=3, session=s, sleep=slept.append, clock=lambda: 0.0)
    assert g("http://x") == "ok"
    assert len(s.urls) == 3 and slept == [1.0, 2.0]
    assert "nba-engine" in s.headers["User-Agent"]


def test_getter_stops_on_a_not_found_and_after_its_retries():
    g = PoliteGetter(pause=0, retries=3, session=_Session([_Resp(404)]), sleep=lambda s: None, clock=lambda: 0.0)
    with pytest.raises(FetchError):
        g("http://x")
    g = PoliteGetter(pause=0, retries=1, session=_Session([_Resp(500), _Resp(500)]), sleep=lambda s: None, clock=lambda: 0.0)
    with pytest.raises(FetchError):
        g("http://x")


def test_expected_tables_match_the_migration():
    from pathlib import Path
    sql = (Path(__file__).resolve().parents[2] / "backend/src/main/resources/db/migration/V4__nba.sql").read_text()
    for t in EXPECTED_TABLES:
        assert f"create table nba.{t} (" in sql, t
