"""Sliding-window rate limits, kept in memory: a restart forgets them,
which only ever lets a few more wakes through."""

from __future__ import annotations

import hashlib
import time
from collections import OrderedDict, deque


class Window:
    """At most [limit] hits per [seconds] for each key. Keys are hashed, so
    no push token is kept, and the oldest are dropped past [max_keys]."""

    def __init__(self, limit: int, seconds: float, *, max_keys: int = 100_000, clock=time.monotonic) -> None:
        self.limit = limit
        self.seconds = seconds
        self._max_keys = max_keys
        self._clock = clock
        self._hits: OrderedDict[str, deque] = OrderedDict()

    def allow(self, key: str) -> bool:
        digest = hashlib.sha256(key.encode()).hexdigest()[:32]
        now = self._clock()
        hits = self._hits.pop(digest, None) or deque()
        while hits and now - hits[0] >= self.seconds:
            hits.popleft()
        allowed = len(hits) < self.limit
        if allowed:
            hits.append(now)
        self._hits[digest] = hits
        while len(self._hits) > self._max_keys:
            self._hits.popitem(last=False)
        return allowed
