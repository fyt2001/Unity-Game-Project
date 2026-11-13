#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""LUA-LAYER: Lua module dependency direction (L2).

Rules live in lua_layers.json; existing violations live in
lua_layers.baseline.txt (only shrink, never grow). FW-GAME
(Framework must not require Game.*) is a hard zero-lock and ignores the
baseline. Requires are found after masking comments, so function-local
(lazy) requires and pcall(require, "x") are included.

Usage:
  python tools/lint/lua_layers.py <project_root> [--write-baseline]
Exit: 0 = no new violations, 1 = new violations / config error.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import lintlib  # noqa: E402

HERE = Path(__file__).resolve().parent
REQUIRE_RE = re.compile(
    r"""(?<![\w.])require\s*(?:\(\s*)?['"]([^'"]+)['"]"""
    r"""|pcall\s*\(\s*require\s*,\s*['"]([^'"]+)['"]"""
)


def package_of(module: str) -> str:
    parts = module.replace("/", ".").replace("\\", ".").split(".")
    if parts[0] == "Game" and len(parts) > 1:
        return "Game." + parts[1]
    return parts[0]


def src_module(rel_to_lua_root: str) -> str:
    return rel_to_lua_root[:-4].replace("/", ".") if rel_to_lua_root.endswith(".lua") else rel_to_lua_root


def has_prefix(name: str, prefixes) -> bool:
    return any(name == p or name.startswith(p + ".") for p in prefixes)


def collect(root: Path, cfg: dict):
    lua_root = root / cfg["lua_root"]
    edges = []   # (rel_path, line, src_mod, module)
    calls = []   # (rel_path, line, rule)
    if not lua_root.is_dir():
        return None, None, f"找不到目录: {lua_root}"
    call_res = [(r, re.compile(r["pattern"])) for r in cfg.get("call_rules", [])]
    for path in sorted(lua_root.rglob("*.lua")):
        text = lintlib.read_text(path)
        code = lintlib.mask_lua(text, strings=False)
        rel = path.relative_to(root).as_posix()
        mod = src_module(path.relative_to(lua_root).as_posix())
        for m in REQUIRE_RE.finditer(code):
            module = m.group(1) or m.group(2)
            edges.append((rel, lintlib.line_of(code, m.start()), mod, module.replace("/", ".")))
        nostr = lintlib.mask_lua(text, strings=True)
        for rule, rx in call_res:
            if not any(rel.startswith(p) for p in rule["paths_prefix"]):
                continue
            for m in rx.finditer(nostr):
                calls.append((rel, lintlib.line_of(nostr, m.start()), rule))
    return edges, calls, None


def reachable(graph, start, goal) -> bool:
    seen, stack = {start}, [start]
    while stack:
        cur = stack.pop()
        if cur == goal:
            return True
        for nxt in graph.get(cur, ()):
            if nxt not in seen:
                seen.add(nxt)
                stack.append(nxt)
    return False


def evaluate(root: Path, cfg: dict):
    edges, calls, err = collect(root, cfg)
    if err:
        return None, err
    hard, soft = [], []   # soft: (key, message)
    for rel, line, mod, module in edges:
        sp, dp = package_of(mod), package_of(module)
        for rule in cfg["rules"]:
            if not has_prefix(mod, rule["from"]) and sp not in rule["from"]:
                continue
            if has_prefix(mod, rule.get("except_from_prefix", [])):
                continue
            if not has_prefix(module, rule["to_prefix"]):
                continue
            msg = f"[LUA-LAYER/{rule['id']}] {rel}:{line} " + rule["message"].format(module=module, src_pkg=sp, dst_pkg=dp)
            key = f"{rule['id']}|{rel}|{module}"
            (soft if rule["baseline"] else hard).append((key, msg))

    cyc = set(cfg.get("cycle_packages", []))
    graph = defaultdict(set)
    for _, _, mod, module in edges:
        sp, dp = package_of(mod), package_of(module)
        if sp != dp and sp in cyc and dp in cyc:
            graph[sp].add(dp)
    for rel, line, mod, module in edges:
        sp, dp = package_of(mod), package_of(module)
        if sp != dp and sp in cyc and dp in cyc and reachable(graph, dp, sp):
            msg = f"[LUA-LAYER/CYCLE] {rel}:{line} " + cfg["cycle_message"].format(module=module, src_pkg=sp, dst_pkg=dp)
            soft.append((f"CYCLE|{rel}|{module}", msg))

    for rel, line, rule in calls:
        msg = f"[LUA-LAYER/{rule['id']}] {rel}:{line} " + rule["message"]
        key = f"{rule['id']}|{rel}|{rule['pattern']}"
        (soft if rule["baseline"] else hard).append((key, msg))
    return (hard, soft, len(edges)), None


def main() -> int:
    lintlib.configure_stdout()
    ap = argparse.ArgumentParser(description="Lua dependency direction gate")
    ap.add_argument("root", type=Path, help="Unity project root (My project)")
    ap.add_argument("--config", type=Path, default=HERE / "lua_layers.json")
    ap.add_argument("--baseline", type=Path, default=HERE / "lua_layers.baseline.txt")
    ap.add_argument("--write-baseline", action="store_true", help="rewrite baseline from current soft hits (hard rules are never written)")
    args = ap.parse_args()

    cfg = json.loads(lintlib.read_text(args.config))
    result, err = evaluate(args.root.resolve(), cfg)
    if err:
        print(f"[LUA-LAYER] {err}")
        return 1
    hard, soft, n_edges = result
    if args.write_baseline:
        lintlib.write_baseline(args.baseline, [
            "LUA-LAYER baseline: existing violations. Only delete lines, never add by hand.",
            "Format: RULE|file|module-or-pattern (no line numbers, so edits elsewhere do not churn).",
        ], [k for k, _ in soft])
        print(f"[LUA-LAYER] baseline written: {len(soft)} entries -> {args.baseline}")
    baseline = lintlib.load_baseline(args.baseline)
    new, used, stale = lintlib.split_new(soft, baseline)
    for _, msg in hard:
        print(msg)
    for msg in new:
        print(msg)
    for key in stale:
        print(f"[LUA-LAYER] 提示: baseline 里的 {key} 已不再出现，请从 {args.baseline.name} 删除这一行（只减不增）。")
    total_new = len(hard) + len(new)
    summary = f"requires={n_edges} hard={len(hard)} new={len(new)} baselined={used} stale={len(stale)}"
    if total_new:
        print(f"[LUA-LAYER] FAIL  {summary}")
        return 1
    print(f"[LUA-LAYER] PASS  {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
