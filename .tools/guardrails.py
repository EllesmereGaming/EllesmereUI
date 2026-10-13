#!/usr/bin/env python3
"""Repo guardrails: mistakes that keep landing, checked mechanically.

Usage:
    python3 .tools/guardrails.py [--base REF] [--head REF]

Checks what changed from the merge-base of BASE and HEAD (default: the working tree,
untracked Lua files included), so a branch that is behind main is judged on its own
changes only. BASE defaults to origin/main, or on a fork with an upstream remote to
whichever of upstream/main and origin/main the branch left more recently. CI runs the
same checks (.github/workflows/guardrails.yml); .tools/tests/test_guardrails.py tests
them. Needs a Lua 5.1 compiler: luac5.1 on PATH, or LUAC=/path/to/luac.

Line exceptions go in a comment on the offending statement, naming the approving human
and a reason:
    -- guardrails-allow: <check> by <approver>: <reason>
    -- guardrails-allow: <check> until YYYY-MM-DD by <approver>: <reason>
The first form is permanent. A dated one fails every run once its date (UTC) has passed.
"""
import argparse
import atexit
import datetime
import itertools
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXCLUDED_DIRS = ("Libs/", ".tools/")
BOM = b"\xef\xbb\xbf"
CHECK_KEYS = ("combat-deferral", "deprecated-global", "ascii")
# The approver starts with a non-space and holds no date, no "until" and no other tag; the
# reason is more than a block comment's close.
ALLOW_RE = re.compile(r"guardrails-allow:\s*(?P<check>[\w-]+)(?:\s+until\s+(?P<date>\S+))?"
                      r"\s+by\s+(?P<who>(?!\s)(?:(?!\b(?i:until)\b|\d{4}-\d|guardrails-allow)[^:])+?)"
                      r"\s*:\s*(?!\]=*\])\S")
TAG_START_RE = re.compile(r"guardrails-allow\s*:")
# One diff whatever the user's git config or environment says: plain a/ b/ prefixes, no
# colour, no external diff tool, git's default algorithm, no inter-hunk context, every
# file as text, renames found (a copy reads as a new file).
DIFF = ["-c", "core.quotePath=false", "-c", "diff.renames=true", "-c",
        "diff.suppressBlankEmpty=false", "diff", "--no-color", "--no-ext-diff", "--no-textconv",
        "--src-prefix=a/", "--dst-prefix=b/", "--diff-algorithm=myers", "--indent-heuristic",
        "--inter-hunk-context=0", "--text", "-M"]
# Environment variables that would change git's diff output or what its pathspecs match
GIT_ENV_DROP = ("GIT_DIFF_OPTS", "GIT_EXTERNAL_DIFF", "GIT_LITERAL_PATHSPECS",
                "GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS", "GIT_ICASE_PATHSPECS")
# For git runs against the throwaway index: write it whole (a split index would leave a
# shared-index file in the real .git), take files outside a sparse-checkout cone, and run
# no repository hooks.
TEMP_INDEX_CFG = ("-c", "core.splitIndex=false", "-c", "core.sparseCheckout=false", "-c",
                  f"core.hooksPath={os.devnull}")
# Lua files whatever the case of their extension (WoW loads Foo.Lua on Windows and macOS)
LUA_SPEC = ":(icase)*.lua"


class GitError(Exception):
    pass


def git(*args, raw=False, ok=(0,), env=None, data=None):
    env = dict(os.environ if env is None else env)
    for key in GIT_ENV_DROP:
        env.pop(key, None)
    res = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, env=env, input=data)
    if res.returncode not in ok:
        err = res.stderr.decode("utf-8", "replace").strip()
        raise GitError(f"git {' '.join(args)} failed: {err}")
    return res.stdout if raw else res.stdout.decode("utf-8", "replace")


def is_commit(ref):
    try:
        git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
        return True
    except GitError:
        return False


def is_ancestor(a, b):
    try:
        git("merge-base", "--is-ancestor", a, b)
        return True
    except GitError:
        return False


def merge_base(base, head):
    try:
        return git("merge-base", base, head or "HEAD").strip() or base
    except GitError:
        return base


def base_candidates():
    """(ref, merge-base with HEAD) for refs/remotes/upstream/main and
    refs/remotes/origin/main, those that exist and share history with the branch (never a
    local branch that happens to be named origin/main)."""
    found = []
    for name in ("upstream/main", "origin/main"):
        ref = f"refs/remotes/{name}"
        if is_commit(ref):
            try:
                found.append((ref, git("merge-base", ref, "HEAD").strip()))
            except GitError:
                pass                    # unrelated to this branch: never the base
    return found


def default_base():
    """origin/main, or on a fork with an upstream remote whichever of upstream/main and
    origin/main the branch left more recently (a stale one would judge the other's
    commits as the branch's own)."""
    found = base_candidates()
    if len(found) < 2:
        return found[0][0] if found else "origin/main"
    (upstream, up_mb), (origin, origin_mb) = found
    return origin if is_ancestor(up_mb, origin_mb) else upstream


def base_note(base):
    """A note when the default base is origin/main and upstream/main lacks some of its
    commits: locally a stale upstream and commits only on the fork look the same, while a
    pull request to upstream is judged against upstream's main."""
    found = dict(base_candidates())
    up = found.get("refs/remotes/upstream/main")
    if base != "refs/remotes/origin/main" or not up or up == found.get(base):
        return None
    return ("compared with origin/main; upstream/main lacks some of its commits. A pull "
            "request to upstream is judged against upstream/main: git fetch upstream, or "
            "pass --base upstream/main")


def unquote_path(s):
    """A path git printed in C-style quotes."""
    body, out, i = s[1:-1], bytearray(), 0
    escapes = {"a": 7, "b": 8, "t": 9, "n": 10, "v": 11, "f": 12, "r": 13, '"': 34, "\\": 92}
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            nxt = body[i + 1]
            if nxt in escapes:
                out.append(escapes[nxt])
                i += 2
                continue
            if nxt.isdigit():
                out.append(int(body[i + 1:i + 4], 8))
                i += 4
                continue
        out.extend(c.encode("utf-8"))
        i += 1
    return out.decode("utf-8", "replace")


