"""The database: the server's Postgres, schema nba (backend/.../V4__nba.sql).

The schema belongs to the server's Flyway migrations; the engine never
creates or alters tables, it only checks they are there.
"""
from __future__ import annotations

from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

EXPECTED_TABLES = (
    "raw_payloads", "import_log", "teams", "players", "player_team_spells", "games",
    "player_games", "team_games", "features", "models", "predictions",
    "backtest_runs", "backtest_metrics", "pipeline_runs",
)


def normalize_url(url: str) -> str:
    """Accept Neon's postgresql://... or a JDBC address; psycopg wants the former."""
    if url.startswith("jdbc:"):
        url = url[len("jdbc:"):]
    p = urlparse(url)
    if p.scheme == "postgres":
        p = p._replace(scheme="postgresql")
    # Drop JDBC-only parameters psycopg doesn't know.
    q = [(k, v) for k, v in parse_qsl(p.query) if k not in ("channelBinding",)]
    return urlunparse(p._replace(query=urlencode(q)))


def connect(url: str):
    import psycopg
    return psycopg.connect(normalize_url(url), connect_timeout=30)


def missing_tables(conn) -> list[str]:
    with conn.cursor() as cur:
        cur.execute("select table_name from information_schema.tables where table_schema = 'nba'")
        have = {r[0] for r in cur.fetchall()}
    return [t for t in EXPECTED_TABLES if t not in have]
