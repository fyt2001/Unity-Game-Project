# -*- coding: utf-8 -*-
"""Shared helpers for tools/lint scanners (no third-party deps, Python 3.8+).

Lexers blank out comments (and optionally string contents) while keeping
every newline, so line numbers in the masked text match the source file.
"""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path
from typing import Iterable

_LONG_OPEN = re.compile(r"\[(=*)\[")


def _blank(chunk: str) -> str:
    return "".join("\n" if c == "\n" else " " for c in chunk)


def mask_lua(text: str, strings: bool = False) -> str:
    """Return text with Lua comments (and strings if requested) replaced by spaces."""
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "-" and text.startswith("--", i):
            m = _LONG_OPEN.match(text, i + 2)
            if m:
                close = "]" + m.group(1) + "]"
                end = text.find(close, m.end())
                end = n if end < 0 else end + len(close)
            else:
                end = text.find("\n", i)
                end = n if end < 0 else end
            out.append(_blank(text[i:end]))
            i = end
            continue
        if c == "[":
            m = _LONG_OPEN.match(text, i)
            if m:
                close = "]" + m.group(1) + "]"
                end = text.find(close, m.end())
                end = n if end < 0 else end + len(close)
                chunk = text[i:end]
                out.append(chunk[:m.end() - i] + _blank(chunk[m.end() - i:]) if strings else chunk)
                i = end
                continue
        if c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            end = min(j + 1, n)
            chunk = text[i:end]
            out.append(c + _blank(chunk[1:-1]) + chunk[-1:] if strings and len(chunk) >= 2 else chunk)
            i = end
            continue
        out.append(c)
        i += 1
    return "".join(out)


def mask_cs(text: str, strings: bool = True) -> str:
    """Return text with C# comments (and string/char literal contents) blanked."""
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            out.append(_blank(text[i:end]))
            i = end
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            out.append(_blank(text[i:end]))
            i = end
            continue
        verbatim = text.startswith('@"', i) or text.startswith('$@"', i) or text.startswith('@$"', i)
        if verbatim or c == '"' or (c == "$" and text.startswith('$"', i)):
            q = text.index('"', i)
            j = q + 1
            while j < n:
                if verbatim and text.startswith('""', j):
                    j += 2
                    continue
                if not verbatim and text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"' or (not verbatim and text[j] == "\n"):
                    break
                j += 1
            end = min(j + 1, n)
            chunk = text[i:end]
            if strings:
                head = q - i + 1
                out.append(chunk[:head] + _blank(chunk[head:-1]) + chunk[-1:])
            else:
                out.append(chunk)
            i = end
            continue
        if c == "'":
            m = re.match(r"'(\\.[^']*|[^'\\\n])'", text[i:i + 12])
            if m:
                out.append("'" + _blank(m.group(0)[1:-1]) + "'" if strings else m.group(0))
                i += len(m.group(0))
                continue
        out.append(c)
        i += 1
    return "".join(out)


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def read_text(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    return data.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")


def norm_snippet(s: str) -> str:
    return " ".join(s.split())


def load_baseline(path: Path) -> Counter:
    counts: Counter = Counter()
    if not path.is_file():
        return counts
    for raw in read_text(path).split("\n"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        counts[line] += 1
    return counts


def write_baseline(path: Path, header: Iterable[str], keys: Iterable[str]) -> None:
    lines = ["# " + h for h in header] + sorted(keys)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def split_new(found: list[tuple[str, str]], baseline: Counter):
    """found: list of (key, message). Returns (new_messages, baselined_count, stale_keys)."""
    budget = Counter(baseline)
    new: list[str] = []
    used = 0
    for key, msg in found:
        if budget[key] > 0:
            budget[key] -= 1
            used += 1
        else:
            new.append(msg)
    stale = sorted(k for k, v in budget.items() for _ in range(v))
    return new, used, stale


def configure_stdout() -> None:
    import sys
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:  # noqa: BLE001 - very old Python; output still works
            pass
