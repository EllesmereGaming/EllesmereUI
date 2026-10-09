#!/usr/bin/env python3
"""Repo guardrails: mistakes that keep landing, checked mechanically.

Usage:
    python3 .tools/guardrails.py [--base REF] [--head REF]

Checks the change from BASE (default: origin/main) to HEAD (default: the
working tree). CI runs the same command (.github/workflows/guardrails.yml).
Needs a Lua 5.1 compiler: `luac5.1` on PATH, or LUAC=/path/to/luac.

Line exceptions go on the offending line:
    -- guardrails-allow: <check> until YYYY-MM-DD by <approver>: <reason>
An expired exception fails like the violation it covers.
"""
import argparse
import datetime
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXCLUDED_DIRS = ("Libs/", ".tools/")
ALLOW_RE = re.compile(
    r"guardrails-allow:\s*(?P<check>[\w-]+)\s+until\s+(?P<date>\d{4}-\d{2}-\d{2})"
    r"\s+by\s+(?P<who>\S+?):\s*\S")


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True,
                          capture_output=True).stdout.decode("utf-8", "replace")


class Change:
    def __init__(self, base, head):
        self.base, self.head = base, head
        rng = [base] + ([head] if head else [])
        self.lua_files = [p for p in git("diff", "--name-only", "--diff-filter=AMR",
                                         *rng, "--", "*.lua").splitlines()
                          if p and not p.startswith(EXCLUDED_DIRS)]
        self.added_files = set(git("diff", "--name-only", "--diff-filter=A",
                                   *rng, "--", "*.lua").splitlines())
        self.added_lines = self._added_lines(rng)

    def read(self, path):
        if self.head:
            return subprocess.run(["git", "show", f"{self.head}:{path}"], cwd=ROOT,
                                  check=True, capture_output=True).stdout
        with open(os.path.join(ROOT, path), "rb") as f:
            return f.read()

    def _added_lines(self, rng):
        out, path, lineno = [], None, 0
        for line in git("diff", "-U0", *rng, "--", "*.lua").splitlines():
            if line.startswith("+++ "):
                path = line[6:] if line.startswith("+++ b/") else None
            elif line.startswith("@@"):
                lineno = int(re.search(r"\+(\d+)", line).group(1))
            elif line.startswith("+") and path and not path.startswith(EXCLUDED_DIRS):
                out.append((path, lineno, line[1:]))
                lineno += 1
        return out


def allowed(check, text, errors, where):
    m = ALLOW_RE.search(text)
    if not m or m.group("check") != check:
        return False
    if datetime.date.fromisoformat(m.group("date")) < datetime.date.today():
        errors.append(f"{where}: guardrails-allow for '{check}' expired on {m.group('date')}")
    return True


def check_compile(change, errors):
    """Lua 5.1 syntax and its 200-local / 60-upvalue limits; WoW fails the whole file."""
    luac = os.environ.get("LUAC", "luac5.1")
    for path in change.lua_files:
        src = change.read(path)
        if src.startswith(b"\xef\xbb\xbf"):
            src = src[3:]
        res = subprocess.run([luac, "-p", "-"], input=src, capture_output=True)
        if res.returncode != 0:
            msg = res.stderr.decode("utf-8", "replace").strip()
            msg = re.sub(r"^.*?stdin:", f"{path}:", msg)
            errors.append(f"{msg}\n  Fix the syntax, or split the file / move state into a "
                          f"table if a 200-local or 60-upvalue limit is hit.")


GUARD = b"if EUI_CLIENT_BLOCKED then return end"


def check_client_gate(change, errors):
    """Every suite file must stop on a blocked client before it runs anything."""
    for path in change.lua_files:
        if path == "EllesmereUI_ClientGate.lua":
            continue
        first = change.read(path).lstrip(b"\xef\xbb\xbf").split(b"\n", 1)[0]
        if not first.startswith(GUARD):
            errors.append(f"{path}:1: first line must be "
                          f"'{GUARD.decode()} -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)'")


REGEN_RE = re.compile(r"(\S*?)\s*:\s*RegisterEvent\(\s*[\"']PLAYER_REGEN_ENABLED[\"']")
REGEN_DISABLED_RE = re.compile(r"(\S*?)\s*:\s*RegisterEvent\(\s*[\"']PLAYER_REGEN_DISABLED[\"']")
PAIR_WINDOW = 3


