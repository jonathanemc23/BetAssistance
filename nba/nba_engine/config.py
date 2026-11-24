"""Settings, from environment variables with safe defaults.

Nothing secret lives in the code: DATABASE_URL comes from the environment
(a GitHub secret in CI), as for the server.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from datetime import date


@dataclass(frozen=True)
class Settings:
    database_url: str | None = None
    provider: str = "espn"
    # First season loaded: 2023 = 2022-23 (seasons are named by the year they end).
    first_season: int = 2023
    # Seconds between requests to the provider, to stay polite.
    request_pause: float = 0.5
    request_timeout: float = 20.0
    request_retries: int = 4
    log_level: str = "INFO"
    # Markets the engine projects in phase 1.
    markets: tuple[str, ...] = field(default=("minutes", "points", "rebounds", "assists"))

    @staticmethod
    def from_env(env: dict[str, str] | None = None) -> "Settings":
        e = os.environ if env is None else env
        return Settings(
            database_url=e.get("DATABASE_URL") or None,
            provider=e.get("NBA_PROVIDER", "espn"),
            first_season=int(e.get("NBA_FIRST_SEASON", "2023")),
            request_pause=float(e.get("NBA_REQUEST_PAUSE", "0.5")),
            request_timeout=float(e.get("NBA_REQUEST_TIMEOUT", "20")),
            request_retries=int(e.get("NBA_REQUEST_RETRIES", "4")),
            log_level=e.get("NBA_LOG_LEVEL", "INFO").upper(),
        )


def season_of(day: date) -> int:
    """The season a day belongs to: October onwards counts toward next year's season."""
    return day.year + 1 if day.month >= 8 else day.year
