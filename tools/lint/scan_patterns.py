#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Anti-pattern scanner (L3 NO-FIND, L4 NO-SWALLOW, NO-PRINT, RES-MIX).

Rules: patterns.json. Accepted-by-design hits: allowlist.txt. Existing debt:
baseline.txt (only shrink). Comments are masked before matching, so a rule
mentioned in a comment does not count. L5 RUNTIME-NO-EDITOR stays in
runtime_no_editor.py as a hard zero-lock (no baseline) and is run by
run_gate.ps1 / verify.ps1.

Usage:
  python tools/lint/scan_patterns.py <project_root> [--write-baseline] [--json out.json]
Exit: 0 = no new hits, 1 = new hits / config error.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import lintlib  # noqa: E402

HERE = Path(__file__).resolve().parent
EXT_LANG = {".cs": "cs", ".lua": "lua"}


def glob_match(rel: str, pattern: str) -> bool:
    if "**/" in pattern:
        head, tail = pattern.split("**/", 1)
        return rel.startswith(head) and (fnmatch.fnmatchcase(rel[len(head):], tail)
                                         or fnmatch.fnmatchcase(rel[len(head):], "*/" + tail)
                                         or fnmatch.fnmatchcase(rel.rsplit("/", 1)[-1], tail))
    return fnmatch.fnmatchcase(rel, pattern)


def load_allowlist(path: Path):
    entries = []
    if not path.is_file():
        return entries
    for raw in lintlib.read_text(path).split("\n"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|", 2)]
        while len(parts) < 3:
            parts.append("")
        entries.append(tuple(parts))
    return entries


def candidate_files(root: Path, rules):
    seen = {}
    for base in ("Assets/Game/Scripts", "Assets/Game/LuaScripts"):
        d = root / base
        if d.is_dir():
            for p in sorted(d.rglob("*")):
                if p.is_file() and p.suffix in EXT_LANG:
                    seen[p.relative_to(root).as_posix()] = p
    return seen


def scan(root: Path, cfg: dict, allow):
    rules = cfg["rules"]
    compiled = [(r, re.compile(r["pattern"], re.MULTILINE)) for r in rules]
    hits = []        # (rule_id, rel, line, src_line)
    allowed = Counter()
    files = candidate_files(root, rules)
    for rel, path in files.items():
        lang = EXT_LANG[path.suffix]
        text = lintlib.read_text(path)
        src_lines = text.split("\n")
        masked = {}
        for rule, rx in compiled:
            if lang not in rule["langs"] or not any(glob_match(rel, g) for g in rule["include"]):
                continue
            key = (lang, rule.get("strings", True))
            if key not in masked:
                masked[key] = lintlib.mask_cs(text, key[1]) if lang == "cs" else lintlib.mask_lua(text, key[1])
            code = masked[key]
            seen_lines = set()
            for m in rx.finditer(code):
                line = lintlib.line_of(code, m.start())
                if not rule.get("multiline") and line in seen_lines:
                    continue
                seen_lines.add(line)
                src = src_lines[line - 1] if line - 1 < len(src_lines) else ""
                ok = any(a_rule == rule["id"] and glob_match(rel, a_glob) and (not a_sub or a_sub in src)
                         for a_rule, a_glob, a_sub in allow)
                if ok:
                    allowed[rule["id"]] += 1
                    continue
                hits.append((rule["id"], rel, line, src))
    return hits, allowed, len(files)


def main() -> int:
    lintlib.configure_stdout()
    ap = argparse.ArgumentParser(description="anti-pattern scanner")
    ap.add_argument("root", type=Path)
    ap.add_argument("--config", type=Path, default=HERE / "patterns.json")
    ap.add_argument("--allowlist", type=Path, default=HERE / "allowlist.txt")
    ap.add_argument("--baseline", type=Path, default=HERE / "baseline.txt")
    ap.add_argument("--write-baseline", action="store_true")
    ap.add_argument("--json", type=Path, help="write machine-readable result here")
    args = ap.parse_args()

    cfg = json.loads(lintlib.read_text(args.config))
    msgs = {r["id"]: r["message"] for r in cfg["rules"]}
    hits, allowed, n_files = scan(args.root.resolve(), cfg, load_allowlist(args.allowlist))
    found = [(f"{rid}|{rel}|{lintlib.norm_snippet(src)}",
              f"[{rid}] {rel}:{line} {msgs[rid]}\n    > {src.strip()[:160]}") for rid, rel, line, src in hits]
    if args.write_baseline:
        lintlib.write_baseline(args.baseline, [
            "scan_patterns baseline: existing debt. Only delete lines, never add by hand.",
            "Format: RULE|file|normalized source line (no line numbers).",
        ], [k for k, _ in found])
        print(f"[SCAN] baseline written: {len(found)} entries -> {args.baseline}")
    baseline = lintlib.load_baseline(args.baseline)
    new, used, stale = lintlib.split_new(found, baseline)

    per_rule = Counter(h[0] for h in hits)
    new_keys = Counter(k.split("|", 1)[0] for k, m in found if m in new)
    for msg in new:
        print(msg)
    for key in stale:
        print(f"[SCAN] 提示: baseline 里的这一行已不再命中，请从 {args.baseline.name} 删除（只减不增）：{key[:200]}")
    for r in cfg["rules"]:
        rid = r["id"]
        print(f"[SCAN] {rid:<11} hits={per_rule[rid]} new={new_keys[rid]} allowlisted={allowed[rid]}")
    summary = f"files={n_files} hits={len(hits)} new={len(new)} baselined={used} stale={len(stale)}"
    if args.json:
        args.json.write_text(json.dumps({
            "pass": not new, "files": n_files, "new": len(new), "baselined": used, "stale": stale,
            "per_rule": {r["id"]: {"hits": per_rule[r["id"]], "new": new_keys[r["id"]], "allowlisted": allowed[r["id"]]} for r in cfg["rules"]},
            "new_messages": new,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
    if new:
        print(f"[SCAN] FAIL  {summary}")
        return 1
    print(f"[SCAN] PASS  {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
