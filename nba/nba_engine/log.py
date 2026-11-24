"""Logging: one line per event, with the run id, readable in GitHub Actions."""
from __future__ import annotations

import logging
import sys
import uuid


def new_run_id(kind: str) -> str:
    return f"{kind}-{uuid.uuid4().hex[:12]}"


def setup(level: str = "INFO") -> logging.Logger:
    logger = logging.getLogger("nba")
    if not logger.handlers:
        h = logging.StreamHandler(sys.stderr)
        h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s", "%Y-%m-%dT%H:%M:%S"))
        logger.addHandler(h)
    logger.setLevel(level)
    return logger
