"""Stop sequences for text completions (OpenAI/Anthropic/Responses).

Matching is incremental and Unicode-safe.  A prefix that could become a stop
sequence is withheld until it can be released or a complete stop is observed;
therefore no part of a stop sequence leaks into a streamed response.
"""
from __future__ import annotations

MAX_STOPS = 16
MAX_STOP_CHARS = 256
MAX_TOTAL_CHARS = 2048


def validate_stops(value, *, parameter: str = "stop") -> list[str]:
    """Normalize absent/string/array stops; fail on malformed or oversized values."""
    if value is None:
        return []
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list) or len(value) > MAX_STOPS:
        raise ValueError(f"{parameter}: expected a string or a list of at most {MAX_STOPS} strings")
    if any(not isinstance(s, str) or not s or len(s) > MAX_STOP_CHARS for s in value):
        raise ValueError(f"{parameter}: each stop must be a nonempty string of at most {MAX_STOP_CHARS} characters")
    if sum(map(len, value)) > MAX_TOTAL_CHARS:
        raise ValueError(f"{parameter}: total stop length exceeds {MAX_TOTAL_CHARS} characters")
    if len(value) != len(set(value)):
        raise ValueError(f"{parameter}: duplicate stop sequences are not allowed")
    return list(value)


class StopMatcher:
    """Consume text fragments; return (safe_text, matched_stop_or_None)."""

    def __init__(self, stops: list[str]):
        self.stops = tuple(stops)
        self.pending = ""
        self.matched: str | None = None
        self.prefixes: dict[int, set[str]] = {}
        for stop in self.stops:
            for size in range(1, len(stop)):
                self.prefixes.setdefault(size, set()).add(stop[:size])
        self.prefix_lengths = sorted(self.prefixes, reverse=True)

    def feed(self, text: str) -> tuple[str, str | None]:
        if self.matched is not None:
            return "", self.matched
        if not text:
            return "", None
        if not self.stops:
            return text, None
        self.pending += text
        matches = [(self.pending.find(s), i, s) for i, s in enumerate(self.stops) if s in self.pending]
        if matches:
            pos, _, stop = min(matches)
            safe = self.pending[:pos]
            self.pending = ""
            self.matched = stop
            return safe, stop
        # Keep only a suffix which could begin a sequence in a later fragment.
        keep = next((size for size in self.prefix_lengths if size <= len(self.pending)
                     and self.pending[-size:] in self.prefixes[size]), 0)
        if keep:
            safe, self.pending = self.pending[:-keep], self.pending[-keep:]
        else:
            safe, self.pending = self.pending, ""
        return safe, None

    def flush(self) -> str:
        """A logical content boundary or natural end cannot extend a partial stop."""
        text, self.pending = self.pending, ""
        return text if self.matched is None else ""
