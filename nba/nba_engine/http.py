"""HTTP GET with a pause between requests and retries with backoff."""
from __future__ import annotations

import logging
import time

import requests

log = logging.getLogger("nba.http")

# A generic client name: no personal details go to outside services.
USER_AGENT = "nba-engine/0.1 (statistics research)"


class FetchError(RuntimeError):
    pass


class PoliteGetter:
    def __init__(self, pause: float = 0.5, timeout: float = 20.0, retries: int = 4, session: requests.Session | None = None,
                 sleep=time.sleep, clock=time.monotonic):
        self.pause, self.timeout, self.retries = pause, timeout, retries
        self.session = session or requests.Session()
        self.session.headers["User-Agent"] = USER_AGENT
        self._sleep, self._clock = sleep, clock
        self._last = 0.0

    def __call__(self, url: str) -> str:
        last_error: Exception | None = None
        for attempt in range(self.retries + 1):
            wait = self.pause - (self._clock() - self._last)
            if wait > 0:
                self._sleep(wait)
            self._last = self._clock()
            try:
                r = self.session.get(url, timeout=self.timeout)
                if r.status_code == 200:
                    return r.text
                if r.status_code not in (429, 500, 502, 503, 504):
                    raise FetchError(f"{url}: HTTP {r.status_code}")
                last_error = FetchError(f"{url}: HTTP {r.status_code}")
            except requests.RequestException as err:
                last_error = err
            backoff = min(60.0, 2.0 ** attempt)
            log.warning("retry %d for %s in %.0fs: %s", attempt + 1, url, backoff, last_error)
            self._sleep(backoff)
        raise FetchError(f"{url}: gave up after {self.retries + 1} tries: {last_error}")