HUNK_RE = re.compile(r"@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def parse_patch(out):
    """(path, line, text) for each added line of a git -U0 patch. Each hunk is read for
    exactly the lengths its @@ header gives, so no added line is mistaken for a header."""
    added, path, old_left, new_left, lineno = [], None, 0, 0, 0
    for line in out.split("\n"):
        if old_left > 0 or new_left > 0:
            if line.startswith("+"):
                if path:
                    text = line[1:]
                    added.append((path, lineno, text[:-1] if text.endswith("\r") else text))
                lineno += 1
                new_left -= 1
            elif line.startswith("-"):
                old_left -= 1
            elif line.startswith(" ") or line == "":   # context ("" when blank ones are cut)
                lineno += 1
                new_left -= 1
                old_left -= 1
            continue
        if line.startswith("diff --git "):
            path = None
        elif line.startswith("+++ "):
            name = line[4:]
            if name.endswith("\t"):    # git ends a name that holds a space with a tab
                name = name[:-1]
            if name.startswith('"'):
                name = unquote_path(name)
            path = name[2:] if name.startswith("b/") else None
        elif line.startswith("@@"):
            m = HUNK_RE.match(line)
            if m:
                old_left = int(m.group(1)) if m.group(1) is not None else 1
                lineno = int(m.group(2))
                new_left = int(m.group(3)) if m.group(3) is not None else 1
    return added


def lua_paths(text):
    return [p for p in text.split("\0")
            if p and p.lower().endswith(".lua") and not p.startswith(EXCLUDED_DIRS)]


def _remove_quietly(path):
    try:
        os.remove(path)
    except OSError:
        pass


class Change:
    """What changed between the merge-base of base and head (or the working tree)."""

    def __init__(self, base, head):
        for flag, ref in (("--base", base), ("--head", head)):
            if ref and not is_commit(ref):
                raise GitError(f"'{ref}' is not a commit in this repository; fetch it or "
                               f"pass another {flag}")
        self.base, self.head = merge_base(base, head), head
        self._read = {}
        # The working tree is diffed against a throwaway copy of the index, its untracked
        # Lua files added as intent-to-add: git diffs them like the rest and pairs a moved
        # file as a rename, and git diff's stat refresh never writes the real index
        self.env = None if head else self._intent_index()
        pre = TEMP_INDEX_CFG if self.env else ()
        rng = [self.base] + ([head] if head else [])
        files = lua_paths(git(*pre, *DIFF, "--name-only", "-z", "--diff-filter=AMR", *rng,
                              "--", LUA_SPEC, env=self.env))
        # A name that is not UTF-8 cannot be passed back to git or open(): named, not read
        self.bad_names = [p for p in files if "\ufffd" in p]
        self.lua_files = [p for p in files if "\ufffd" not in p]
        self.added_lines = [a for a in parse_patch(git(*pre, *DIFF, "-U0", *rng, "--", LUA_SPEC,
                                                       env=self.env))
                            if not a[0].startswith(EXCLUDED_DIRS) and "\ufffd" not in a[0]]
        self.added_by_path = {}
        for path, lineno, text in self.added_lines:
            self.added_by_path.setdefault(path, {})[lineno] = text
        self._lex, self._analysis, self.skips = {}, {}, {}

    def _intent_index(self):
        """The environment for a throwaway copy of the index that also holds the untracked
        Lua files as intent-to-add. The real index is never touched; with no index yet,
        git starts the copy empty."""
        new = lua_paths(git("ls-files", "--others", "--exclude-standard", "-z", "--",
                            LUA_SPEC))
        index = git("rev-parse", "--git-path", "index").strip()
        index = index if os.path.isabs(index) else os.path.join(ROOT, index)
        fd, tmp = tempfile.mkstemp(prefix="guardrails-index-")
        os.close(fd)
        atexit.register(_remove_quietly, tmp)
        if os.path.exists(index):
            shutil.copyfile(index, tmp)
        else:
            os.remove(tmp)          # git rejects an empty file as an index
        env = dict(os.environ, GIT_INDEX_FILE=tmp)
        if new:
            git(*TEMP_INDEX_CFG, "--literal-pathspecs", "add", "--intent-to-add",
                "--pathspec-from-file=-", "--pathspec-file-nul", env=env,
                data="\0".join(new).encode("utf-8"))
        return env

    def read(self, path):
        if path not in self._read:
            if self.head:
                self._read[path] = git("cat-file", "blob", f"{self.head}:{path}", raw=True)
            else:
                with open(os.path.join(ROOT, path), "rb") as f:
                    self._read[path] = f.read()
        return self._read[path]

    def lex(self, path):
        if path not in self._lex:
            self._lex[path] = lua_lex(self.read(path).decode("utf-8", "replace"))
        return self._lex[path]

    def tokens(self, path):
        return self.lex(path)[0]

    def comment(self, path, line):
        """The comment text on a line of a Lua file (a block comment's whole text on each
        line it spans)."""
        return self.lex(path)[1].text(line)

    def analysis(self, path, errors):
        if path not in self._analysis:
            try:
                self._analysis[path] = Analysis(self.tokens(path))
            except Exception as e:      # a syntax error the walk trips on, or a bug here
                self._analysis[path] = FailedAnalysis(f"{type(e).__name__}: {e}")
        result = self._analysis[path]
        if isinstance(result, FailedAnalysis):
            errors.append(Error(path, None, f"could not be analysed ({result.error}); fix its "
                                            f"syntax first, or report this"))
        return result

    def list_dir(self, folder):
        """File names directly in folder ("" is the repository root)."""
        if self.head:
            spec = [f"{folder}/"] if folder else []
            out = git("ls-tree", "--name-only", "-z", self.head, "--", *spec)
            return [p.rsplit("/", 1)[-1] for p in out.split("\0") if p]
        try:
            return os.listdir(os.path.join(ROOT, folder))
        except OSError:
            return []

    def grep(self, pattern):
        """The Lua files of the tree whose text matches pattern. git lists them
        NUL-separated, so any name survives."""
        args = ["grep", "--no-color", "-z", "-l", "-a"] + ([] if self.head else ["--untracked"])
        args += ["-E", pattern] + ([self.head] if self.head else [])
        out = git(*args, "--", LUA_SPEC, ok=(0, 1))
        prefix = f"{self.head}:" if self.head else ""
        paths = []
        for rec in out.split("\0"):
            path = rec[len(prefix):] if prefix and rec.startswith(prefix) else rec
            if path and not path.startswith(EXCLUDED_DIRS) and "\ufffd" not in path:
                paths.append(path)
        return paths


class Error:
    """One finding: its file and line (either may be None) and the message."""

    def __init__(self, path, line, text):
        self.path, self.line, self.text = path, line, text

    def __str__(self):
        if self.path and self.line:
            return f"{self.path}:{self.line}: {self.text}"
        return f"{self.path}: {self.text}" if self.path else self.text

    def annotation(self):
        """The GitHub Actions form, attached to the file and line."""
        def esc(s, prop=False):
            s = s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            return s.replace(":", "%3A").replace(",", "%2C") if prop else s
        props = [f"file={esc(self.path, True)}"] if self.path else []
        if self.path and self.line:
            props.append(f"line={self.line}")
        if props:
            return f"::error {','.join(props)}::{esc(str(self))}"
        return f"::error::{esc(str(self))}"


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------
def utc_today():
    return datetime.datetime.now(datetime.timezone.utc).date()


def parse_date(text):
    try:
        return datetime.datetime.strptime(text, "%Y-%m-%d").date()
    except (TypeError, ValueError):
        return None


def expired_message(check, date):
    return f"guardrails-allow for '{check}' expired on {date}"


def tags_in(text):
    """Each guardrails-allow tag in a comment's text, read from its own start (so it never
    borrows a later tag's text): its match, or None when malformed."""
    return [ALLOW_RE.match(text, m.start()) for m in TAG_START_RE.finditer(text)]


def tag_problems(tag):
    """What is wrong with one guardrails-allow tag (None: it did not parse)."""
    if not tag:
        return ["malformed guardrails-allow; write -- guardrails-allow: <check> "
                "[until YYYY-MM-DD] by <approver>: <reason>"]
    problems = []
    check, date = tag.group("check"), tag.group("date")
    if check not in CHECK_KEYS:
        problems.append(f"unknown guardrails-allow check '{check}' "
                        f"(one of: {', '.join(CHECK_KEYS)})")
    if date and parse_date(date) is None:
        problems.append(f"guardrails-allow for '{check}' has an invalid date {date} "
                        f"(use YYYY-MM-DD)")
    return problems


def allowed(change, check, path, lines, errors):
    """True when a comment on one of lines (the offending statement's) carries an exception
    for this check. An expired one is reported in place of the violation."""
    expired = None
    for line in lines:
        for tag in tags_in(change.comment(path, line)):
            if not tag or tag.group("check") != check:
                continue
            raw = tag.group("date")
            date = parse_date(raw) if raw else None
            if not raw or date is None or date >= utc_today():
                return True        # a bad date is reported by check_exception_tags
            expired = (line, raw)
    if expired:
        errors.append(Error(path, expired[0], expired_message(check, expired[1])))
        return True
    return False


# ---------------------------------------------------------------------------
# Lua tokens: names, keywords, strings, numbers and operators with their line, and the
# comment text on each line. Comments are not tokens and a string is one token, so text
# inside either never reads as code. Lines count LF only, as git counts them.
# ---------------------------------------------------------------------------
KEYWORDS = frozenset("and break do else elseif end false for function if in local nil not or "
                     "repeat return then true until while".split())
NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUMBER_RE = re.compile(r"0[xX][0-9a-fA-F]+|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?")
LONG_OPEN_RE = re.compile(r"\[(=*)\[")
OPS3, OPS2 = ("...",), ("..", "==", "~=", "<=", ">=")


class Comments:
    """A file's comments, each with its first line. A block comment's text counts on every
    line it spans, so a tag or a reason wrapped inside one is read whole."""

    def __init__(self):
        self.items, self.by_line = [], {}

    def add(self, line, raw):
        self.items.append((line, raw))
        for ln in range(line, line + raw.count("\n") + 1):
            self.by_line.setdefault(ln, []).append(len(self.items) - 1)

    def text(self, line):
        return " ".join(self.items[k][1].replace("\n", " ") for k in self.by_line.get(line, ()))

    def tags(self):
        """(line, match or None) for each guardrails-allow tag, at the line it starts on."""
        for line, raw in self.items:
            flat = raw.replace("\n", " ")
            for m in TAG_START_RE.finditer(flat):
                yield line + raw.count("\n", 0, m.start()), ALLOW_RE.match(flat, m.start())


def lua_lex(src):
    src = src.replace("\r\n", "\n")
    out, comments, i, n, line = [], Comments(), 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif c in " \t\r\f\v":
            i += 1
        elif src.startswith("--", i):
            m = LONG_OPEN_RE.match(src, i + 2)
            if m:
                close = "]" + m.group(1) + "]"
                e = src.find(close, m.end())
                e = n if e < 0 else e + len(close)
            else:
                e = src.find("\n", i)
                e = n if e < 0 else e
            comments.add(line, src[i:e])
            line += src.count("\n", i, e)
            i = e
        elif c == "[" and LONG_OPEN_RE.match(src, i):
            m = LONG_OPEN_RE.match(src, i)
            close = "]" + m.group(1) + "]"
            e = src.find(close, m.end())
            body_end, e = (n, n) if e < 0 else (e, e + len(close))
            out.append(("string", src[m.end():body_end], line))
            line += src.count("\n", i, e)
            i = e
        elif c in "\"'":
            j = i + 1
            while j < n and src[j] != c and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            out.append(("string", src[i + 1:j], line))
            line += src.count("\n", i, min(j, n))
            i = j + 1
        elif "0" <= c <= "9" or (c == "." and i + 1 < n and "0" <= src[i + 1] <= "9"):
            m = NUMBER_RE.match(src, i)
            out.append(("number", m.group(0), line))
            i = m.end()
        elif c == "_" or "a" <= c <= "z" or "A" <= c <= "Z":
            m = NAME_RE.match(src, i)
            word = m.group(0)
            out.append(("keyword" if word in KEYWORDS else "name", word, line))
            i = m.end()
        else:
            op = next((o for o in OPS3 + OPS2 if src.startswith(o, i)), c)
            out.append(("op", op, line))
            i += len(op)
    return out, comments


def lua_tokens(src):
    return lua_lex(src)[0]


def sym(t):
    """A token's value when it is syntax (an operator or keyword), else None, so a
    string, name or number never reads as syntax."""
    return t[1] if t[0] in ("op", "keyword") else None


# ---------------------------------------------------------------------------
# Compile and line-1 gate
# ---------------------------------------------------------------------------
def find_luac():
    """(the Lua 5.1 compiler to use, None) or (None, why there is none)."""
    name = os.environ.get("LUAC", "luac5.1")
    exe = shutil.which(name)
    if not exe:
        return None, (f"no Lua 5.1 compiler '{name}': install lua5.1 (luac5.1 on PATH) "
                      f"or set LUAC=/path/to/luac")
    try:
        res = subprocess.run([exe, "-v"], capture_output=True, stdin=subprocess.DEVNULL,
                             timeout=60)
        version = (res.stdout + res.stderr).decode("utf-8", "replace").strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, f"cannot run Lua compiler '{name}': {e}"
    if "Lua 5.1" not in version:
        first = version.splitlines()[0] if version else "no version"
        return None, f"'{name}' is not a Lua 5.1 compiler ({first}); set LUAC to a luac 5.1"
    return exe, None


def check_compile(change, errors):
    """Lua 5.1 syntax and its 200-local / 60-upvalue limits; WoW fails the whole file."""
    if not change.lua_files:
        return
    exe, problem = find_luac()
    if problem:
        errors.append(Error(None, None, problem))
        return
    for path in change.lua_files:
        src = change.read(path)
        if src.startswith(BOM):
            src = src[3:]
        res = subprocess.run([exe, "-p", "-"], input=src, capture_output=True)
        if res.returncode != 0:
            msg = res.stderr.decode("utf-8", "backslashreplace").strip()
            m = re.search(r"stdin:(\d+):\s*(.*)", msg, re.S)
            line, text = (int(m.group(1)), m.group(2).strip()) if m else (None, msg)
            errors.append(Error(path, line, f"{text} (fix the syntax, or split the file / "
                                            f"move state into a table if a 200-local or "
                                            f"60-upvalue limit is hit)"))


GUARD = b"if EUI_CLIENT_BLOCKED then return end"


def check_client_gate(change, errors):
    """Every suite file must stop on a blocked client before it runs anything."""
    for path in change.lua_files:
        if path == "EllesmereUI_ClientGate.lua":
            continue
        first = change.read(path)
        if first.startswith(BOM):
            first = first[3:]
        if not first.split(b"\n", 1)[0].startswith(GUARD):
            errors.append(Error(path, 1, f"first line must be '{GUARD.decode()} -- pre-12.1 "
                                         f"client failsafe (EllesmereUI_ClientGate.lua)'"))


# ---------------------------------------------------------------------------
# Globals WoW Forever never defines. Retail gets them from Blizzard's deprecation
# addons, and only while the loadDeprecationFallbacks CVar is on; Forever loads none
# of these (Blizzard_DeprecatedSpecialization is "classic, standard" only, the others
# do not exist there). Each name maps to what to call instead.
# ---------------------------------------------------------------------------
_MOVED = (  # the same name, now in a namespace
    ("C_SpecializationInfo", "GetSpecialization GetSpecializationInfo "
                             "GetNumSpecializationsForClassID GetActiveSpecGroup"),
    ("C_Item", "ActionBindsItem BindEnchant ConfirmBindOnUse ConfirmNoRefundOnUse ConfirmOnUse "
               "DoesItemContainSpec DropItemOnUnit EndBoundTradeable EndRefund EquipItemByName "
               "GetDetailedItemLevelInfo GetItemChildInfo GetItemClassInfo GetItemCooldown "
               "GetItemCount GetItemCreationContext GetItemFamily GetItemGem GetItemInfo "
               "GetItemInfoInstant GetItemInventorySlotInfo GetItemQualityColor GetItemSetInfo "
               "GetItemSpecInfo GetItemSpell GetItemSubClassInfo GetItemUniqueness "
               "IsArtifactPowerItem IsConsumableItem IsCorruptedItem IsCosmeticItem IsCurrentItem "
               "IsDressableItem IsEquippableItem IsEquippedItem IsEquippedItemType IsHarmfulItem "
               "IsHelpfulItem IsItemInRange IsUsableItem ItemHasRange PickupItem ReplaceEnchant "
               "ReplaceTradeEnchant ReplaceTradeskillEnchant UseItemByName"),
    ("C_ItemSocketInfo", "AcceptSockets ClickSocketButton CloseSocketInfo GetExistingSocketInfo "
                         "GetExistingSocketLink GetNewSocketInfo GetNewSocketLink GetNumSockets "
                         "GetSocketItemBoundTradeable GetSocketItemInfo GetSocketItemRefundable "
                         "GetSocketTypes HasBoundGemProposed"),
    ("C_CurrencyInfo", "GetCoinIcon GetCoinText GetCoinTextureString"),
    ("C_PvP", "GetZonePVPInfo IsSubZonePVPPOI SetPVP TogglePVP"),
    ("C_PetInfo", "GetPetTalentTree PetAssistMode"),
    ("C_TradeInfo", "PickupTradeMoney"),
)
DEPRECATED = {name: f"{ns}.{name}" for ns, names in _MOVED for name in names.split()}
DEPRECATED.update({
    "GetSpecializationMasterySpells": "C_SpecializationInfo.GetSpecializationMasterySpells "
                                      "(returns a table)",
    "GetTalentInfo": "C_SpecializationInfo.GetTalentInfo (takes a query table)",
    "GetItemIcon": "C_Item.GetItemIconByID",
    "PlayVocalErrorSoundID": "C_Sound.PlayVocalErrorSound",
})
# Native on retail, missing on Forever, and with no namespaced form: callers nil-guard
# it and fall through to "no spec".
NIL_GUARD = frozenset({"GetSpecializationInfoByID"})
WATCHED = frozenset(DEPRECATED) | NIL_GUARD
WATCHED_RE = re.compile(r"\b(?:" + "|".join(sorted(WATCHED, key=len, reverse=True)) + r")\b")
# The namespaced form each name moved to, as a name chain: ("C_Item", "GetItemInfo").
TARGETS = {tuple(to.split(" ")[0].split(".")): name for name, to in DEPRECATED.items()}


def _family(name):
    """What a test of `name` proves present: a deprecation addon loads whole, and only
    retail loads the spec one, where GetSpecializationInfoByID is native."""
    if name in NIL_GUARD:
        return frozenset({name})
    ns = DEPRECATED[name].split(".")[0]
    fam = {n for n, to in DEPRECATED.items() if to.split(".")[0] == ns}
    return frozenset(fam | NIL_GUARD if ns == "C_SpecializationInfo" else fam)


FAMILY = {name: _family(name) for name in WATCHED}
EMPTY = frozenset()
OPENERS, CLOSERS = ("(", "[", "{"), (")", "]", "}")
STATEMENT_START = {"end", "else", "elseif", "until", "return", "local", "if", "for", "while",
                   "do", "function", "repeat", "break"}
# Keywords that start a statement or a block: nothing an expression proved carries on.
STATEMENT_KEYS = {"then", "do", "else", "elseif", "end", "until", "local", "return", "if",
                  "for", "while", "repeat", "break"}
# A line that ends with one of these, or starts with one of these, continues the
# previous line's expression.
CONT_END = {"and", "or", "not", "(", "[", "{", ",", "=", "..", "+", "-", "*", "/", "%", "^",
            "==", "~=", "<", ">", "<=", ">="}
CONT_START = {"and", "or", "..", ")", "]", "}", "+", "-", "*", "/", "%", "^", "==", "~=",
              "<", ">", "<=", ">=", ".", ":", ","}


def ends_expr(t):
    """t can end an expression, so a name right after it on the same line starts a new
    statement."""
    return t[0] in ("name", "number", "string") or \
        sym(t) in (")", "]", "}", "...", "nil", "true", "false", "end")


def bracket_pairs(tokens):
    """{opening index: closing index} for every bracket pair."""
    pairs, stack = {}, []
    for i, t in enumerate(tokens):
        s = sym(t)
        if s in OPENERS:
            stack.append(i)
        elif s in CLOSERS and stack:
            pairs[stack.pop()] = i
    return pairs


def branch_exits(tokens):
    """Indexes of the then/else tokens whose branch always leaves the rest of its block:
    a return or break directly in it, or in plain do-blocks inside it."""
    # loops: the function nesting of each for/while header still waiting for its do
    # (a closure in the header has loops of its own)
    exits, stack, loops, fns = set(), [], [], 0
    for i, t in enumerate(tokens):
        s = sym(t)
        if s in ("for", "while"):
            loops.append(fns)
        elif s == "do":
            loop = bool(loops) and loops[-1] == fns
            if loop:
                loops.pop()
            stack.append(["loop" if loop else "do", None])
        elif s in ("function", "repeat", "if"):
            stack.append([s, None])
            if s == "function":
                fns += 1
        elif s in ("then", "else") and stack and stack[-1][0] == "if":
            stack[-1][1] = i
        elif s == "elseif" and stack and stack[-1][0] == "if":
            stack[-1][1] = None
        elif s in ("end", "until"):
            if stack and stack.pop()[0] == "function":
                fns -= 1
        elif s in ("return", "break"):
            for kind, branch in reversed(stack):
                if kind == "if":
                    if branch is not None:
                        exits.add(branch)
                    break
                if kind != "do":
                    break
    return exits


# ---------------------------------------------------------------------------
# What an expression proves: for a condition or the left side of 'and', the watched
# globals known present when it is truthy, and when it is falsy.
# ---------------------------------------------------------------------------
def split_top(toks, word):
    """toks split at each top-level keyword `word` (outside brackets and function bodies)."""
    parts, cur, depth, blocks = [], [], 0, 0
    for t in toks:
        s = sym(t)
        if s in OPENERS:
            depth += 1
        elif s in CLOSERS:
            depth -= 1
        elif s == "function" or (blocks and s in ("if", "do", "repeat")):
            blocks += 1
        elif s in ("end", "until") and blocks:
            blocks -= 1
        if s == word and depth == 0 and blocks == 0:
            parts.append(cur)
            cur = []
        else:
            cur.append(t)
    parts.append(cur)
    return parts


def whole_paren(toks):
    """toks is one parenthesized expression."""
    if len(toks) < 2 or sym(toks[0]) != "(" or sym(toks[-1]) != ")":
        return False
    depth = 0
    for k, t in enumerate(toks):
        s = sym(t)
        if s in OPENERS:
            depth += 1
        elif s in CLOSERS:
            depth -= 1
            if depth == 0:
                return k == len(toks) - 1
    return False


def chain_names(toks):
    """('a', 'b', 'c') for a name chain a.b.c, ('_G', 'X') for _G["X"], else None."""
    if len(toks) == 4 and toks[0][:2] == ("name", "_G") and sym(toks[1]) == "[" \
            and toks[2][0] == "string" and sym(toks[3]) == "]":
        return "_G", toks[2][1]
    if not toks or len(toks) % 2 == 0:
        return None
    for k, t in enumerate(toks):
        if (k % 2 == 0 and t[0] != "name") or (k % 2 == 1 and sym(t) != "."):
            return None
    return tuple(t[1] for t in toks[::2])


def is_flag(chain):
    """A Forever flag: EllesmereUI.IS_FOREVER, a local FOREVER, EABR.FOREVER."""
    return bool(chain) and chain[-1].endswith("FOREVER")


def ref_global(toks, resolve):
    """The watched global a reference names: X, a local copy of one, _G.X or _G["X"]."""
    chain = chain_names(toks)
    if not chain:
        return None
    if len(chain) == 2 and chain[0] == "_G":
        return chain[1] if chain[1] in WATCHED else None
    if len(chain) == 1:
        bnd = resolve(chain[0])
        if bnd is None:
            return chain[0] if chain[0] in WATCHED else None
        return bnd.alias
    return None


def prove(toks, resolve):
    """(when truthy, when falsy): the watched globals each outcome of toks proves present.
    resolve(name) is the binding the name has there."""
    while whole_paren(toks):
        toks = toks[1:-1]
    if not toks:
        return EMPTY, EMPTY
    parts = split_top(toks, "or")
    if len(parts) > 1:
        res = [prove(p, resolve) for p in parts]
        return (frozenset.intersection(*(r[0] for r in res)),
                frozenset.union(*(r[1] for r in res)))
    parts = split_top(toks, "and")
    if len(parts) > 1:
        chains = [chain_names(p) for p in parts]
        res = []
        for p, c in zip(parts, chains):
            if c and any(o and len(o) > len(c) and o[:len(c)] == c for o in chains):
                res.append((EMPTY, WATCHED))   # a table another operand indexes: never false
            else:
                res.append(prove(p, resolve))
        return (frozenset.union(*(r[0] for r in res)),
                frozenset.intersection(*(r[1] for r in res)))
    if sym(toks[0]) == "not":
        rest = toks[1:]
        if chain_names(rest) or whole_paren(rest):
            pos, neg = prove(rest, resolve)
            return neg, pos
        return EMPTY, EMPTY
    return prove_atom(toks, resolve)


def whole_function(toks):
    """toks is one function literal: function (...) ... end."""
    if not toks or sym(toks[0]) != "function" or sym(toks[-1]) != "end":
        return False
    blocks = 0
    for k, t in enumerate(toks):
        s = sym(t)
        if s in ("function", "if", "do", "repeat"):
            blocks += 1
        elif s in ("end", "until"):
            blocks -= 1
            if blocks == 0:
                return k == len(toks) - 1
    return False


def whole_table(toks):
    """toks is one table constructor."""
    if len(toks) < 2 or sym(toks[0]) != "{" or sym(toks[-1]) != "}":
        return False
    depth = 0
    for k, t in enumerate(toks):
        s = sym(t)
        if s in OPENERS:
            depth += 1
        elif s in CLOSERS:
            depth -= 1
            if depth == 0:
                return k == len(toks) - 1
    return False


def always_truthy(toks):
    """toks can never be nil or false: a literal, a table or function, a C_ namespace
    or one of the C_ forms the watched globals moved to (both exist on every client),
    or and/or chains of such."""
    while whole_paren(toks):
        toks = toks[1:-1]
    if not toks:
        return False
    parts = split_top(toks, "or")
    if len(parts) > 1:
        return any(always_truthy(p) for p in parts)
    parts = split_top(toks, "and")
    if len(parts) > 1:
        return all(always_truthy(p) for p in parts)
    if len(toks) == 1 and (toks[0][0] in ("number", "string") or sym(toks[0]) == "true"):
        return True
    if whole_table(toks) or whole_function(toks):
        return True
    chain = chain_names(toks)
    return bool(chain) and ((len(chain) == 1 and chain[0].startswith("C_")) or chain in TARGETS)


def prove_atom(toks, resolve):
    chain = chain_names(toks)
    if chain in TARGETS:
        return EMPTY, FAMILY[TARGETS[chain]]          # C_Item.GetItemInfo missing: not Forever
    if always_truthy(toks):
        return EMPTY, WATCHED                         # never false: that outcome proves anything
    if len(toks) == 1 and sym(toks[0]) in ("nil", "false"):
        return WATCHED, EMPTY                         # never true
    depth, cmp_at = 0, []
    for k, t in enumerate(toks):
        s = sym(t)
        if s in OPENERS:
            depth += 1
        elif s in CLOSERS:
            depth -= 1
        elif depth == 0 and s in ("==", "~=", "<", ">", "<=", ">="):
            cmp_at.append(k)
    if not cmp_at:
        chain = chain_names(toks)
        if is_flag(chain):
            return EMPTY, WATCHED                     # IS_FOREVER: false only on retail
        name = ref_global(toks, resolve)
        if name:
            return FAMILY[name], EMPTY                # GetX, _G.GetX
        return EMPTY, EMPTY
    if len(cmp_at) != 1 or sym(toks[cmp_at[0]]) not in ("==", "~="):
        return EMPTY, EMPTY
    k = cmp_at[0]
    left, right, equal = toks[:k], toks[k + 1:], sym(toks[k]) == "=="
    if len(left) == 1 and (left[0][0] == "string" or sym(left[0]) in ("nil", "true", "false")):
        left, right = right, left                     # nil ~= GetX
    if len(right) != 1:
        return EMPTY, EMPTY
    lit = sym(right[0]) if right[0][0] == "keyword" else \
        ("string:" + right[0][1] if right[0][0] == "string" else None)
    if lit == "nil":
        name = ref_global(left, resolve)
        if name:                                      # GetX ~= nil / GetX == nil
            return (EMPTY, FAMILY[name]) if equal else (FAMILY[name], EMPTY)
    elif lit in ("true", "false") and is_flag(chain_names(left)):
        if equal == (lit == "true"):                  # IS_FOREVER == true / ~= false
            return EMPTY, WATCHED
        return WATCHED, EMPTY                         # IS_FOREVER ~= true / == false
    elif lit == "string:function" and len(left) >= 4 and left[0][:2] == ("name", "type") \
            and sym(left[1]) == "(" and sym(left[-1]) == ")":
        name = ref_global(left[2:-1], resolve)
        if name:                                      # type(GetX) == "function"
            return (FAMILY[name], EMPTY) if equal else (EMPTY, FAMILY[name])
    return EMPTY, EMPTY


# ---------------------------------------------------------------------------
# The walk: scopes and bindings, what each point of the code knows, the watched globals
# it uses, and its PLAYER_REGEN_* registrations.
# ---------------------------------------------------------------------------
REGEN = ("PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED")


class Binding:
    """A local. alias: the watched global it copies (it may be nil, so calls through it
    are judged as calls of that global). key: the registrant it is another name for (a
    script handler's self, a method's self, a local copy of a field). strings / keys:
    the event names a table holds as elements / as keys, for a table, a string constant
    (value) or a loop variable running over one; table: which tables those are (several
    when it is chosen by and/or); lines: the lines that make a registration through it new
    besides the call's own (a constant's value, a loop's header); ver: bumped when the
    local is given a new object, so the old and the new one are different registrants."""
    __slots__ = ("id", "alias", "key", "strings", "keys", "table", "value", "lines", "ver")

    def __init__(self, bid, alias=None):
        self.id, self.alias, self.key = bid, alias, None
        self.strings, self.keys, self.table, self.value = None, None, None, False
        self.lines, self.ver = None, 0


class Scope:
    def __init__(self, kind, guards=()):
        self.kind, self.locals, self.guards = kind, {}, set(guards)
        self.awaiting_do = kind in ("while", "for")
        self.pending = None     # what an if/elseif/while condition proves, from its then/do on
        self.later = set()      # if-chain: what the next branch knows (each condition so far false)
        self.chain = None       # if-chain: what each branch that falls through ends up knowing
        self.exits = False      # if-branch: always leaves the rest of the block
        self.saved = None       # function: the enclosing expression state, back at its end


class Reg:
    """A PLAYER_REGEN_* registration: who registers it (key; None when that cannot be
    told), the lines from the registrant to the event, the event's line, whether it is
    reported itself (a loop over an event list is reported at the list), whether it is a
    handler table's key (reported only once a loop registers that table), and its
    statement's exception lines (span)."""
    __slots__ = ("event", "key", "lines", "line", "report", "keyed", "stmt", "span")

    def __init__(self, event, key, lines, line, report, keyed, stmt):
        self.event, self.key, self.lines, self.line = event, key, lines, line
        self.report, self.keyed, self.stmt, self.span = report, keyed, stmt, None


# Registrars whose later arguments are a callback and an owner, not events
CALLBACK_REGS = ("RegisterCallback", "RegisterCallbackWithHandle",
                 "RegisterFrameEventAndCallback", "RegisterFrameEventAndCallbackWithHandle")
# Helper names that run or fire a handler rather than register one, as a leading word
DISPATCH = ("On", "Handle", "Trigger", "Fire", "Dispatch", "Process", "Is", "Has", "Get")
WORD_RE = re.compile(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+")
DISPATCH_LEAD = frozenset(w.lower() for w in DISPATCH) | {"unregister"}


class Analysis:
    """uses: (line, global, how) for each unguarded use of a watched global, how being
    call, copy-call (through a local copy), alias (a local copy made), store (kept in a
    variable or table) or hook (hooksecurefunc on it); spans: the exception lines of each
    use's statement (its lines, less the bodies of function literals written in it).
    deferrals: the PLAYER_REGEN_ENABLED registrations of a registrant that never
    registers PLAYER_REGEN_DISABLED."""

    def __init__(self, tokens):
        self.t, self.n = tokens, len(tokens)
        self.pairs = bracket_pairs(tokens)
        self.open_of = {c: o for o, c in self.pairs.items()}
        self.exits = branch_exits(tokens)
        self.ids = itertools.count(1)
        self.stack = [Scope("chunk")]
        # expr: (bracket depth, names, kind) known for the rest of an operand. "and": the
        # left side of an 'and' was true, until that depth's next 'or'. "or": the left side
        # of an 'or' was false, until the end of the or-chain.
        self.expr, self.depth = [], 0
        self.region, self.or_region = {0: 0}, {0: 0}   # where the current operand starts
        self.brackets, self.pending, self.handled = [], [], set()
        self.fn_level = 0
        self.rhs_depth = None   # the depth of the assignment whose values the walk is in
        self.stmt_start = 0     # the index of the statement's first token
        self.stmts, self.cur = [[1, 1]], 0             # first and last line of each statement
        self.holes = [[]]       # each statement's function literals: (header line, end line)
        self.stmt_tok = [0]     # the token each statement starts at
        self.owner = [0] * self.n                      # the statement each token belongs to
        self._by_line = None
        self.uses, self.use_stmt, self.regs = [], [], []
        self.table_owner = {}   # event table -> [(registrant, lines, binding id)] of its loops
        self.field_tables = {}  # a field's registrant key -> the index of its table constructor
        self.fn_target = {}     # index of a function literal -> the identity it is assigned to
        self.fn_first = {}      # a named function's identity -> its first parameter's binding id
        self.script_owners = {} # a function identity -> the frames it is a script handler of
        self.method_self = {}   # a colon method's self binding id -> its object's key
        self.field_alias = []   # (field key, local key) for field = local
        self._line_span = None
        self.walk()
        self.spans = [self.lines_of(k) for k in self.use_stmt]
        # A list or handler table that loops register: each registrant gets its own copy of
        # the entry, new when the entry or that loop is. A helper's claim gives way to a frame's
        # through the same name (a check like EventValid(ev) beside f:RegisterEvent(ev)).
        roots = {r.key[0] for r in self.regs if r.key and isinstance(r.key[0], tuple)}
        regs = []
        for r in self.regs:
            r.span = self.lines_of(r.stmt)
            claims = self.table_owner.get(r.key[1]) if r.key and r.key[0] == "table" else None
            owners = []
            for key, lines, via in claims or ():
                if key[0] == "call" and (("local", via) in roots or any(
                        k[0] != "call" and v == via for k, _, v in claims)):
                    continue
                if all(o[0] != key for o in owners):
                    owners.append((key, lines))
            if not owners:
                regs.append(r)
                continue
            for key, lines in owners:
                c = Reg(r.event, key, list(r.lines) + [ln for ln in lines if ln not in r.lines],
                        r.line, r.report or r.keyed, r.keyed, r.stmt)
                c.span = r.span
                regs.append(c)
        self.regs = regs
        self.rewrite_handlers()
        trackers = {r.key for r in self.regs
                    if r.event == "PLAYER_REGEN_DISABLED" and r.key is not None}
        self.deferrals = [r for r in self.regs if r.event == "PLAYER_REGEN_ENABLED"
                          and r.report and (r.key is None or r.key not in trackers)]

    def tok(self, k):
        return self.t[k] if 0 <= k < self.n else ("eof", "", 0)

    def rewrite_handlers(self):
        """A named function's first parameter is each frame it is a script handler of (one
        copy of the registration per frame); failing that, a colon method's self is its
        object. Then a field assigned a local is that local."""
        by_param = {pid: self.script_owners.get(ident) for ident, pid in self.fn_first.items()}
        regs = []
        for r in self.regs:
            root = r.key[0] if r.key and isinstance(r.key[0], tuple) else None
            pid = root[1] if root and root[0] == "local" else None
            owners = by_param.get(pid) if pid is not None else None
            if owners and all(o is not None for o in owners):
                for o in dict.fromkeys(owners):
                    c = Reg(r.event, (o[0], o[1] + r.key[1]), r.lines, r.line, r.report,
                            r.keyed, r.stmt)
                    c.span = r.span
                    regs.append(c)
                continue
            if pid in self.method_self:
                o = self.method_self[pid]
                r.key = (o[0], o[1] + r.key[1])
            regs.append(r)
        self.regs = regs
        for fkey, lkey in self.field_alias:
            n = len(fkey[1])
            for r in self.regs:
                if r.key and r.key[0] == fkey[0] and r.key[1][:n] == fkey[1]:
                    r.key = (lkey[0], lkey[1] + r.key[1][n:])

    def name_ident(self, a, b):
        """The identity of the function a name or name chain a..b refers to."""
        chain = chain_names(self.t[a:b + 1])
        if not chain or chain[0] == "_G":
            return None
        if len(chain) == 1:
            bnd = self.lookup(chain[0])
            return ("b", bnd.id) if bnd else ("g", chain[0])
        rk = self.receiver(b)[0]
        return ("k", rk) if rk else None

    def lookup(self, name):
        for scope in reversed(self.stack):
            bnd = scope.locals.get(name)
            if bnd is not None:
                return bnd
        return None

    def guarded(self, name):
        return any(name in names for _, names, _ in self.expr) or \
            any(name in s.guards for s in self.stack)

    def use(self, line, name, how):
        self.uses.append((line, name, how))
        self.use_stmt.append(self.cur)

    def reg(self, event, key, lines, line, report, keyed=False):
        holes = self.holes[self.cur]
        if holes:   # a callback written before the event is not part of the registration
            lines = [ln for ln in lines if not any(a < ln < b for a, b in holes)]
        self.regs.append(Reg(event, key, lines, line, report, keyed, self.cur))

    def in_table(self):
        """The walk is directly inside a table constructor (not in a function body in it)."""
        return bool(self.brackets) and self.brackets[-1][0] == "{" \
            and self.brackets[-1][2] == self.fn_level

    def lines_of(self, k):
        """Statement k's exception lines: its first to last line, less the inside of each
        function literal written in it (a statement there takes its own tag)."""
        first, last = self.stmts[k]
        holes = self.holes[k]
        return frozenset(ln for ln in range(first, last + 1)
                         if not any(a < ln < b for a, b in holes))

    def span_of(self, line):
        """The exception lines of the innermost statement holding a line."""
        if self._line_span is None:
            spans = {}
            for k in range(len(self.stmts)):
                lines = self.lines_of(k)
                for ln in lines:
                    old = spans.get(ln)
                    if old is None or len(lines) < len(old):
                        spans[ln] = lines
            self._line_span = spans
        return self._line_span.get(line, frozenset((line,)))

    def ascii_needs(self, line, comment_bad):
        """The exception lines each non-ASCII piece of a line needs: a string (or a stray
        character) its own statement's, a comment those of the statements owning a token
        on the line, else of the innermost statement holding it."""
        if self._by_line is None:
            by_line = {}
            for k, (kind, val, ln) in enumerate(self.t):
                for x in range(ln, ln + (val.count("\n") if kind == "string" else 0) + 1):
                    by_line.setdefault(x, []).append(k)
            self._by_line = by_line
        needs, owners = [], set()
        for k in self._by_line.get(line, ()):
            kind, val, ln = self.t[k]
            owners.add(self.owner[k])
            piece = val.split("\n")[line - ln] if kind == "string" else val
            if any(ord(c) > 127 for c in piece):
                needs.append(self.lines_of(self.owner[k]))
        if comment_bad:
            needs.append(frozenset().union(*(self.lines_of(s) for s in owners)) if owners
                         else self.span_of(line))
        return needs

    def new_statement(self, i, kind, s, prev, line):
        if s == ";":
            return not self.in_table()          # in a table it separates fields
        if (kind == "keyword" and s in STATEMENT_KEYS) or prev[0] == "eof":
            return True
        if prev[2] != line:
            return sym(prev) not in CONT_END and s not in CONT_START
        return (kind == "name" or s == "function") and ends_expr(prev)

    def walk(self):
        i = 0
        while i < self.n:
            while self.pending and self.pending[-1][0] <= i:
                _, scope, binds = self.pending.pop()
                scope.locals.update(binds)
            kind, val, line = self.t[i]
            s, prev = sym(self.t[i]), self.tok(i - 1)
            self.track_brackets(i, s)
            d = self.depth
            if self.new_statement(i, kind, s, prev, line):
                self.expr.clear()
                self.rhs_depth = None
                self.region[d] = self.or_region[d] = i if kind == "name" else i + 1
                # After then/do/else/repeat or ';' the statement proper starts at the next token
                self.stmt_start = i + 1 if s in ("then", "do", "else", "repeat", ";") else i
                self.stmts.append([line, line])
                self.holes.append([])
                self.stmt_tok.append(i)
                self.cur = len(self.stmts) - 1
            elif s in (",", ";"):
                self.expr[:] = [e for e in self.expr if e[0] < d]
                self.region[d] = self.or_region[d] = i + 1
            elif s == "or":
                # What the left side being false proves holds for the rest of the chain
                neg = prove(self.t[self.or_region.get(d, i):i], self.lookup)[1]
                self.expr[:] = [e for e in self.expr if e[0] < d or e[2] == "or"]
                if neg:
                    self.expr.append((d, neg, "or"))
                self.region[d] = self.or_region[d] = i + 1
            elif s == "and":
                pos = prove(self.t[self.region.get(d, i):i], self.lookup)[0]
                if pos:
                    self.expr.append((d, pos, "and"))
                self.region[d] = i + 1
            elif s in ("=", "in"):
                self.region[d] = self.or_region[d] = i + 1
                if s == "=" and not self.in_table():
                    self.rhs_depth = d
            stmt = self.stmts[self.cur]
            stmt[1] = max(stmt[1], line + (val.count("\n") if kind == "string" else 0))
            self.owner[i] = self.cur
            if kind == "keyword":
                nxt = self.keyword(i, val)
                for k in range(i + 1, nxt):
                    self.owner[k] = self.owner[i]      # a function header, local names
                i = nxt
                continue
            if kind == "string" and val in REGEN:
                self.regen_string(i)
            elif kind == "name":
                self.name(i)
            i += 1

    # -- expressions -------------------------------------------------------------
    def track_brackets(self, i, s):
        if s in OPENERS:
            rec = None
            if s == "(" and self.is_call_paren(i):
                rec = self.call_record(i)
            elif s == "{":
                # A table nested in a table counts as part of the outermost one (a list of
                # { event, handler } pairs). A table given to ipairs/pairs, or to a call that
                # plainly does not register (an unregister, a dispatcher), is reported only
                # once a loop or call registers it; any other one where it is written.
                parent = self.brackets[-1] if self.brackets else None
                if self.in_table() and parent[1]:
                    root, arg = parent[1]["root"], parent[1]["arg"]
                else:
                    call = parent[1] if parent and parent[0] == "(" \
                        and parent[2] == self.fn_level else None
                    root = i
                    arg = bool(call) and (call["name"] in ("ipairs", "pairs")
                                          or self.non_registering(call["name"]))
                rec = {"table": i, "strings": [], "root": root, "arg": arg}
            self.brackets.append((s, rec, self.fn_level))
            self.depth += 1
            self.region[self.depth] = self.or_region[self.depth] = i + 1
        elif s in CLOSERS:
            if self.brackets:
                _, rec, _ = self.brackets.pop()
                if rec is not None:
                    self.close_record(i, rec)
            self.depth -= 1
            self.expr[:] = [e for e in self.expr if e[0] <= self.depth]
        elif s == "," and self.brackets:
            _, rec, fn = self.brackets[-1]
            if rec is not None and "args" in rec and fn == self.fn_level:
                rec["args"].append((rec["arg_start"], i))
                rec["arg_start"] = i + 1

    def is_call_paren(self, i):
        prev = self.tok(i - 1)
        return prev[0] == "name" or sym(prev) in (")", "]")

    def global_ref(self, i):
        """(global, last token index, local name or None) when the expression at i names a
        watched global: X, a local copy of one, _G.X or _G["X"]."""
        kind, val, _ = self.t[i]
        if kind != "name":
            return None
        if val == "_G":
            a, b = self.tok(i + 1), self.tok(i + 2)
            if sym(a) == "." and b[0] == "name" and b[1] in WATCHED:
                return b[1], i + 2, None
            if sym(a) == "[" and b[0] == "string" and b[1] in WATCHED \
                    and sym(self.tok(i + 3)) == "]":
                return b[1], i + 3, None
            return None
        bnd = self.lookup(val)
        if bnd is None:
            return (val, i, None) if val in WATCHED else None
        return (bnd.alias, i, val) if bnd.alias else None

    def ref_name(self, toks):
        """The watched global a (parenthesized) reference names, or None."""
        while whole_paren(toks):
            toks = toks[1:-1]
        return ref_global(toks, self.lookup)

    def rhs_alias(self, a, b):
        """The watched global the expression a..b can evaluate to, so that a local holding
        it may be nil (or false) on WoW Forever, or None."""
        toks = self.t[a:b]
        while whole_paren(toks):
            toks = toks[1:-1]
        name = ref_global(toks, self.lookup)
        if name:
            return name
        parts = split_top(toks, "or")
        if len(parts) > 1:
            # X is reached only when every earlier operand can be false
            return None if any(always_truthy(p) for p in parts[:-1]) else self.ref_name(parts[-1])
        parts = split_top(toks, "and")
        return self.ref_name(parts[-1]) if len(parts) > 1 else None

    def chain_key(self, a, b):
        """The registrant a plain name chain a..b names (another name for it), or None."""
        chain = chain_names(self.t[a:b])
        if not chain or chain[0] == "_G":
            return None
        return self.receiver(b - 1)[0]

    def name(self, i):
        if sym(self.tok(i - 1)) in (".", ":"):
            return
        val = self.t[i][1]
        if val in REGEN and self.in_table() and sym(self.tok(i - 1)) in ("{", ",", ";") \
                and sym(self.tok(i + 1)) == "=":
            # { PLAYER_REGEN_ENABLED = handler }: a handler table's key
            self.reg(val, ("table", self.brackets[-1][1]["root"]), [self.t[i][2]], self.t[i][2],
                     False, True)
        if i == self.stmt_start:
            self.assignment(i)
            self.field_table(i)
            self.field_event(i)
            self.field_alias_of(i)
        ref = self.global_ref(i)
        if not ref or self.guarded(ref[0]):
            return
        gname, end, via = ref
        first = i
        if sym(self.tok(i - 1)) == "(" and self.pairs.get(i - 1) == end + 1 \
                and not self.is_call_paren(i - 1):
            first, end = i - 1, end + 1                # (X) as a value
        nxt, line = self.tok(end + 1), self.t[i][2]
        if sym(nxt) in ("(", "{") or nxt[0] == "string":
            self.use(line, gname, "copy-call" if via else "call")
        elif i not in self.handled and self.is_store(first, end):
            self.use(line, gname, "store")

    def assignment(self, i):
        """A statement assigning to plain names: a local whose new value can be a watched
        global becomes a copy of it (calls through it are judged like calls of the global),
        one given a plain name chain becomes another name for that registrant, one given a
        new object (CreateFrame(...)) a new registrant, and the event names and tables the
        value can hold join the ones it held."""
        j, targets = i, []
        while self.tok(j)[0] == "name" and sym(self.tok(j + 1)) in (",", "="):
            targets.append(self.tok(j)[1])
            if sym(self.tok(j + 1)) == "=":
                break
            j += 2
        else:
            return
        items, _ = self.expr_list(j + 2)
        for nm, (a, b) in zip(targets, items):
            bnd = self.lookup(nm)
            if not bnd:
                continue
            alias = self.rhs_alias(a, b)
            if alias:
                bnd.alias = alias
                continue
            ck = self.chain_key(a, b)
            if ck:
                bnd.key = ck
            elif self.new_object(a, b):
                bnd.ver += 1
                bnd.key = None
            fl = self.flow(a, b)
            if fl:
                self.merge(bnd, fl)

    def new_object(self, a, b):
        """The expression a..b is a call of a name chain (CreateFrame(...)): a new object."""
        o = self.open_of.get(b - 1) if b - a >= 3 and sym(self.t[b - 1]) == ")" else None
        return o is not None and o > a and chain_names(self.t[a:o]) is not None

    def split_idx(self, a, b, word):
        """The (first, after-last) ranges of a..b split at each top-level keyword word."""
        parts, start, depth, blocks = [], a, 0, 0
        for k in range(a, b):
            s = sym(self.t[k])
            if s in OPENERS:
                depth += 1
            elif s in CLOSERS:
                depth -= 1
            elif s == "function" or (blocks and s in ("if", "do", "repeat")):
                blocks += 1
            elif s in ("end", "until") and blocks:
                blocks -= 1
            if s == word and depth == 0 and blocks == 0:
                parts.append((start, k))
                start = k + 1
        parts.append((start, b))
        return parts

    def flow(self, a, b):
        """What the expression a..b can hold, as (event strings, handler keys, tables, is a
        string value, lines of its PLAYER_REGEN_* literals): a table constructor, a string,
        a local holding any of these, an element L[i] of a list or a field L.name of a
        record, and for and/or the union over what each operand can give."""
        while b - a >= 2 and sym(self.t[a]) == "(" and self.pairs.get(a) == b - 1:
            a, b = a + 1, b - 1
        if b <= a:
            return None
        parts = self.split_idx(a, b, "or")
        if len(parts) == 1:
            ands = self.split_idx(a, b, "and")
            return self.flow(*ands[-1]) if len(ands) > 1 else self.flow_atom(a, b)
        res = [r for r in (self.flow(x, y) for x, y in parts) if r]
        if not res:
            return None
        return (set().union(*(r[0] or () for r in res)) or None,
                set().union(*(r[1] or () for r in res)) or None,
                tuple(dict.fromkeys(t for r in res for t in (r[2] or ()))) or None,
                any(r[3] for r in res),
                sorted(set().union(*(r[4] or () for r in res))) or None)

    def flow_atom(self, a, b):
        tk = self.t[a]
        if sym(tk) == "{" and self.pairs.get(a) == b - 1:
            return self.table_strings(a, b - 1), self.table_keys(a, b - 1), (a,), False, None
        if b - a == 1 and tk[0] == "string":
            return ({tk[1]}, None, None, True, [tk[2]]) if tk[1] in REGEN else \
                (None, None, None, True, None)
        if tk[0] == "name" and sym(self.tok(a - 1)) not in (".", ":"):
            bnd = self.lookup(tk[1])
            if bnd is None or not (bnd.strings or bnd.keys or bnd.table is not None):
                return None
            tables = None if bnd.value else self.table_of(bnd)
            if b - a == 1:
                return bnd.strings, bnd.keys, tables, bnd.value, bnd.lines
            if (sym(self.tok(a + 1)) == "[" and self.pairs.get(a + 1) == b - 1) or \
                    (b - a == 3 and sym(self.tok(a + 1)) == "." and self.tok(a + 2)[0] == "name"):
                return bnd.strings, None, tables, False, None   # an element, a record's field
        return None

    def merge(self, bnd, fl):
        strings, keys, tables, value, lines = fl
        if strings:
            bnd.strings = (bnd.strings or set()) | strings
        if keys:
            bnd.keys = (bnd.keys or set()) | keys
        if tables:
            bnd.table = tuple(dict.fromkeys((bnd.table or ()) + tuple(tables)))
        bnd.value = bnd.value or value
        if lines:
            bnd.lines = sorted(set(bnd.lines or ()) | set(lines))

    def field_event(self, i):
        """T.PLAYER_REGEN_ENABLED = handler and T["PLAYER_REGEN_ENABLED"] = handler (a
        handler table's key), and EV[#EV + 1] = "EVENT" (an event appended to a list)."""
        a, b, c = self.tok(i + 1), self.tok(i + 2), self.tok(i + 3)
        if sym(a) == "." and b[0] == "name" and b[1] in REGEN and sym(c) == "=":
            self.table_key(self.t[i][1], b[1], b[2])
        elif sym(a) == "[":
            close = self.pairs.get(i + 1)
            if close is None or sym(self.tok(close + 1)) != "=":
                return
            if close == i + 3 and b[0] == "string" and b[1] in REGEN:
                self.table_key(self.t[i][1], b[1], b[2])
                return
            v = self.tok(close + 2)
            if v[0] == "string" and v[1] in REGEN:
                self.list_add(self.t[i][1], v[1], v[2])
        else:
            j = self.chain_end(i)
            close = self.pairs.get(j + 1) if j > i and sym(self.tok(j + 1)) == "[" else None
            if close is not None and sym(self.tok(close + 1)) == "=":
                v = self.tok(close + 2)
                if v[0] == "string" and v[1] in REGEN:
                    self.chain_list_add(j, v[1], v[2])     # inst.events[#inst.events + 1] = "E"

    def chain_end(self, i):
        """The last name of the chain a.b.c that starts at i."""
        j = i
        while sym(self.tok(j + 1)) == "." and self.tok(j + 2)[0] == "name":
            j += 2
        return j

    def field_table(self, i):
        """a.b = { ... }: that constructor is the field's list, so appends to the field join
        it (one list, as for a local); any other value ends it."""
        j = self.chain_end(i)
        if j == i or sym(self.tok(j + 1)) != "=":
            return
        rk = self.receiver(j)[0]
        if rk is None:
            return
        if sym(self.tok(j + 2)) == "{":
            self.field_tables[rk] = j + 2
        else:
            self.field_tables.pop(rk, None)

    def field_alias_of(self, i):
        """a.b = name, the whole statement: the field is another name for that local."""
        j = self.chain_end(i)
        v, nxt = self.tok(j + 2), self.tok(j + 3)
        if j == i or sym(self.tok(j + 1)) != "=" or v[0] != "name" \
                or not (nxt[0] == "eof" or sym(nxt) == ";" or nxt[2] != v[2]):
            return
        bnd = self.lookup(v[1])
        fkey = self.receiver(j)[0]
        if bnd and fkey:
            self.field_alias.append((fkey, bnd.key or (("local", bnd.id), ())))

    def chain_list_add(self, b, event, line):
        """An event appended to the list held in the field whose chain ends at b."""
        rk = self.receiver(b)[0]
        if rk is not None:
            self.reg(event, ("table", self.field_tables.get(rk, ("field", rk))), [line], line, True)

    def table_of(self, bnd):
        if bnd.table is None:
            bnd.table = (("b", bnd.id),)
        return bnd.table

    def table_key(self, tname, event, line):
        bnd = self.lookup(tname)
        if bnd:
            bnd.keys = (bnd.keys or set()) | {event}
            self.reg(event, ("table", self.table_of(bnd)[0]), [line], line, False, True)

    def list_add(self, tname, event, line):
        bnd = self.lookup(tname)
        if bnd:
            bnd.strings = (bnd.strings or set()) | {event}
            self.reg(event, ("table", self.table_of(bnd)[0]), [line], line, True)

    def is_store(self, i, end):
        """The reference at i..end is a whole value kept by an assignment or a table field."""
        ps = sym(self.tok(i - 1))
        table = self.in_table()
        if not (ps == "=" or (table and ps in ("{", ",", ";"))
                or (ps == "," and not table and self.rhs_depth == self.depth)):
            return False
        nxt = self.tok(end + 1)
        ns = sym(nxt)
        return ns in (",", ";", "}") or nxt[0] in ("eof", "name") or \
            (nxt[0] == "keyword" and ns in STATEMENT_START) or \
            (nxt[2] != self.t[end][2] and ns not in CONT_START)

    def expr_list(self, j):
        """The expressions of a list starting at j, as (first, after-last) index ranges, and
        the index where its statement ends."""
        t, items, start, depth, blocks, k = self.t, [], j, 0, 0, j
        while k < self.n:
            kind, _, line = t[k]
            s = sym(t[k])
            if depth == 0 and blocks == 0 and k > j:
                prev = t[k - 1]
                if s == ";" or (kind == "keyword" and s in STATEMENT_START and s != "function") \
                        or (s == "function" and ends_expr(prev)) \
                        or (prev[2] != line and sym(prev) not in CONT_END
                            and s not in CONT_START) \
                        or (prev[2] == line and kind == "name" and ends_expr(prev)):
                    break
            if s in OPENERS:
                depth += 1
            elif s in CLOSERS:
                if depth == 0:
                    break
                depth -= 1
            elif s == "function" or (blocks and s in ("if", "do", "repeat")):
                blocks += 1
            elif s in ("end", "until"):
                if blocks == 0:
                    break
                blocks -= 1
            elif s == "," and depth == 0 and blocks == 0:
                items.append((start, k))
                start = k + 1
            k += 1
        if start < k:
            items.append((start, k))
        return items, k

    def table_strings(self, a, close):
        """The string elements of the table constructor a..close."""
        found, depth = set(), 0
        for k in range(a + 1, close):
            s = sym(self.t[k])
            if s in OPENERS:
                depth += 1
            elif s in CLOSERS:
                depth -= 1
            elif depth == 0 and self.t[k][0] == "string" \
                    and sym(self.t[k - 1]) in ("{", ",", ";") \
                    and sym(self.tok(k + 1)) in (",", ";", "}"):
                found.add(self.t[k][1])
        return found or None

    def table_keys(self, a, close):
        """The event names the table constructor a..close holds as keys (NAME = or
        ["NAME"] =)."""
        found, depth = set(), 0
        for k in range(a + 1, close):
            tk, s = self.t[k], sym(self.t[k])
            if s == "[" and depth == 0 and self.tok(k + 1)[0] == "string" \
                    and sym(self.tok(k + 2)) == "]" and sym(self.tok(k + 3)) == "=" \
                    and self.tok(k + 1)[1] in REGEN:
                found.add(self.tok(k + 1)[1])
            if s in OPENERS:
                depth += 1
            elif s in CLOSERS:
                depth -= 1
            elif depth == 0 and tk[0] == "name" and tk[1] in REGEN \
                    and sym(self.t[k - 1]) in ("{", ",", ";") and sym(self.tok(k + 1)) == "=":
                found.add(tk[1])
        return found or None

    def until_kw(self, j, word):
        """The tokens from j up to the next top-level `word` keyword, and its index."""
        depth = blocks = 0
        k = j
        while k < self.n:
            s = sym(self.t[k])
            if s in OPENERS:
                depth += 1
            elif s in CLOSERS:
                depth -= 1
            elif s == "function" or (blocks and s in ("if", "do", "repeat")):
                blocks += 1
            elif s in ("end", "until") and blocks:
                blocks -= 1
            elif s == word and depth <= 0 and blocks == 0:
                break
            k += 1
        return self.t[j:k], k

    # -- statements and blocks ---------------------------------------------------
    def keyword(self, i, val):
        stack = self.stack
        if val == "function":
            return self.function(i)
        if val == "local":
            return self.local(i)
        if val in ("while", "for", "repeat"):
            scope = Scope(val)
            if val == "for":
                j, names = i + 1, []
                while self.tok(j)[0] == "name" or sym(self.tok(j)) == ",":
                    if self.tok(j)[0] == "name":
                        names.append(self.tok(j)[1])
                    j += 1
                for nm in names:
                    scope.locals[nm] = Binding(next(self.ids))
                if sym(self.tok(j)) == "in" and names:
                    strings, keys, table, by_key = self.iterated(j + 1)
                    if by_key and keys:
                        scope.locals[names[0]].keys = keys
                    if len(names) >= 2 and strings:
                        scope.locals[names[1]].strings = strings
                    # The header names the table, so editing it changes what is registered
                    do_at = self.until_kw(j + 1, "do")[1]
                    header = list(range(self.t[i][2], self.tok(do_at)[2] + 1)) \
                        if do_at < self.n else [self.t[i][2]]
                    for nm in names[:2]:
                        scope.locals[nm].table = table
                        if table is not None:
                            scope.locals[nm].lines = header
            elif val == "while":
                scope.pending = prove(self.until_kw(i + 1, "do")[0], self.lookup)[0]
            stack.append(scope)
        elif val == "do":
            top = stack[-1]
            if top.awaiting_do:
                top.awaiting_do = False
                if top.pending is not None:
                    top.guards |= top.pending
                    top.pending = None
            else:
                stack.append(Scope("do"))
        elif val == "if":
            self.open_branch(i, "if", set(), None)
        elif val == "then":
            top = stack[-1]
            if top.pending is not None:
                top.guards |= top.pending
                top.pending = None
            top.exits = i in self.exits
        elif val in ("elseif", "else"):
            later, chain = set(), None
            if stack[-1].kind in ("if", "elseif"):
                done = stack.pop()
                self.fall_through(done)
                later, chain = done.later, done.chain
            if val == "elseif":
                self.open_branch(i, "elseif", later, chain)
            else:
                scope = Scope("else", later)
                # An else with no if before it (a syntax error) gets a chain of its own
                scope.chain = chain if chain is not None else {"paths": [], "else": True}
                scope.chain["else"] = True
                scope.exits = i in self.exits
                stack.append(scope)
        elif val in ("end", "until"):
            self.close_block(i)
        return i + 1

    def handler_owner(self):
        """The frame whose script handler the function literal being opened is:
        X:SetScript("...", function(self, ...) and X:HookScript (its first parameter
        names X), or None."""
        if not self.brackets:
            return None
        kind, rec, fn = self.brackets[-1]
        if kind == "(" and rec and fn == self.fn_level and rec.get("kind") == "method" \
                and rec.get("name") in ("SetScript", "HookScript") and len(rec["args"]) == 1:
            return rec["key"]
        return None

    def function(self, i):
        j, method, owner = i + 1, False, None
        ident = self.fn_target.get(i)          # local F = function
        if self.tok(j)[0] == "name":
            j += 1
            while sym(self.tok(j)) in (".", ":") and self.tok(j + 1)[0] == "name":
                method = sym(self.tok(j)) == ":"
                if method:
                    owner = self.receiver(j - 1)[0]   # self names the object before ':'
                j += 2
            if j - i == 4 and self.t[i + 3][1] in REGEN:
                # function T.PLAYER_REGEN_ENABLED() / T:PLAYER_REGEN_ENABLED(): a handler key
                self.table_key(self.t[i + 1][1], self.t[i + 3][1], self.t[i + 3][2])
            if method:
                ident = ("k", (owner[0], owner[1] + (self.t[j - 1][1],))) if owner else None
            else:
                ident = self.name_ident(i + 1, j - 1)
        else:
            owner = self.handler_owner()
            if ident is None and sym(self.tok(i - 1)) == "=" and not self.in_table():
                k = i - 2                              # F = function, T.f = function
                while sym(self.tok(k - 1)) == "." and self.tok(k - 2)[0] == "name":
                    k -= 2
                if self.tok(i - 2)[0] == "name" and sym(self.tok(k - 1)) not in (".", ":", ","):
                    ident = self.name_ident(k, i - 2)
        scope = Scope("function")
        scope.fn_line = self.t[i][2]
        # What holds where the function is made holds in its body (it only runs once
        # made); the body's own statements start afresh.
        for _, names, _ in self.expr:
            scope.guards |= names
        scope.saved = (list(self.expr), dict(self.region), dict(self.or_region), self.depth,
                       self.rhs_depth, self.stmt_start, self.cur)
        self.expr.clear()
        first_bnd = None
        if method:
            # self is resolved after the walk: the frame when the method is a script handler,
            # else its object
            scope.locals["self"] = first_bnd = Binding(next(self.ids))
            if owner:
                self.method_self[first_bnd.id] = owner
        if sym(self.tok(j)) == "(":
            close = self.pairs.get(j, j)
            first = True
            for k in range(j + 1, close):
                if self.t[k][0] == "name":
                    bnd = scope.locals[self.t[k][1]] = Binding(next(self.ids))
                    if first and not method:
                        bnd.key = owner
                        first_bnd = bnd
                    first = False
            j = close + 1
        if ident is not None and first_bnd is not None:
            self.fn_first[ident] = first_bnd.id
        self.stack.append(scope)
        self.fn_level += 1
        return j

    def local(self, i):
        if sym(self.tok(i + 1)) == "function" and self.tok(i + 2)[0] == "name":
            self.stack[-1].locals[self.tok(i + 2)[1]] = Binding(next(self.ids))
            return i + 1
        j, names = i + 1, []
        while self.tok(j)[0] == "name":
            names.append(self.tok(j)[1])
            j += 1
            if sym(self.tok(j)) != ",":
                break
            j += 1
        binds = {nm: Binding(next(self.ids)) for nm in names}
        if sym(self.tok(j)) != "=":
            self.stack[-1].locals.update(binds)
            return j
        # The names come into scope only once the statement ends: inside its own
        # expressions they are still the globals.
        items, end = self.expr_list(j + 1)
        for nm, (a, b) in zip(names, items):
            alias = self.rhs_alias(a, b)
            if alias:
                binds[nm] = Binding(next(self.ids), alias=alias)
                # A plain copy is reported where it is made; any other way of making one
                # (cond and X, a or X) is judged at its calls.
                if self.ref_name(self.t[a:b]):
                    self.handled.update(range(a, b))
                    if alias in DEPRECATED and not self.guarded(alias):
                        self.use(self.t[a][2], alias, "alias")
            elif whole_function(self.t[a:b]):
                self.fn_target[a] = ("b", binds[nm].id)
            else:
                fl = self.flow(a, b)
                if fl:
                    self.merge(binds[nm], fl)
                binds[nm].key = self.chain_key(a, b)
        self.pending.append((end, self.stack[-1], binds))
        return j

    def iterated(self, j):
        """(strings, keys, tables, by key) for the table an ipairs/pairs loop header at j
        runs over; by key: pairs, whose first variable takes the table's keys."""
        nothing = (None, None, None, False)
        head = self.tok(j)
        if not (head[0] == "name" and head[1] in ("ipairs", "pairs") and sym(self.tok(j + 1)) == "("):
            return nothing
        close, a = self.pairs.get(j + 1), j + 2
        if close is None:
            return nothing
        by_key = head[1] == "pairs"
        fl = self.flow(a, close)
        if fl and not fl[3] and (fl[0] or fl[1] or fl[2]):
            return fl[0], fl[1], fl[2], by_key
        return nothing

    def open_branch(self, i, kind, later, chain):
        pos, neg = prove(self.until_kw(i + 1, "then")[0], self.lookup)
        scope = Scope(kind, later)
        scope.pending = pos
        scope.later = set(later) | neg
        scope.chain = chain if chain is not None else {"paths": [], "else": False}
        self.stack.append(scope)

    def fall_through(self, done):
        if done.chain is not None and not done.exits:
            done.chain["paths"].append(set(done.guards))

    def close_block(self, end_i=None):
        if len(self.stack) <= 1:
            return
        done = self.stack.pop()
        if done.kind == "function":
            self.fn_level -= 1
            if done.saved:
                (self.expr, self.region, self.or_region, self.depth, self.rhs_depth,
                 self.stmt_start, self.cur) = done.saved
            if end_i is not None:
                # The end belongs to the statement the function literal is written in,
                # not to a one-line statement of its own
                end_line = self.t[end_i][2]
                if self.stmt_tok[-1] == end_i and len(self.stmts) - 1 > self.cur:
                    self.stmts.pop()
                    self.holes.pop()
                    self.stmt_tok.pop()
                st = self.stmts[self.cur]
                st[1] = max(st[1], end_line)
                self.holes[self.cur].append((getattr(done, "fn_line", end_line), end_line))
                self.owner[end_i] = self.cur
        elif done.kind in ("if", "elseif", "else") and done.chain is not None:
            # After the chain, only what every branch that falls through knows (and,
            # with no else, what each condition being false proves) still holds.
            self.fall_through(done)
            paths = list(done.chain["paths"])
            if not done.chain["else"]:
                paths.append(set(done.later))
            if paths:
                self.stack[-1].guards |= set.intersection(*paths)
        elif done.kind == "do":
            # A plain do block always runs to its end (or leaves): what it proved holds after
            self.stack[-1].guards |= done.guards

    # -- registrations -----------------------------------------------------------
    def receiver(self, k):
        """(key, first index) of the name chain ending at k: key is (root, the rest as
        text), the root being the registrant's binding (or the binding it is another name
        for) or global name; None when the chain is part of a longer expression."""
        parts, j = [], k
        while j >= 0:
            tk = self.t[j]
            if tk[0] == "name":
                parts.append(tk[1])
                if sym(self.tok(j - 1)) == "." and (self.tok(j - 2)[0] == "name"
                                                    or sym(self.tok(j - 2)) == "]"):
                    j -= 2
                    continue
                break
            if sym(tk) == "]" and j in self.open_of:
                o = self.open_of[j]
                parts.append("[" + " ".join(x[1] for x in self.t[o + 1:j]) + "]")
                j = o - 1
                continue
            return None, k
        if j < 0 or not parts or sym(self.tok(j - 1)) in (".", ":"):
            return None, max(j, 0)
        parts.reverse()
        bnd = self.lookup(parts[0])
        if bnd and bnd.key:
            root, rest = bnd.key
            return (root, rest + tuple(parts[1:])), j
        if not bnd:
            root = ("global", parts[0])
        else:
            root = ("local", bnd.id, bnd.ver) if bnd.ver else ("local", bnd.id)
        return (root, tuple(parts[1:])), j

    def arg_key(self, rec, idx):
        if idx >= len(rec["args"]):
            return None
        a, b = rec["args"][idx]
        return self.receiver(b - 1)[0] if b > a else None

    def call_record(self, i):
        """The callee of the call whose argument list opens at i."""
        k = i - 1
        prev = self.t[k]
        rec = {"args": [], "arg_start": i + 1, "first": k,
               "name": prev[1] if prev[0] == "name" else None, "key": None, "kind": "call"}
        if prev[0] == "name" and sym(self.tok(k - 1)) == ":":
            rec["kind"] = "method"
            rec["key"], rec["first"] = self.receiver(k - 2)
        elif prev[0] == "name" and sym(self.tok(k - 1)) == ".":
            rec["kind"] = "field"
        j = k
        while sym(self.tok(j - 1)) in (".", ":") and self.tok(j - 2)[0] == "name":
            j -= 2
        rec["text"] = "".join(x[1] for x in self.t[j:k + 1])
        rec["first"] = min(rec["first"], j)
        return rec

    def event_arg(self, rec, idx):
        """Argument idx is an event name: a REGEN string, or a name holding event names."""
        if idx >= len(rec["args"]):
            return False
        a, b = rec["args"][idx]
        if b - a != 1:
            return False
        tk = self.t[a]
        if tk[0] == "string":
            return tk[1] in REGEN
        bnd = tk[0] == "name" and self.lookup(tk[1])
        return bool(bnd and (bnd.strings or bnd.keys))

    def registers(self, name, rec):
        """A helper that registers the events it is given: Register or Event in its name;
        not an unregister or a dispatcher, judged by the leading word of the name or of its
        last _ part, any case (OnEvent, onEvent, Watcher_OnEvent, TriggerEvent,
        IsEventRegistered); a name without Register must take the event first and must not
        end in Valid (handler(frame, event), EventValid(event)); and no literal false or
        nil among its arguments (SetEvent(event, false))."""
        if not name or ("Register" not in name and "Event" not in name):
            return False
        if self.non_registering(name):
            return False
        if "Register" not in name and (name.endswith("Valid")
                                       or (rec["args"] and not self.event_first(rec))):
            return False
        return not any(b - a == 1 and sym(self.t[a]) in ("false", "nil") for a, b in rec["args"])

    def non_registering(self, name):
        """The name (or its last _ part) leads with an unregister or dispatcher word."""
        if not name:
            return False
        for part in (name, name.rsplit("_", 1)[-1]):
            words = WORD_RE.findall(part)
            if words and words[0].lower() in DISPATCH_LEAD:
                return True
        return False

    def event_first(self, rec):
        """The first argument can be an event: a string, or a local holding event names."""
        a, b = rec["args"][0]
        if b - a != 1:
            return False
        tk = self.t[a]
        if tk[0] == "string":
            return True
        bnd = tk[0] == "name" and self.lookup(tk[1])
        return bool(bnd and (bnd.strings or bnd.keys))

    def close_record(self, close, rec):
        if "table" in rec:
            for k in rec["strings"]:
                ev, line = self.t[k][1], self.t[k][2]
                self.reg(ev, ("table", rec["root"]), [line], line, not rec["arg"], rec["arg"])
            return
        if rec["arg_start"] < close:
            rec["args"].append((rec["arg_start"], close))
        name, args = rec["name"], rec["args"]
        if name in ("SetScript", "HookScript") and rec["kind"] == "method" and len(args) >= 2:
            a, b = args[1]                         # X:SetScript("OnEvent", handler)
            ident = self.name_ident(a, b - 1) if b > a else None
            if ident is not None:
                self.script_owners.setdefault(ident, []).append(rec["key"])
        if name in ("RegisterEvent", "RegisterUnitEvent"):
            if rec["kind"] == "method":
                self.reg_arg(rec, 0, rec["key"])
            elif rec["kind"] == "field" and not self.event_arg(rec, 0):
                self.reg_arg(rec, 1, self.arg_key(rec, 0))     # frame.RegisterEvent(frame, ev)
            else:
                self.reg_arg(rec, 0, ("call", rec["text"]))    # an event helper of that name
        elif name in ("pcall", "xpcall", "securecall") and args:
            a, b = args[0]
            chain = chain_names(self.t[a:b])
            if chain and chain[-1] in ("RegisterEvent", "RegisterUnitEvent"):
                skip = 1 if name == "xpcall" else 0           # xpcall(f, handler, ...)
                self.reg_arg(rec, 2 + skip, self.arg_key(rec, 1 + skip))
        elif name == "hooksecurefunc" and args:
            k = 1 if self.t[args[0][0]][:2] == ("name", "_G") and args[0][1] - args[0][0] == 1 else 0
            if len(args) > k and args[k][1] - args[k][0] == 1:
                tk = self.t[args[k][0]]
                if tk[0] == "string" and tk[1] in WATCHED and not self.guarded(tk[1]):
                    self.use(tk[2], tk[1], "hook")
        elif name == "tinsert" or rec["text"] == "table.insert":
            if len(args) >= 2 and args[-1][1] - args[-1][0] == 1:
                (a0, b0), v = args[0], self.t[args[-1][0]]
                if v[0] == "string" and v[1] in REGEN:     # an event appended to a list
                    if b0 - a0 == 1 and self.t[a0][0] == "name":
                        self.list_add(self.t[a0][1], v[1], v[2])
                    elif chain_names(self.t[a0:b0]):
                        self.chain_list_add(b0 - 1, v[1], v[2])
        elif self.registers(name, rec):
            idxs = [0] if name in CALLBACK_REGS else range(len(args))
            claim = not self.tested(rec, close)    # a call used as a condition owns no table
            for idx in idxs:                       # an event helper, EventRegistry
                self.reg_arg(rec, idx, ("call", rec["text"]), claim)

    def tested(self, rec, close):
        """The call's result is tested (if f(x) then, f(x) and ...): a predicate."""
        before, after = sym(self.tok(rec["first"] - 1)), sym(self.tok(close + 1))
        return before in ("if", "elseif", "while", "until", "and", "or", "not") or \
            after in ("then", "and", "or")

    def reg_arg(self, rec, idx, key, claim=True):
        if idx >= len(rec["args"]):
            return
        a, b = rec["args"][idx]
        tk = self.t[a]
        lines = range(self.t[rec["first"]][2], self.t[b - 1][2] + 1)
        if b - a == 1 and tk[0] == "string":
            if tk[1] in REGEN:
                self.reg(tk[1], key, lines, tk[2], True)
            return
        # Anything else that can hold event names: a name (a constant, a list, a handler
        # table or a loop variable over one), L[i], a record's field, a table written in
        # the call, an and/or choice
        fl = self.flow(a, b)
        if not fl:
            return
        strings, keys, tables, value, flines = fl
        if flines:
            lines = list(lines) + [ln for ln in flines if ln not in lines]
        for ev in sorted((set(strings or ()) | set(keys or ())) & set(REGEN)):
            # A string value is reported here; a list or a handler table where it is
            # written, owned by this registrant
            self.reg(ev, key, lines, tk[2], value)
        if claim and key is not None and not value and tables:
            bnd = self.lookup(tk[1]) if tk[0] == "name" else None
            for t in tables:
                self.table_owner.setdefault(t, []).append((key, list(lines), bnd and bnd.id))

    def regen_string(self, i):
        prev, nxt = self.tok(i - 1), self.tok(i + 1)
        if prev[0] == "name" and prev[1] in ("RegisterEvent", "RegisterUnitEvent") \
                and sym(self.tok(i - 2)) == ":":           # f:RegisterEvent "EVENT"
            key, first = self.receiver(i - 3)
            line = self.t[i][2]
            self.reg(self.t[i][1], key, range(self.t[first][2], line + 1), line, True)
            return
        if sym(prev) == "[" and sym(nxt) == "]" and sym(self.tok(i + 2)) == "=" \
                and len(self.brackets) >= 2 and self.brackets[-2][0] == "{" \
                and self.brackets[-2][2] == self.fn_level and self.brackets[-2][1]:
            # { ["PLAYER_REGEN_ENABLED"] = handler }: a handler table's key
            line = self.t[i][2]
            self.reg(self.t[i][1], ("table", self.brackets[-2][1]["root"]), [line], line, False,
                     True)
            return
        if self.in_table():
            rec = self.brackets[-1][1]
            if rec is not None and sym(prev) in ("{", ",", ";") and sym(nxt) in (",", ";", "}"):
                rec["strings"].append(i)                 # an event list
            elif rec is not None and sym(prev) == "=" and self.tok(i - 2)[0] == "name" \
                    and sym(self.tok(i - 3)) in ("{", ",", ";") and sym(nxt) in (",", ";", "}"):
                # { event = "PLAYER_REGEN_ENABLED" }: a record's field, reported once a loop
                # or call registers its table
                line = self.t[i][2]
                self.reg(self.t[i][1], ("table", rec["root"]), [line], line, False, True)


class FailedAnalysis:
    """Stands in for a file the analysis could not walk (a syntax error, or a bug here)."""

    def __init__(self, error):
        self.error, self.uses, self.spans, self.deferrals = error, [], [], []

    def span_of(self, line):
        return frozenset((line,))

    def ascii_needs(self, line, comment_bad):
        return []


def unsafe_global_uses(tokens):
    """(line, global, how) for each unguarded use of a watched global (see Analysis)."""
    return Analysis(tokens).uses


# ---------------------------------------------------------------------------
# Checks on changed lines
# ---------------------------------------------------------------------------
def check_combat_deferral(change, errors):
    """Work deferred to combat end goes through the shared combat queue. A registrant that
    registers both PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED tracks combat state,
    which is not a deferral."""
    for path, added in change.added_by_path.items():
        if b"PLAYER_REGEN_ENABLED" not in change.read(path):
            continue
        for reg in change.analysis(path, errors).deferrals:
            if not any(ln in added for ln in reg.lines):
                continue
            lines = sorted(set(reg.lines) | reg.span)
            if allowed(change, "combat-deferral", path, lines, errors):
                continue
            # At the event, or at the registration's first new line when the event is old
            line = reg.line if reg.line in added else next(ln for ln in reg.lines if ln in added)
            errors.append(Error(path, line, "new PLAYER_REGEN_ENABLED registration. Defer "
                                "with EllesmereUI.CombatQueue.Defer(key, fn) in the parent "
                                "addon, or the child's ns.CombatQueue (EllesmereUI.NewCombatQueue, "
                                "EllesmereUI_Ticker.lua)"))


def forever_listed(types):
    names = {x.strip().lower() for x in types.split(",")}
    return "camelot" in names or "mainline" in names


def toc_allows(toc, rel):
    """Whether WoW Forever loads the addon of a TOC, and the file rel in it."""
    toc = toc.lstrip("\ufeff")
    addon = True
    m = re.search(r"^##\s*AllowLoadGameType:\s*(.+?)\s*$", toc, re.M)
    if m and not forever_listed(m.group(1)):
        addon = False
    m = re.search(r"^##\s*ExcludeLoadGameType:\s*(.+?)\s*$", toc, re.M)
    if m and forever_listed(m.group(1)):
        addon = False
    for line in toc.splitlines():
        m = re.match(r"\s*([^#\s][^\[]*?)\s*\[(Allow|Exclude)LoadGameType\s+([^\]]+)\]", line)
        if m and m.group(1).replace("\\", "/") == rel:
            listed = forever_listed(m.group(3))
            if listed != (m.group(2) == "Allow"):
                return addon, False
    return addon, True


def forever_skips(change, path):
    """True for a file WoW Forever never loads: the TOC Forever reads for its addon
    (<Addon>_Camelot.toc, then _Mainline, then the plain one) excludes camelot, or lists
    the file for other game types only."""
    folder, _, rel = path.partition("/") if "/" in path else ("", "", path)
    if folder not in change.skips:
        names = set(change.list_dir(folder))
        if folder:
            order = [f"{folder}_Camelot.toc", f"{folder}_Mainline.toc", f"{folder}.toc"]
        else:
            tocs = sorted(n for n in names if n.endswith(".toc"))
            order = [n for n in tocs if n.endswith("_Camelot.toc")] + \
                [n for n in tocs if n.endswith("_Mainline.toc")] + tocs
        found = next((n for n in order if n in names), None)
        change.skips[folder] = change.read(f"{folder}/{found}" if folder else found).decode(
            "utf-8", "replace") if found else None
    toc = change.skips[folder]
    if toc is None:
        return False
    addon, file_ok = toc_allows(toc, rel)
    return not (addon and file_ok)


def deprecated_message(name, how):
    if name in NIL_GUARD:
        return (f"{name} is nil on WoW Forever and has no C_ form; guard it "
                f"(if {name} then ... end) and fall through to no spec")
    target = DEPRECATED[name]
    if how == "alias":
        return (f"local alias of {name}, which is nil on WoW Forever; alias "
                f"{target.split(' ')[0]} instead")
    if how == "copy-call":
        return f"calls a local copy of {name}, which is nil on WoW Forever; use {target}"
    if how == "store":
        return f"stores {name}, which is nil on WoW Forever; use {target}"
    if how == "hook":
        return f"hooks {name}, which is nil on WoW Forever; hook {target.split(' ')[0]} instead"
    return f"bare {name} is nil on WoW Forever; use {target}"


def check_deprecated_globals(change, errors):
    """Globals that are nil on WoW Forever, used with nothing guarding them."""
    for path, added in change.added_by_path.items():
        if not WATCHED_RE.search(change.read(path).decode("utf-8", "replace")):
            continue
        if forever_skips(change, path):
            continue
        found = change.analysis(path, errors)
        for (line, name, how), span in zip(found.uses, found.spans):
            if line not in added:
                continue
            if allowed(change, "deprecated-global", path, sorted(span), errors):
                continue
            errors.append(Error(path, line, deprecated_message(name, how)))


def check_ascii(change, errors):
    """CONTRIBUTING.md: ASCII only in code; multi-byte text corrupts in packaging."""
    for path, lineno, text in change.added_lines:
        if path.startswith("EllesmereUILocales/"):
            continue
        if lineno == 1 and text.startswith("\ufeff"):
            errors.append(Error(path, 1, "file starts with a UTF-8 BOM; save it as UTF-8 "
                                         "without a BOM"))
            text = text[1:]
        bad = sorted({c for c in text if ord(c) > 127})
        if not bad or allowed(change, "ascii", path, [lineno], errors):
            continue
        # The exception may sit on another line of the statement that owns each non-ASCII
        # piece (a table or a call, never across a function body written in it)
        needs = change.analysis(path, errors).ascii_needs(
            lineno, any(ord(c) > 127 for c in change.comment(path, lineno)))
        if needs and all(allowed(change, "ascii", path, sorted(n), errors) for n in needs):
            continue
        shown = ", ".join(f"U+{ord(c):04X}" for c in bad)
        errors.append(Error(path, lineno, f"non-ASCII character(s) {shown}; use ASCII (-- for "
                                          f"a dash, plain quotes) or a byte escape such as "
                                          f"\\226\\128\\148"))


def check_exception_tags(change, errors):
    """Malformed, unknown or badly dated exceptions that start on new lines, and expired
    ones anywhere in the tree."""
    for path, added in change.added_by_path.items():
        if not any("guardrails-allow" in text for text in added.values()):
            continue
        for line, tag in change.lex(path)[1].tags():
            if line in added:
                for problem in tag_problems(tag):
                    errors.append(Error(path, line, problem))
    today = utc_today()
    for path in change.grep(r"guardrails-allow:.*until"):
        for line, tag in change.lex(path)[1].tags():
            date = parse_date(tag.group("date")) if tag and tag.group("date") else None
            if date and date < today:
                errors.append(Error(path, line, expired_message(tag.group("check"),
                                                                tag.group("date"))))


def check_paths(change, errors):
    """File names git and the other checks can read back."""
    for path in change.bad_names:
        errors.append(Error(path, None, "file name is not valid UTF-8; rename it"))


CHECKS = [check_paths, check_compile, check_client_gate, check_combat_deferral,
          check_deprecated_globals, check_ascii, check_exception_tags]


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--base", default=None)
    ap.add_argument("--head", default=None)
    args = ap.parse_args()
    errors = []
    try:
        base = args.base or default_base()
        note = None if args.base else base_note(base)
        if note:
            print(f"guardrails: {note}", file=sys.stderr)
        change = Change(base, args.head)
        for check in CHECKS:
            check(change, errors)
    except GitError as e:
        print(f"guardrails: {e}", file=sys.stderr)
        return 2
    seen, unique = set(), []
    for e in errors:
        if str(e) not in seen:
            seen.add(str(e))
            unique.append(e)
    actions = os.environ.get("GITHUB_ACTIONS")
    for e in unique:
        print(e.annotation() if actions else str(e))
    if unique:
        print(f"{len(unique)} guardrail error(s).")
        return 1
    print(f"guardrails OK ({len(change.lua_files)} Lua files, "
          f"{len(change.added_lines)} added lines).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
