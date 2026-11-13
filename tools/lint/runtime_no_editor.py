#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""RUNTIME-NO-EDITOR（零规则锁）：运行时 C# 在 UNITY_EDITOR=false 时不得引用 UnityEditor。

按「玩家构建」语义求值预处理：UNITY_EDITOR=false，其它宏按真值处理（尽量多纳入非 Editor 分支）。
不扫描 Assets/Editor、任何名为 Editor 的目录、以及 Assets/XLua。
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DIRECTIVE_RE = re.compile(r"^\s*#\s*(if|elif|else|endif)\b(.*)$")
UNITYEDITOR_RE = re.compile(r"\bUnityEditor\b")
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

SKIP_DIR_NAMES = {"Editor", "editor"}
# 只扫游戏运行时脚本，避开第三方与生成代码
SCAN_ROOTS = [
    Path("Assets") / "Game" / "Scripts",
]

FIX = (
    "[RUNTIME-NO-EDITOR] {path}:{line} 在运行时代码中使用 UnityEditor 而未包 #if UNITY_EDITOR，"
    "player 构建会编译失败。请把 Editor 逻辑移到 Assets/Editor，"
    "或用 #if UNITY_EDITOR ... #endif 包住 using 和调用。"
)


def tokenize_expr(expr: str) -> list[str]:
    expr = expr.replace("&&", " & ").replace("||", " | ").replace("!", " ! ")
    tokens: list[str] = []
    buf = []
    for ch in expr:
        if ch in "()&|!":
            if buf:
                tokens.append("".join(buf).strip())
                buf = []
            tokens.append(ch)
        else:
            buf.append(ch)
    if buf:
        tokens.append("".join(buf).strip())
    return [t for t in tokens if t]


def eval_defined(name: str) -> bool:
    if name == "UNITY_EDITOR":
        return False
    # 其它符号取真，使「UNITY_EDITOR || FOO」这类分支被纳入扫描
    return True


def parse_prim(tokens: list[str], i: int):
    if i >= len(tokens):
        return True, i
    t = tokens[i]
    if t == "!":
        val, i = parse_prim(tokens, i + 1)
        return (not val), i
    if t == "(":
        val, i = parse_or(tokens, i + 1)
        if i < len(tokens) and tokens[i] == ")":
            i += 1
        return val, i
    i += 1
    ident = IDENT_RE.findall(t)
    if not ident:
        return True, i
    return eval_defined(ident[0]), i


def parse_and(tokens: list[str], i: int):
    val, i = parse_prim(tokens, i)
    while i < len(tokens) and tokens[i] == "&":
        rhs, i = parse_prim(tokens, i + 1)
        val = val and rhs
    return val, i


def parse_or(tokens: list[str], i: int):
    val, i = parse_and(tokens, i)
    while i < len(tokens) and tokens[i] == "|":
        rhs, i = parse_and(tokens, i + 1)
        val = val or rhs
    return val, i


def eval_expr(expr: str) -> bool:
    tokens = tokenize_expr(expr.strip())
    if not tokens:
        return True
    val, _ = parse_or(tokens, 0)
    return val


def iter_runtime_cs(root: Path):
    for rel in SCAN_ROOTS:
        base = root / rel
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.cs")):
            if any(part in SKIP_DIR_NAMES for part in path.parts):
                continue
            yield path


def scan_file(path: Path, root: Path) -> list[str]:
    """stack item: {taken_current, taken_any, active} for one #if group."""
    hits: list[str] = []
    rel = path.relative_to(root).as_posix()
    # A stack of frames for nested #if. Each frame:
    #   parent_active, branch_active, any_taken
    stack: list[tuple[bool, bool, bool]] = []

    def active() -> bool:
        return all(frame[1] for frame in stack) if stack else True

    for lineno, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        m = DIRECTIVE_RE.match(raw)
        if m:
            kind, rest = m.group(1), m.group(2)
            if kind == "if":
                parent = active()
                taken = parent and eval_expr(rest)
                stack.append((parent, taken, taken))
            elif kind == "elif":
                if not stack:
                    continue
                parent, _cur, any_taken = stack[-1]
                taken = parent and (not any_taken) and eval_expr(rest)
                stack[-1] = (parent, taken, any_taken or taken)
            elif kind == "else":
                if not stack:
                    continue
                parent, _cur, any_taken = stack[-1]
                taken = parent and (not any_taken)
                stack[-1] = (parent, taken, True)
            elif kind == "endif":
                if stack:
                    stack.pop()
            continue
        if active() and UNITYEDITOR_RE.search(raw):
            # 跳过注释里的提及（粗略）
            stripped = raw.strip()
            if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*"):
                continue
            hits.append(FIX.format(path=rel, line=lineno))
    return hits


def scan_tree(root: Path) -> list[str]:
    hits: list[str] = []
    found = False
    for path in iter_runtime_cs(root):
        found = True
        hits.extend(scan_file(path, root))
    if not found:
        print(f"[RUNTIME-NO-EDITOR] 未找到运行时脚本目录: {root / SCAN_ROOTS[0]}", file=sys.stderr)
        return [f"missing:{root / SCAN_ROOTS[0]}"]
    return hits


def main() -> int:
    parser = argparse.ArgumentParser(description="运行时禁止未隔离的 UnityEditor 引用")
    parser.add_argument("root", type=Path, help="Unity 工程根目录（My project）")
    args = parser.parse_args()
    root = args.root.resolve()
    hits = scan_tree(root)
    if hits:
        print("\n".join(hits))
        print(f"[RUNTIME-NO-EDITOR] FAIL  {len(hits)} 条", file=sys.stderr)
        return 1
    print("[RUNTIME-NO-EDITOR] PASS  运行时 UnityEditor 未隔离引用 = 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
