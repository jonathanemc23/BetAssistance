"""Data providers. The engine depends on base.Provider only."""
from .base import BoxScore, Fetched, Game, PlayerLine, Provider, Team, TeamLine

__all__ = ["BoxScore", "Fetched", "Game", "PlayerLine", "Provider", "Team", "TeamLine", "make_provider"]


def make_provider(name: str, get):
    """The provider named in the settings (NBA_PROVIDER)."""
    if name == "espn":
        from .espn import EspnProvider
        return EspnProvider(get)
    raise ValueError(f"unknown provider: {name}")