def check_combat_deferral(change, errors):
    """Work deferred to combat end goes through the shared combat queue."""
    lines = {}
    for path, lineno, text in change.added_lines:
        m = REGEN_RE.search(text)
        if not m:
            continue
        if path not in lines:
            lines[path] = change.read(path).decode("utf-8", "replace").splitlines()
        # The same frame registering PLAYER_REGEN_DISABLED next to it tracks
        # combat state; that is not a deferral.
        near = lines[path][max(0, lineno - 1 - PAIR_WINDOW):lineno + PAIR_WINDOW]
        if any(d.group(1) == m.group(1) for d in map(REGEN_DISABLED_RE.search, near) if d):
            continue
        where = f"{path}:{lineno}"
        if allowed("combat-deferral", text, errors, where):
            continue
        errors.append(f"{where}: new PLAYER_REGEN_ENABLED registration. Defer with "
                      f"EllesmereUI.CombatQueue.Defer(key, fn) in the parent addon, or the "
                      f"child's ns.CombatQueue (EllesmereUI.NewCombatQueue, EllesmereUI_Ticker.lua)")


# Loose globals that only Blizzard_Deprecated defines: nil on WoW Forever.
DEPRECATED = {
    "GetSpecialization": "C_SpecializationInfo.GetSpecialization",
    "GetSpecializationInfo": "C_SpecializationInfo.GetSpecializationInfo",
    "GetItemInfo": "C_Item.GetItemInfo",
    "GetItemInfoInstant": "C_Item.GetItemInfoInstant",
    "GetItemQualityColor": "C_Item.GetItemQualityColor",
}
GETGLOBAL_RE = re.compile(r"^\s*\d+\s+\[(\d+)\]\s+GETGLOBAL\b.*;\s*(\w+)\s*$", re.M)


def global_reads(change, path):
    """(line, name) for each global read in the compiled file, so strings,
    comments and locals in scope never count."""
    src = change.read(path).lstrip(b"\xef\xbb\xbf")
    res = subprocess.run([os.environ.get("LUAC", "luac5.1"), "-l", "-p", "-"],
                         input=src, capture_output=True)
    if res.returncode != 0:
        return [], []  # check_compile reports it
    return ([(int(n), g) for n, g in GETGLOBAL_RE.findall(res.stdout.decode("utf-8", "replace"))],
            src.decode("utf-8", "replace").splitlines())


def check_deprecated_globals(change, errors):
    """Bare deprecated API globals break the Forever client."""
    added = {}
    for path, lineno, text in change.added_lines:
        added.setdefault(path, set()).add(lineno)
    for path, linenos in added.items():
        reads, lines = global_reads(change, path)
        for lineno, name in sorted(set(reads)):
            if name not in DEPRECATED or lineno not in linenos:
                continue
            text = lines[lineno - 1]
            # A fallback behind the namespace form: (C_Item and C_Item.NAME) or NAME
            if re.search(r"\bC_\w+\." + name + r"\b", text):
                continue
            where = f"{path}:{lineno}"
            if allowed("deprecated-global", text, errors, where):
                continue
            errors.append(f"{where}: bare {name} is nil on WoW Forever; "
                          f"use {DEPRECATED[name]} (or local {name} = {DEPRECATED[name]})")


def check_ascii(change, errors):
    """CONTRIBUTING.md: ASCII only in code; multi-byte text corrupts in packaging."""
    for path, lineno, text in change.added_lines:
        if path.startswith("EllesmereUILocales/"):
            continue
        bad = sorted({c for c in text if ord(c) > 127})
        if not bad:
            continue
        where = f"{path}:{lineno}"
        if allowed("ascii", text, errors, where):
            continue
        shown = ", ".join(f"U+{ord(c):04X}" for c in bad)
        errors.append(f"{where}: non-ASCII character(s) {shown}; use ASCII "
                      f"(-- for a dash, plain quotes) or a byte escape such as \\226\\128\\148")


CHECKS = [check_compile, check_client_gate, check_combat_deferral, check_deprecated_globals,
          check_ascii]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--head", default=None)
    args = ap.parse_args()
    change = Change(args.base, args.head)
    errors = []
    for check in CHECKS:
        check(change, errors)
    for e in errors:
        print(f"::error::{e}" if os.environ.get("GITHUB_ACTIONS") else e)
    if errors:
        print(f"{len(errors)} guardrail error(s).")
        return 1
    print(f"guardrails OK ({len(change.lua_files)} Lua files, "
          f"{len(change.added_lines)} added lines).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
