"""Tests for .tools/guardrails.py: each check against small Lua sources, the
repository-level ones in a scratch git repository.

Run: python .tools/tests/test_guardrails.py  (needs git; the compile tests also need
a Lua 5.1 luac -- luac5.1 on PATH, or LUAC=/path/to/luac -- and are skipped without one)
"""
import datetime
import importlib.util
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True    # no __pycache__ left in .tools
_spec = importlib.util.spec_from_file_location("guardrails", ROOT / ".tools" / "guardrails.py")
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)

GATE = "if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)\n"
LUAC = os.environ.get("LUAC", "luac5.1")


def uses(src):
    """The unguarded uses of watched globals in a Lua source, as (line, name)."""
    return [(line, name) for line, name, _ in g.unsafe_global_uses(g.lua_tokens(src))]


def names(src):
    return [name for _, name in uses(src)]


class Repo:
    """A scratch git repository the checks run against."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix="guardrails-test-")
        self.git("init", "-q")
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        for key, value in (("user.email", "test@example.invalid"), ("user.name", "test"),
                           ("commit.gpgsign", "false"), ("core.autocrlf", "false"),
                           ("core.hooksPath", "no-hooks")):
            self.git("config", key, value)

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.dir, check=True, capture_output=True,
                              text=True).stdout

    def write(self, path, text):
        p = Path(self.dir, path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(text.encode("utf-8"))

    def commit(self, message="change"):
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD").strip()

    def check(self, base, head=None, checks=None):
        """Errors the checks report for base..head (head None: the working tree)."""
        saved = g.ROOT
        g.ROOT = self.dir
        try:
            change = g.Change(base, head)
            errors = []
            for check in checks or [c for c in g.CHECKS if c is not g.check_compile]:
                check(change, errors)
            seen = []
            for e in map(str, errors):
                if e not in seen:
                    seen.append(e)
            return seen
        finally:
            g.ROOT = saved

    def close(self):
        def unlock(func, path, _):
            os.chmod(path, stat.S_IWRITE)    # git leaves its objects read-only on Windows
            func(path)
        handler = "onexc" if sys.version_info >= (3, 12) else "onerror"
        shutil.rmtree(self.dir, **{handler: unlock})


class RepoCase(unittest.TestCase):
    def setUp(self):
        self.repo = Repo()
        self.repo.write("Base.lua", GATE + "local x = 1\n")
        self.base = self.repo.commit("base")

    def tearDown(self):
        self.repo.close()

    def errors_for(self, path, body, checks=None):
        """Errors for a new file holding the gate line and body, against the commit before it."""
        before = self.repo.git("rev-parse", "HEAD").strip()
        self.repo.write(path, GATE + body)
        return self.repo.check(before, self.repo.commit(), checks)


class Tokens(unittest.TestCase):
    def test_strings_and_comments_are_not_code(self):
        toks = g.lua_tokens('local s = "a -- b" -- c\n--[==[ x\n]==] y = [[\nz]] w')
        self.assertEqual([t[1] for t in toks if t[0] != "string"], ["local", "s", "=", "y", "=", "w"])
        self.assertEqual([t[1] for t in toks if t[0] == "string"], ["a -- b", "\nz"])

    def test_lines_count_through_comments_and_strings(self):
        toks = g.lua_tokens('--[[\n\n]]\nlocal a = "x\\\ny"\nb = 1\r\nc = 2')
        line_of = {t[1]: t[2] for t in toks}
        self.assertEqual((line_of["local"], line_of["b"], line_of["c"]), (4, 6, 7))

    def test_escaped_quote_stays_in_the_string(self):
        toks = g.lua_tokens(r'x = "a\"GetItemInfo(1)" y = 2')
        self.assertEqual([t[1] for t in toks if t[0] == "name"], ["x", "y"])


class DeprecatedGlobals(unittest.TestCase):
    """unsafe_global_uses: the analysis behind check_deprecated_globals."""

    def test_bare_call(self):
        self.assertEqual(uses("local id = GetSpecialization()"), [(1, "GetSpecialization")])

    def test_call_forms(self):
        self.assertEqual(names('GetItemInfo "x"\nGetItemInfo{}\nGetItemCount(1)'),
                         ["GetItemInfo", "GetItemInfo", "GetItemCount"])

    def test_text_in_strings_and_comments(self):          # author P2 1
        src = ('print("GetSpecialization()")\n'
               "-- GetSpecialization()\n"
               "--[[ GetItemInfo(1)\n GetItemInfo(2) ]]\n"
               "local s = [[ GetItemInfo(3) ]] .. 'GetItemInfo(4)'\n")
        self.assertEqual(uses(src), [])

    def test_namespaced_method_and_field_uses(self):
        src = ("C_Item.GetItemInfo(1)\nobj:GetItemInfo(2)\nt.GetSpecialization()\n"
               "local t = { GetItemInfo = 1 }\nlocal f = GetItemInfo\n")
        self.assertEqual(uses(src), [(5, "GetItemInfo")])

    def test_alias_forms(self):                           # author P2 2, A2
        for alias in (
                "local GetSpecialization = (C_SpecializationInfo and "
                "C_SpecializationInfo.GetSpecialization) or GetSpecialization",
                "local GetSpecialization = GetSpecialization or function() return nil end",
                "local GetSpecialization = C_SpecializationInfo.GetSpecialization",
                "local GetSpecialization = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization"):
            with self.subTest(alias=alias):
                self.assertEqual(uses(alias + "\nlocal id = GetSpecialization()\n"), [])

    def test_pure_alias(self):
        # The copy is reported, and so is every unguarded call through it: it is nil too.
        hits = g.unsafe_global_uses(g.lua_tokens("local GetItemInfo = GetItemInfo\nGetItemInfo(1)\n"))
        self.assertEqual(hits, [(1, "GetItemInfo", "alias"), (2, "GetItemInfo", "copy-call")])

    def test_alias_is_scoped(self):                       # author P2 3
        src = ("local function a()\n"
               "    local GetSpecialization = C_SpecializationInfo.GetSpecialization\n"
               "    return GetSpecialization()\n"
               "end\n"
               "local function b()\n"
               "    return GetSpecialization()\n"
               "end\n"
               "do local GetItemInfo = C_Item.GetItemInfo end\n"
               "GetItemInfo(1)\n")
        self.assertEqual(uses(src), [(6, "GetSpecialization"), (9, "GetItemInfo")])

    def test_later_local_does_not_cover_earlier_calls(self):
        src = ("local function f() return GetItemInfo(1) end\n"
               "local GetItemInfo = C_Item.GetItemInfo\n"
               "GetItemInfo(2)\n")
        self.assertEqual(uses(src), [(1, "GetItemInfo")])

    def test_parameters_and_loop_variables_bind(self):
        src = ("local function f(a, GetItemInfo) return GetItemInfo(a) end\n"
               "for _, GetSpecialization in ipairs(t) do GetSpecialization() end\n"
               "for GetItemCount = 1, 2 do GetItemCount() end\n")
        self.assertEqual(uses(src), [])

    def test_existence_guards(self):                      # A1
        for src in (
                "if GetSpecializationInfoByID then GetSpecializationInfoByID(1) end",
                "if x and GetSpecializationInfoByID then GetSpecializationInfoByID(1) end",
                "if GetSpecializationInfoByID ~= nil then GetSpecializationInfoByID(1) end",
                "local n = GetSpecializationInfoByID and GetSpecializationInfoByID(1)",
                "local n = GetSpecializationInfoByID and select(2, GetSpecializationInfoByID(1))",
                "local n = GetSpecializationInfoByID ~= nil and GetSpecializationInfoByID(1)",
                "local function f()\n if not GetSpecializationInfoByID then return end\n"
                " return GetSpecializationInfoByID(1)\nend",
                "local n = GetItemInfo and\n    GetItemInfo(1)",
                "local n = GetItemInfo\n    and GetItemInfo(1)",
                "local function f()\n if not GetItemInfo then print(1) return end\n"
                " return GetItemInfo(1)\nend"):
            with self.subTest(src=src):
                self.assertEqual(uses(src), [])

    def test_guard_ends_where_lua_stops_short_circuiting(self):
        for src in (
                "if GetItemInfo then end\nGetItemInfo(1)",
                "local a = GetItemInfo and 1\nGetItemInfo(2)",
                "local a = GetItemInfo and 1; GetItemInfo(2)",
                "local a = GetItemInfo and x or GetItemInfo(1)",
                "f(GetItemInfo and 1, GetItemInfo(2))",
                "local t = { a = GetItemInfo and 1, b = GetItemInfo(2) }",
                "local a = (GetItemInfo and 1) + GetItemInfo(2)",
                "local a = not GetItemInfo and GetItemInfo(1)",
                "local a = x == GetItemInfo and GetItemInfo(1)",
                "if not GetItemInfo and x then return end\nGetItemInfo(1)",
                "if GetItemInfo then else GetItemInfo(1) end",
                "if GetSpecialization() and not EllesmereUI.IS_FOREVER then end"):
            with self.subTest(src=src):
                self.assertEqual(len(uses(src)), 1)

    def test_a_guard_covers_its_family_only(self):
        self.assertEqual(uses("if GetSpecialization then GetSpecializationInfo(1) "
                              "GetSpecializationInfoByID(2) end"), [])
        self.assertEqual(uses("if GetItemInfo then GetItemCount(1) end"), [])
        self.assertEqual(names("if GetItemInfo then GetSpecialization() end"), ["GetSpecialization"])
        # GetSpecializationInfoByID is native on retail, so it proves nothing about the
        # deprecation fallbacks.
        self.assertEqual(names("if GetSpecializationInfoByID then GetSpecialization() end"),
                         ["GetSpecialization"])

    def test_forever_flag(self):
        for src in (
                "if EllesmereUI.IS_FOREVER then return end\nGetSpecialization()",
                "if EllesmereUI and EllesmereUI.IS_FOREVER then return end\nGetSpecialization()",
                "if EllesmereUI.IS_FOREVER == true then return end\nGetSpecialization()",
                "if not EllesmereUI.IS_FOREVER then GetSpecialization() end",
                "if not EABR.FOREVER and x then GetItemInfo(1) end",
                "if IS_FOREVER then x() else GetSpecialization() end",
                "if IS_FOREVER then x() elseif y then GetSpecialization() end",
                "local s = not EllesmereUI.IS_FOREVER and GetSpecialization()"):
            with self.subTest(src=src):
                self.assertEqual(uses(src), [])
        for src in (
                "if EllesmereUI.IS_FOREVER and x then return end\nGetSpecialization()",
                "if not EllesmereUI.IS_FOREVER then return end\nGetSpecialization()",
                "if IS_FOREVER and x then y() else GetSpecialization() end",
                "if EllesmereUI.IS_FOREVER then GetSpecialization() end"):
            with self.subTest(src=src):
                self.assertEqual(names(src), ["GetSpecialization"])

    def test_namespaced_fallback_branch(self):
        self.assertEqual(uses(
            "if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then\n"
            "    x = C_SpecializationInfo.GetSpecialization()\n"
            "else\n"
            "    x = GetSpecialization()\n"
            "end"), [])
        self.assertEqual(names("if C_Item.GetItemInfo and y then z() else GetItemInfo(1) end"),
                         ["GetItemInfo"])


class DeprecatedGlobalsInRepo(RepoCase):
    def test_messages(self):
        errors = self.errors_for("A.lua", "GetSpecializationInfoByID(1)\nGetItemIcon(2)\n"
                                          "local GetItemCount = GetItemCount\n",
                                 [g.check_deprecated_globals])
        self.assertEqual(len(errors), 3)
        self.assertTrue(errors[0].startswith(
            "A.lua:2: GetSpecializationInfoByID is nil on WoW Forever and has no C_ form"))
        self.assertTrue(errors[1].startswith(
            "A.lua:3: bare GetItemIcon is nil on WoW Forever; use C_Item.GetItemIconByID"))
        self.assertTrue(errors[2].startswith(
            "A.lua:4: local alias of GetItemCount, which is nil on WoW Forever; "
            "alias C_Item.GetItemCount instead"))

    def test_review_repros(self):                         # author P2 1-3
        self.assertEqual(self.errors_for("A.lua", 'local s = "GetSpecialization()"\n'
                                                  "--[[\nGetItemInfo(1)\n]]\n"), [])
        self.assertEqual(self.errors_for(
            "B.lua", "local GetSpecialization = (C_SpecializationInfo and "
                     "C_SpecializationInfo.GetSpecialization) or GetSpecialization\n"
                     "local id = GetSpecialization()\n"), [])
        errors = self.errors_for("C.lua", "local function a()\n"
                                          "    local GetItemInfo = C_Item.GetItemInfo\n"
                                          "    return GetItemInfo(1)\n"
                                          "end\n"
                                          "local name = GetItemInfo(2)\n")
        self.assertEqual([e.split(": ")[0] for e in errors], ["C.lua:6"])

    def test_only_added_lines_count(self):
        self.repo.write("Old.lua", GATE + "GetItemInfo(1)\nlocal y = 1\n")
        base = self.repo.commit()
        self.repo.write("Old.lua", GATE + "GetItemInfo(1)\nlocal y = 2\n")
        self.assertEqual(self.repo.check(base, self.repo.commit()), [])
        self.repo.write("Old.lua", GATE + "GetItemInfo(3)\nlocal y = 2\n")
        errors = self.repo.check(base, self.repo.commit())
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("Old.lua:2: bare GetItemInfo"))

    def test_addons_that_never_load_on_forever_are_skipped(self):
        self.repo.write("Retail/Retail.toc", "## AllowLoadGameType: standard\n")
        self.repo.write("Both/Both.toc", "## AllowLoadGameType: standard, camelot\n")
        self.repo.write("Retail/A.lua", GATE + "GetItemInfo(1)\n")
        self.repo.write("Both/A.lua", GATE + "GetItemInfo(1)\n")
        errors = self.repo.check(self.base, self.repo.commit())
        self.assertEqual([e.split(":")[0] for e in errors], ["Both/A.lua"])


class CombatDeferral(RepoCase):
    def test_raw_registration(self):
        errors = self.errors_for("A.lua", 'local f = CreateFrame("Frame")\n'
                                          'f:RegisterEvent("PLAYER_REGEN_ENABLED")\n')
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("A.lua:3: new PLAYER_REGEN_ENABLED registration"))

    def test_combat_state_tracker(self):
        self.assertEqual(self.errors_for("A.lua", 'ns.watch:RegisterEvent("PLAYER_REGEN_DISABLED")\n'
                                                  'ns.watch:RegisterEvent("PLAYER_REGEN_ENABLED")\n'), [])

    def test_tracker_does_not_cover_other_frames(self):   # author P2 4
        errors = self.errors_for("A.lua", 'tracker:RegisterEvent("PLAYER_REGEN_DISABLED")\n'
                                          'tracker:RegisterEvent("PLAYER_REGEN_ENABLED")\n'
                                          'other:RegisterEvent("PLAYER_REGEN_ENABLED")\n'
                                          'CreateFrame("Frame"):RegisterEvent("PLAYER_REGEN_DISABLED")\n'
                                          'CreateFrame("Frame"):RegisterEvent("PLAYER_REGEN_ENABLED")\n'
                                          'self:RegisterEvent "PLAYER_REGEN_ENABLED"\n')
        self.assertEqual([e.split(": ")[0] for e in errors], ["A.lua:4", "A.lua:6", "A.lua:7"])

    def test_text_is_not_a_registration(self):
        self.assertEqual(self.errors_for(
            "A.lua", "print('f:RegisterEvent(\"PLAYER_REGEN_ENABLED\")')\n"
                     '-- f:RegisterEvent("PLAYER_REGEN_ENABLED")\n'
                     'local e = "PLAYER_REGEN_ENABLED"\n'), [])


class Exceptions(RepoCase):
    LINE = 'f:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: '

    def run_tag(self, tag):
        return self.errors_for("A.lua", self.LINE + tag + "\n")

    def test_permanent(self):                            # A3
        self.assertEqual(self.run_tag("combat-deferral by Ellesmere: re-hides after combat"), [])

    def test_dated(self):
        later = g.utc_today() + datetime.timedelta(days=30)
        self.assertEqual(self.run_tag(f"combat-deferral until {later} by Ellesmere: until the fix"), [])

    def test_expired(self):
        past = g.utc_today() - datetime.timedelta(days=1)
        errors = self.run_tag(f"combat-deferral until {past} by Ellesmere: until the fix")
        self.assertEqual(len(errors), 1)
        self.assertIn(f"expired on {past}", errors[0])

    def test_invalid_date(self):
        errors = self.run_tag("combat-deferral until 2026-13-40 by Ellesmere: typo")
        self.assertEqual(len(errors), 1)
        self.assertIn("invalid date 2026-13-40", errors[0])

    def test_needs_approver_and_reason(self):
        for tag in ("combat-deferral", "combat-deferral by Ellesmere",
                    "combat-deferral by Ellesmere:", "combat-deferral until 2099-01-01"):
            with self.subTest(tag=tag):
                errors = self.run_tag(tag)
                self.assertEqual(len(errors), 2)
                self.assertTrue(any("malformed guardrails-allow" in e for e in errors))
                self.assertTrue(any("new PLAYER_REGEN_ENABLED registration" in e for e in errors))

    def test_covers_its_own_check_only(self):
        errors = self.run_tag("ascii by Ellesmere: wrong check")
        self.assertEqual(len(errors), 1)
        self.assertIn("new PLAYER_REGEN_ENABLED registration", errors[0])

    def test_one_line_two_checks(self):
        self.assertEqual(self.errors_for(
            "A.lua", 'f:RegisterEvent("PLAYER_REGEN_ENABLED") print(GetItemInfo(1)) '
                     "-- guardrails-allow: combat-deferral by Ellesmere: r1; "
                     "guardrails-allow: deprecated-global by Ellesmere: r2\n"), [])


class AsciiAndGate(RepoCase):
    def test_ascii(self):
        dash = "\u2014"
        errors = self.errors_for("A.lua", f"-- a {dash} b\n")
        self.assertEqual(len(errors), 1)
        self.assertIn("U+2014", errors[0])
        self.assertEqual(self.errors_for("EllesmereUILocales/deDE.lua", f'L["a"] = "{dash}"\n'), [])
        self.assertEqual(self.errors_for(
            "B.lua", f"-- a {dash} b -- guardrails-allow: ascii by Ellesmere: quoted text\n"), [])

    def test_client_gate(self):
        self.repo.write("NoGate.lua", "local x = 1\n")
        self.repo.write("EllesmereUI_ClientGate.lua", "local x = 1\n")
        self.repo.write("Libs/Lib.lua", "local x = 1\n")
        errors = self.repo.check(self.base, self.repo.commit())
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("NoGate.lua:1: first line must be"))


class ChangeRange(RepoCase):
    def test_branch_behind_main_is_judged_on_its_own_changes(self):   # A5
        self.repo.write("F.lua", GATE + "GetItemInfo(1)\n")
        start = self.repo.commit("old code")
        self.repo.write("F.lua", GATE + "C_Item.GetItemInfo(1)\n")
        self.repo.commit("main fixes it")
        self.repo.git("checkout", "-q", "-b", "topic", start)
        self.repo.write("G.lua", GATE + "local y = 1\n")
        topic = self.repo.commit("topic work")
        self.assertEqual(self.repo.check("main", topic), [])
        self.repo.git("checkout", "-q", "main")
        self.assertEqual(self.repo.check("main", "topic"), [])

    def test_working_tree_includes_untracked_files(self):
        self.repo.write("New.lua", "GetItemInfo(1)\n")
        errors = self.repo.check(self.base)
        self.assertEqual(len(errors), 2)
        self.assertTrue(errors[0].startswith("New.lua:1: first line must be"))
        self.assertTrue(errors[1].startswith("New.lua:1: bare GetItemInfo"))

    def test_working_tree_edits(self):
        self.repo.write("Base.lua", GATE + "local x = GetSpecialization()\n")
        errors = self.repo.check(self.base)
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("Base.lua:2: bare GetSpecialization"))


@unittest.skipUnless(shutil.which(LUAC), f"no Lua 5.1 compiler ({LUAC})")
class Compile(RepoCase):
    def test_syntax_error(self):
        errors = self.errors_for("A.lua", "local x = = 1\n", [g.check_compile])
        self.assertEqual(len(errors), 1)
        self.assertTrue(errors[0].startswith("A.lua:2:"))

    def test_local_limit(self):
        body = "".join(f"local v{i} = {i}\n" for i in range(201))
        errors = self.errors_for("A.lua", body, [g.check_compile])
        self.assertEqual(len(errors), 1)
        self.assertIn("more than 200 local variables", errors[0])

    def test_upvalue_limit(self):
        body = "".join(f"local u{i} = {i}\n" for i in range(61))
        body += "local function f()\n    return " + " + ".join(f"u{i}" for i in range(61)) + "\nend\n"
        errors = self.errors_for("A.lua", body, [g.check_compile])
        self.assertEqual(len(errors), 1)
        self.assertIn("more than 60 upvalues", errors[0])

    def test_clean_file(self):
        self.assertEqual(self.errors_for("A.lua", "local x = 1\n", [g.check_compile]), [])


def fake_luac(folder, version):
    """A stand-in compiler that only prints a version line."""
    if os.name == "nt":
        path = os.path.join(folder, "fakeluac.bat")
        with open(path, "w") as f:
            f.write(f"@echo {version}\n")
    else:
        path = os.path.join(folder, "fakeluac")
        with open(path, "w") as f:
            f.write(f"#!/bin/sh\necho '{version}'\n")
        os.chmod(path, 0o755)
    return path


class CompilerChoice(RepoCase):
    def compile_with(self, luac):
        saved = os.environ.get("LUAC")
        os.environ["LUAC"] = luac
        try:
            return self.errors_for("A.lua", "local x = 1\n", [g.check_compile])
        finally:
            if saved is None:
                del os.environ["LUAC"]
            else:
                os.environ["LUAC"] = saved

    def test_another_lua_version_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            errors = self.compile_with(fake_luac(tmp, "Lua 5.4.6  Copyright (C) 1994-2023"))
        self.assertEqual(len(errors), 1)
        self.assertIn("is not a Lua 5.1 compiler (Lua 5.4.6", errors[0])

    def test_a_missing_compiler_is_one_clear_error(self):
        errors = self.compile_with("no-such-luac-here")
        self.assertEqual(errors, ["no Lua 5.1 compiler 'no-such-luac-here': install lua5.1 "
                                  "(luac5.1 on PATH) or set LUAC=/path/to/luac"])


class DeprecatedRound2(unittest.TestCase):
    """Shapes the second adversarial pass found."""

    def test_c_fallback_needs_the_real_namespaced_form(self):
        for src in (
                "if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoByID then\n"
                "    x = C_SpecializationInfo.GetSpecializationInfoByID(1)\n"
                "else\n"
                "    x = GetSpecializationInfoByID(1)\n"
                "end",
                "if C_Sound and C_Sound.PlayVocalErrorSoundID then C_Sound.PlayVocalErrorSoundID(1) "
                "else PlayVocalErrorSoundID(1) end",
                "if x then elseif C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoByID "
                "then n = 1 else n = GetSpecializationInfoByID(1) end"):
            with self.subTest(src=src):
                self.assertEqual(len(uses(src)), 1)
        self.assertEqual(uses("if C_Sound and C_Sound.PlayVocalErrorSound then x() "
                              "else PlayVocalErrorSoundID(1) end"), [])

    def test_a_test_of_a_local_proves_nothing_about_the_globals(self):
        first = ("local GetSpecialization = (C_SpecializationInfo and "
                 "C_SpecializationInfo.GetSpecialization) or GetSpecialization\n")
        self.assertEqual(uses(first + "local function SpecID()\n"
                                      "    if not GetSpecialization then return nil end\n"
                                      "    local idx = GetSpecialization()\n"
                                      "    return idx and GetSpecializationInfo(idx)\n"
                                      "end"), [(5, "GetSpecializationInfo")])
        self.assertEqual(uses(first + "local specID = GetSpecialization and "
                                      "GetSpecializationInfo(GetSpecialization())"),
                         [(2, "GetSpecializationInfo")])

    def test_copies_in_a_list(self):
        hits = g.unsafe_global_uses(g.lua_tokens(
            "local UnitHealth, GetItemInfo = UnitHealth, GetItemInfo\n"
            "local function Name(id) return (GetItemInfo(id)) end"))
        self.assertEqual(hits, [(1, "GetItemInfo", "alias"), (2, "GetItemInfo", "copy-call")])
        hits = g.unsafe_global_uses(g.lua_tokens(
            "local GetSpecialization, GetSpecializationInfo = "
            "C_SpecializationInfo.GetSpecialization, GetSpecializationInfo\n"
            "local id = GetSpecializationInfo(GetSpecialization())"))
        self.assertEqual(hits, [(1, "GetSpecializationInfo", "alias"),
                                (2, "GetSpecializationInfo", "copy-call")])

    def test_or_in_a_condition(self):
        self.assertEqual(uses("local function Refresh(specID, force)\n"
                              "    if GetSpecializationInfoByID and specID or force then\n"
                              "        local _, name = GetSpecializationInfoByID(specID or 0)\n"
                              "    end\n"
                              "end"), [(3, "GetSpecializationInfoByID")])
        self.assertEqual(names("if not EllesmereUI.IS_FOREVER and idx or force then "
                               "local s = GetSpecialization() end"), ["GetSpecialization"])
        # Leaving when either holds: after it, neither does.
        self.assertEqual(uses("if IS_FOREVER or not GetItemInfo then return end\nGetItemInfo(1)"), [])

    def test_a_local_is_not_bound_in_its_own_expression(self):
        self.assertEqual(uses("local cache = {}\n"
                              "local GetItemInfo = function(link)\n"
                              "    local r = cache[link]\n"
                              "    if not r then r = { GetItemInfo(link) } cache[link] = r end\n"
                              "    return unpack(r)\n"
                              "end\n"
                              "GetItemInfo(1)"), [(4, "GetItemInfo")])

    def test_early_exits_that_do_work_first(self):
        for src in (
                "local function ShouldBeActive()\n"
                "    if EllesmereUI.IS_FOREVER then\n"
                "        local _, pClass = UnitClass('player')\n"
                "        return EllesmereUI.FOREVER_HEAL_SPELLS[pClass] ~= nil\n"
                "    end\n"
                "    local spec = GetSpecialization()\n"
                "    return spec\n"
                "end",
                "local function f(id)\n"
                "    if not GetSpecializationInfoByID then cache[id] = false return nil end\n"
                "    return GetSpecializationInfoByID(id)\n"
                "end",
                "if IS_FOREVER then do return end end\nGetSpecialization()",
                "for i = 1, 2 do\n    if IS_FOREVER then break end\n    GetSpecialization()\nend",
                "if IS_FOREVER then return else x() end\nGetSpecialization()",
                "if IS_FOREVER then return elseif a then b() end\nGetSpecialization()",
                "if IS_FOREVER then return elseif a then return else b() end\nGetSpecialization()",
                "if a then return elseif IS_FOREVER then return end\nGetSpecialization()",
                "if not IS_FOREVER then x() else return end\nGetSpecialization()"):
            with self.subTest(src=src):
                self.assertEqual(uses(src), [])
        for src in (
                "if IS_FOREVER then if x then return end end\nGetSpecialization()",
                "if IS_FOREVER then for i = 1, 2 do return end end\nGetSpecialization()",
                "if IS_FOREVER then x() else y() end\nGetSpecialization()",
                "if a then return elseif IS_FOREVER then x() end\nGetSpecialization()",
                "if not IS_FOREVER then return else x() end\nGetSpecialization()"):
            with self.subTest(src=src):
                self.assertEqual(names(src), ["GetSpecialization"])

    def test_more_guard_shapes(self):
        for src in (
                "if EllesmereUI.IS_FOREVER ~= true then f.spec = GetSpecialization() end",
                "if EllesmereUI.IS_FOREVER == false then f.spec = GetSpecialization() end",
                "local function f()\n    if type(GetSpecializationInfoByID) ~= 'function' then "
                "return nil end\n    return (select(2, GetSpecializationInfoByID(1)))\nend",
                "local function f()\n    if GetSpecializationInfoByID == nil then return nil end\n"
                "    return (select(2, GetSpecializationInfoByID(1)))\nend",
                "if not GetSpecializationInfoByID then x = nil else x = GetSpecializationInfoByID(1) end",
                "local s = (EllesmereUI.IS_FOREVER ~= true) and GetSpecialization() or nil",
                "if (EllesmereUI.IS_FOREVER) then return end\nGetSpecialization()",
                "if type(GetItemInfo) == 'function' then GetItemInfo(1) end",
                "if nil ~= GetItemInfo then GetItemInfo(1) end",
                "if not (EllesmereUI.IS_FOREVER or x) then GetSpecialization() end",
                "while GetItemInfo do GetItemInfo(1) end"):
            with self.subTest(src=src):
                self.assertEqual(uses(src), [])

    def test_code_with_non_ascii_letters_still_lexes(self):
        for src in ("local caf\u00e9 = C_Item.GetItemInfo(6948)",
                    "local n = \u00b2 + C_Item.GetItemCount(1)",
                    "local \u0441ount = GetItemInfo(1)"):
            with self.subTest(src=src):
                g.lua_tokens(src)
        self.assertEqual(names("local \u0441ount = GetItemInfo(1)"), ["GetItemInfo"])

    def test_indirect_uses(self):
        cases = (
            ("local spec = _G.GetSpecialization()", "call"),
            ("local name = _G['GetItemInfo'](123)", "call"),
            ("local api = { info = GetItemInfo }", "store"),
            ("local getInfo\ngetInfo = GetItemInfo", "store"),
            ("t.info = GetItemInfo", "store"),
            ("hooksecurefunc('EquipItemByName', function() end)", "hook"),
            ("hooksecurefunc(_G, 'EquipItemByName', function() end)", "hook"))
        for src, how in cases:
            with self.subTest(src=src):
                self.assertEqual([h[2] for h in g.unsafe_global_uses(g.lua_tokens(src))], [how])
        self.assertEqual([h[2] for h in g.unsafe_global_uses(g.lua_tokens(
            "local GetItemInfo = _G.GetItemInfo\nGetItemInfo(1)"))], ["alias", "copy-call"])
        for src in ("if _G.GetItemSubClassInfo then x = _G.GetItemSubClassInfo(1, 2) end",
                    "if GetItemInfo then hooksecurefunc('GetItemInfo', f) end",
                    "local ok = pcall(GetItemInfo, 1)",
                    "local t = { GetItemInfo = 1 }",
                    "if GetItemInfo then t.info = GetItemInfo end"):
            with self.subTest(src=src):
                self.assertEqual(uses(src), [])

    def test_statements_on_one_line(self):
        self.assertEqual(names("if link then e.name = GetItemInfo and GetItemInfo(link) "
                               "e.icon = GetItemIcon(link) end"), ["GetItemIcon"])
        self.assertEqual(names("local has = GetItemInfo ~= nil print(GetItemInfo(1))"),
                         ["GetItemInfo"])

    def test_a_copy_of_the_no_namespace_global_is_fine_when_guarded(self):
        src = ("local GetSpecializationInfoByID = GetSpecializationInfoByID\n"
               "local function SpecName(id)\n"
               "    if not GetSpecializationInfoByID then return nil end\n"
               "    return (select(2, GetSpecializationInfoByID(id)))\n"
               "end\n")
        self.assertEqual(uses(src), [])
        self.assertEqual(uses(src + "local s = GetSpecializationInfoByID(2)"),
                         [(6, "GetSpecializationInfoByID")])

    def test_combat_flags_in_expressions(self):
        self.assertEqual(uses("x = not EllesmereUI.IS_FOREVER and GetSpecialization()"), [])
        self.assertEqual(names("x = EllesmereUI.IS_FOREVER and GetSpecialization()"),
                         ["GetSpecialization"])


class CombatRound2(RepoCase):
    def test_trackers_are_told_apart_by_binding(self):
        errors = self.errors_for("A.lua",
                                 "do\n"
                                 "    local f = CreateFrame('Frame')\n"
                                 "    f:RegisterEvent('PLAYER_REGEN_DISABLED')\n"
                                 "    f:RegisterEvent('PLAYER_REGEN_ENABLED')\n"
                                 "end\n"
                                 "do\n"
                                 "    local f = CreateFrame('Frame')\n"
                                 "    f:RegisterEvent('PLAYER_REGEN_ENABLED')\n"
                                 "end\n"
                                 "function Tracker:Init()\n"
                                 "    self:RegisterEvent('PLAYER_REGEN_DISABLED')\n"
                                 "    self:RegisterEvent('PLAYER_REGEN_ENABLED')\n"
                                 "end\n"
                                 "function Bar:Refresh()\n"
                                 "    self:RegisterEvent('PLAYER_REGEN_ENABLED')\n"
                                 "end\n")
        self.assertEqual([e.split(": ")[0] for e in errors], ["A.lua:9", "A.lua:16"])

    def test_one_line_and_indexed_trackers(self):
        self.assertEqual(self.errors_for(
            "A.lua",
            "local f = CreateFrame('Frame') f:RegisterEvent('PLAYER_REGEN_DISABLED')\n"
            "f:RegisterEvent('PLAYER_REGEN_ENABLED')\n"
            "watch:SetScript('OnShow', function(self) self:RegisterEvent('PLAYER_REGEN_DISABLED'); "
            "self:RegisterEvent('PLAYER_REGEN_ENABLED') end)\n"
            "frames[unit]:RegisterEvent('PLAYER_REGEN_DISABLED')\n"
            "frames[unit]:RegisterEvent('PLAYER_REGEN_ENABLED')\n"
            "local g = CreateFrame('Frame')\n"
            "for _, ev in ipairs({ 'PLAYER_REGEN_DISABLED', 'PLAYER_ENTERING_WORLD' }) do "
            "g:RegisterEvent(ev) end\n"
            "g:RegisterEvent('PLAYER_REGEN_ENABLED')\n"
            "local EVENTS = { 'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED' }\n"
            "EllesmereUI.SetEvent('PLAYER_REGEN_DISABLED', true)\n"
            "EllesmereUI.SetEvent('PLAYER_REGEN_ENABLED', true)\n"), [])

    def test_other_ways_to_register(self):
        errors = self.errors_for(
            "EllesmereUIDataBars/Blocks/Mine.lua",
            "inst.events = { 'PLAYER_REGEN_ENABLED' }\n"
            "local EVENTS = { 'PLAYER_ENTERING_WORLD', 'PLAYER_REGEN_ENABLED' }\n"
            "for _, ev in ipairs(EVENTS) do f:RegisterEvent(ev) end\n"
            "pcall(f.RegisterEvent, f, 'PLAYER_REGEN_ENABLED')\n"
            "f.RegisterEvent(f, 'PLAYER_REGEN_ENABLED')\n"
            "EventRegistry:RegisterFrameEventAndCallback('PLAYER_REGEN_ENABLED', fn)\n"
            "SetEvent('PLAYER_REGEN_ENABLED', true)\n"
            "f:RegisterEvent(\n"
            "    'PLAYER_REGEN_ENABLED')\n")
        self.assertEqual([e.split(": ")[0].rsplit(":", 1)[1] for e in errors],
                         ["2", "3", "5", "6", "7", "8", "10"])

    def test_text_and_comparisons_are_not_registrations(self):
        self.assertEqual(self.errors_for(
            "A.lua",
            "if event == 'PLAYER_REGEN_ENABLED' then x() end\n"
            "f:UnregisterEvent('PLAYER_REGEN_ENABLED')\n"
            "local handlers = { ['PLAYER_REGEN_ENABLED'] = OnRegen }\n"
            "print(f:IsEventRegistered('PLAYER_REGEN_ENABLED'))\n"
            "local e = 'PLAYER_REGEN_ENABLED'\n"), [])

    def test_a_tag_on_the_event_line_and_an_edit_of_only_that_line(self):
        self.repo.write("L.lua", GATE + "local f = CreateFrame('Frame')\nf:RegisterEvent(\n"
                                        "    'PLAYER_ENTERING_WORLD')\n")
        base = self.repo.commit()
        self.repo.write("L.lua", GATE + "local f = CreateFrame('Frame')\nf:RegisterEvent(\n"
                                        "    'PLAYER_REGEN_ENABLED')\n")
        head = self.repo.commit()
        self.assertEqual([e.split(": ")[0] for e in self.repo.check(base, head)], ["L.lua:4"])
        self.repo.write("L.lua", GATE + "local f = CreateFrame('Frame')\nf:RegisterEvent(\n"
                                        "    'PLAYER_REGEN_ENABLED') -- guardrails-allow: "
                                        "combat-deferral by Ellesmere: re-applies after combat\n")
        self.assertEqual(self.repo.check(base, self.repo.commit()), [])


class ExceptionsRound2(RepoCase):
    def test_approver_names_may_have_spaces(self):
        self.assertEqual(self.errors_for(
            "A.lua", "local s = 'caf\u00e9' -- guardrails-allow: ascii by John Smith: French UI text\n"), [])

    def test_a_typo_in_the_check_name_is_reported(self):
        errors = self.errors_for("A.lua", "local n = GetItemInfo(1) -- guardrails-allow: "
                                          "deprecated-globals by Ellesmere: retail-only\n")
        self.assertTrue(any("unknown guardrails-allow check 'deprecated-globals'" in e for e in errors))
        self.assertTrue(any("bare GetItemInfo" in e for e in errors))

    def test_tag_order_does_not_matter(self):
        past = g.utc_today() - datetime.timedelta(days=3)
        old = f"guardrails-allow: ascii until {past} by A: stopgap"
        new = "guardrails-allow: ascii by Ellesmere: permanent"
        one = [e for e in self.errors_for("A.lua", f"-- caf\u00e9 {old}; {new}\n") if e.startswith("A.lua")]
        two = [e for e in self.errors_for("B.lua", f"-- caf\u00e9 {new}; {old}\n") if e.startswith("B.lua")]
        self.assertEqual([e.split(": ", 1)[1] for e in one], [e.split(": ", 1)[1] for e in two])
        self.assertEqual(len(one), 1)
        self.assertIn("expired on", one[0])

    def test_tags_count_only_in_comments(self):
        errors = self.errors_for("A.lua", "local help = 'guardrails-allow: ascii by Ellesmere: x' "
                                          ".. '\u2014'\n")
        self.assertEqual(len(errors), 1)
        self.assertIn("U+2014", errors[0])

    def test_a_malformed_tag_beside_a_valid_one_is_reported(self):
        errors = self.errors_for("A.lua", "f:RegisterEvent('PLAYER_REGEN_ENABLED') -- "
                                          "guardrails-allow: ascii by Ellesmere: r; "
                                          "guardrails-allow: combat-deferral\n")
        self.assertTrue(any("malformed guardrails-allow" in e for e in errors))
        self.assertTrue(any("new PLAYER_REGEN_ENABLED registration" in e for e in errors))

    def test_one_message_per_line(self):
        past = g.utc_today() - datetime.timedelta(days=3)
        errors = self.errors_for("A.lua", "local a, b = GetItemInfo(1), GetItemInfo(2) -- "
                                          f"guardrails-allow: deprecated-global until {past} "
                                          "by Ellesmere: stopgap\n")
        self.assertEqual(errors, [f"A.lua:2: guardrails-allow for 'deprecated-global' expired on {past}"])

    def test_an_expired_stopgap_fails_every_run(self):
        past = g.utc_today() - datetime.timedelta(days=3)
        self.repo.write("Stop.lua", GATE + f"local GetItemInfo = GetItemInfo -- guardrails-allow: "
                                           f"deprecated-global until {past} by Ellesmere: stopgap\n")
        before = self.repo.commit()
        self.repo.write("Other.lua", GATE + "local y = 1\n")
        errors = self.repo.check(before, self.repo.commit())
        self.assertEqual(errors, [f"Stop.lua:2: guardrails-allow for 'deprecated-global' expired on {past}"])

    def test_a_call_through_an_excepted_copy_is_still_judged(self):
        self.repo.write("Spec.lua", GATE + "local GetSpecializationInfoByID = GetSpecializationInfoByID\n"
                                           "local M = {}\n")
        before = self.repo.commit()
        self.repo.write("Spec.lua", GATE + "local GetSpecializationInfoByID = GetSpecializationInfoByID\n"
                                           "local M = {}\n"
                                           "function M.SpecName(id) return (select(2, "
                                           "GetSpecializationInfoByID(id))) end\n")
        errors = self.repo.check(before, self.repo.commit())
        self.assertEqual([e.split(": ")[0] for e in errors], ["Spec.lua:4"])


class GitRound2(RepoCase):
    BODY = ("local f = CreateFrame('Frame')\nf:RegisterEvent('PLAYER_REGEN_ENABLED')\n"
            "local id = GetSpecialization()\n-- caf\u00e9\n")
    EXPECTED = ["A.lua:3: new PLAYER_REGEN_ENABLED", "A.lua:4: bare GetSpecialization",
                "A.lua:5: non-ASCII character(s) U+00E9"]

    def assert_found(self, errors):
        self.assertEqual(len(errors), 3)
        for want, got in zip(self.EXPECTED, errors):
            self.assertTrue(got.startswith(want), got)

    def test_diff_settings_do_not_change_the_verdict(self):
        for key, value in (("diff.mnemonicPrefix", "true"), ("diff.noprefix", "true"),
                           ("color.diff", "always"), ("color.ui", "always"),
                           ("diff.external", "false"), ("diff.dstPrefix", "new/")):
            with self.subTest(setting=key):
                self.repo.git("config", key, value)
                try:
                    self.repo.write("A.lua", GATE + self.BODY)
                    self.assert_found(self.repo.check(self.base))
                    head = self.repo.commit()
                    self.assert_found(self.repo.check(self.base, head))
                    self.repo.git("reset", "-q", "--hard", self.base)
                finally:
                    self.repo.git("config", "--unset", key)

    def test_a_copy_reads_as_a_new_file(self):
        self.repo.git("config", "diff.renames", "copies")
        self.repo.write("Src.lua", GATE + "".join(f"local v{i} = {i}\n" for i in range(30)))
        base = self.repo.commit()
        self.repo.write("Src.lua", GATE + "".join(f"local v{i} = {i}\n" for i in range(31)))
        self.repo.write("Copy.lua", "".join(f"local v{i} = {i}\n" for i in range(30)))
        errors = self.repo.check(base, self.repo.commit())
        self.assertEqual([e.split(": ")[0] for e in errors], ["Copy.lua:1"])

    def test_paths_with_spaces_and_non_ascii(self):
        self.repo.write("My Addon/A.lua", GATE + "local f = CreateFrame('Frame')\n"
                                                 "f:RegisterEvent('PLAYER_REGEN_ENABLED')\n")
        self.repo.write("M\u00e9dias/A.lua", GATE + "-- caf\u00e9\n")
        errors = self.repo.check(self.base, self.repo.commit())
        self.assertEqual([e.split(": ")[0] for e in errors], ["My Addon/A.lua:3", "M\u00e9dias/A.lua:2"])
        self.repo.write("\u00dcber/B.lua", "local x = 1\n")
        errors = self.repo.check(self.base)
        self.assertTrue(any(e.startswith("\u00dcber/B.lua:1: first line must be") for e in errors))

    def test_odd_lines_in_a_diff(self):
        errors = self.errors_for("Notes.lua", "--[[ Changelog\n++ added the item tooltip\n]]\n"
                                              "local name = GetItemInfo(6948)\n")
        self.assertEqual([e.split(": ")[0] for e in errors], ["Notes.lua:5"])
        for sep in ("\r", "\f"):
            with self.subTest(sep=repr(sep)):
                errors = self.errors_for("Items.lua", f"local a = 1{sep}local n = GetItemInfo(6948)\n")
                self.assertEqual([e.split(": ")[0] for e in errors], ["Items.lua:2"])
        errors = self.errors_for("Ls.lua", "-- copied note\u2028with a line separator\n")
        self.assertTrue(errors and "U+2028" in errors[0])

    def test_an_untracked_file_counts_lines_as_git_does(self):
        self.repo.write("Paged.lua", GATE + "local f = CreateFrame('Frame')\n\f\n"
                                            "f:RegisterEvent('PLAYER_REGEN_ENABLED') -- guardrails-allow: "
                                            "combat-deferral by Ellesmere: re-applies after combat\n"
                                            "local z = '\u00e9'\n")
        self.assertEqual([e.split(": ")[0] for e in self.repo.check(self.base)], ["Paged.lua:5"])

    def test_a_file_moved_without_git_mv(self):
        body = (GATE + "".join(f"local v{i} = {i}\n" for i in range(30)) +
                "-- old caf\u00e9 note\nlocal f = CreateFrame('Frame')\n"
                "f:RegisterEvent('PLAYER_REGEN_ENABLED')\n")
        self.repo.write("Old/Thing.lua", body)
        base = self.repo.commit()
        os.remove(os.path.join(self.repo.dir, "Old", "Thing.lua"))
        self.repo.write("New/Thing.lua", body)
        self.assertEqual(self.repo.check(base), [])
        self.repo.write("New/Thing.lua", body + "local id = GetSpecialization()\n")
        self.assertEqual([e.split(": ")[0] for e in self.repo.check(base)], ["New/Thing.lua:35"])

    def test_an_unknown_base_is_a_clear_error(self):
        with self.assertRaises(g.GitError) as ctx:
            self.repo.check("1234567890abcdef1234567890abcdef12345678")
        self.assertIn("is not a commit in this repository", str(ctx.exception))

    def test_a_fork_compares_with_upstream(self):
        saved = g.ROOT
        g.ROOT = self.repo.dir
        try:
            self.assertEqual(g.default_base(), "origin/main")
            self.repo.git("update-ref", "refs/remotes/upstream/main", "HEAD")
            self.assertEqual(g.default_base(), "refs/remotes/upstream/main")
        finally:
            g.ROOT = saved

    def test_a_bom_is_named(self):
        self.repo.write("Bom.lua", "\ufeff" + GATE + "local y = 1\n")
        errors = self.repo.check(self.base, self.repo.commit())
        self.assertEqual(errors, ["Bom.lua:1: file starts with a UTF-8 BOM; save it as UTF-8 "
                                  "without a BOM"])

    def test_output_survives_a_narrow_console(self):
        tools = os.path.join(self.repo.dir, ".tools")
        os.makedirs(tools)
        shutil.copy(ROOT / ".tools" / "guardrails.py", tools)
        self.repo.write("M\u00e9dias/A.lua", GATE + "-- caf\u00e9\n")
        head = self.repo.commit()
        env = dict(os.environ, PYTHONIOENCODING="ascii", PYTHONDONTWRITEBYTECODE="1")
        env.pop("GITHUB_ACTIONS", None)
        res = subprocess.run([sys.executable, os.path.join(tools, "guardrails.py"), "--base",
                              self.base, "--head", head], capture_output=True, env=env,
                             cwd=self.repo.dir)
        out = res.stdout.decode("ascii", "replace")
        self.assertEqual(res.returncode, 1, res.stderr.decode("utf-8", "replace"))
        self.assertIn("M\\xe9dias/A.lua:2: non-ASCII character(s) U+00E9", out)


class TocSkips(RepoCase):
    def test_the_toc_forever_reads(self):
        layout = {
            "PlainStd/PlainStd.toc": "## AllowLoadGameType: standard\n",
            "StdPlusCamelot/StdPlusCamelot.toc": "## AllowLoadGameType: standard\n",
            "StdPlusCamelot/StdPlusCamelot_Camelot.toc": "## AllowLoadGameType: camelot\nA.lua\n",
            "StdPlusMainline/StdPlusMainline.toc": "## AllowLoadGameType: standard\n",
            "StdPlusMainline/StdPlusMainline_Mainline.toc": "A.lua\n",
            "BomStd/BomStd.toc": "\ufeff## AllowLoadGameType: standard\n",
            "Excluded/Excluded.toc": "## ExcludeLoadGameType: camelot\n",
            "CamelotOnly/CamelotOnly_Camelot.toc": "## AllowLoadGameType: camelot\n",
            "PerFile/PerFile.toc": "Retail.lua [AllowLoadGameType standard]\nA.lua\n",
            "PerFileOut/PerFileOut.toc": "A.lua [ExcludeLoadGameType camelot]\n",
        }
        for path, text in layout.items():
            self.repo.write(path, text)
        folders = sorted({p.split("/")[0] for p in layout})
        for folder in folders:
            self.repo.write(f"{folder}/A.lua", GATE + "local name = GetItemInfo(6948)\n")
        self.repo.write("PerFile/Retail.lua", GATE + "local name = GetItemInfo(6948)\n")
        errors = self.repo.check(self.base, self.repo.commit())
        self.assertEqual(sorted(e.split(":")[0] for e in errors),
                         ["CamelotOnly/A.lua", "PerFile/A.lua", "StdPlusCamelot/A.lua",
                          "StdPlusMainline/A.lua"])


class DeprecatedRound3(unittest.TestCase):
    """Shapes the third adversarial pass found."""

    def test_or_left_sides_guard_the_right(self):
        for src in (
                "local function Name(id)\n"
                "    if not GetSpecializationInfoByID or not GetSpecializationInfoByID(id) then return nil end\n"
                "    return select(2, GetSpecializationInfoByID(id))\n"
                "end",
                "local function H(id)\n"
                "    return not GetSpecializationInfoByID or select(5, GetSpecializationInfoByID(id)) == 'HEALER'\n"
                "end",
                "local function S() return EllesmereUI.IS_FOREVER and 1 or GetSpecialization() end",
                "local x = GetItemInfo == nil or GetItemInfo(1)",
                "local t = not GetItemInfo and {} or { GetItemInfo(1) }"):
            with self.subTest(src=src):
                self.assertEqual(uses(src), [])
        for src in ("local x = GetItemInfo or GetItemInfo(1)",
                    "local x = a or GetItemInfo(1)",
                    "local x = (not GetItemInfo or a) and GetItemInfo(1)"):
            with self.subTest(src=src):
                self.assertEqual(names(src), ["GetItemInfo"])

    def test_a_stray_else_does_not_stop_the_walk(self):
        g.Analysis(g.lua_tokens(GATE + "if x then y() end else z() end\nlocal n = C_Item.GetItemCount(1)\n"))

    def test_stores_in_a_list_of_targets(self):
        hits = g.unsafe_global_uses(g.lua_tokens(
            "local I = {}\nI.UnitHealth, I.GetItemInfo = UnitHealth, GetItemInfo\n"))
        self.assertEqual(hits, [(2, "GetItemInfo", "store")])
        self.assertEqual(uses("local a, b\na, b = f(GetItemInfo), 1"), [])

    def test_a_function_statement_after_a_guard_on_the_same_line(self):
        self.assertEqual(names("M.hasInfo = GetItemInfo ~= nil and true "
                               "function M.Name(id) return (GetItemInfo(id)) end"), ["GetItemInfo"])

    def test_copies_made_under_a_guard_or_a_condition(self):
        self.assertEqual(uses("local GetSpecInfo\n"
                              "if not EllesmereUI.IS_FOREVER then\n"
                              "    GetSpecInfo = GetSpecializationInfo\n"
                              "end\n"
                              "local function SpecID(index) return (GetSpecInfo(index)) end"),
                         [(5, "GetSpecializationInfo")])
        self.assertEqual(uses("local GetSpec = not EllesmereUI.IS_FOREVER and GetSpecialization\n"
                              "local function Index() return GetSpec() end"),
                         [(2, "GetSpecialization")])
        self.assertEqual(uses("local L = GetItemInfo and GetItemInfo\nL(1)"), [(2, "GetItemInfo")])
        for src in ("local L = a and GetItemInfo\nif L then L(1) end",
                    "local L = C_Item.GetItemInfo or GetItemInfo\nL(1)",
                    "local L = (C_Item and C_Item.GetItemInfo) or GetItemInfo\nL(1)",
                    "local L = GetItemInfo or function() return nil end\nL(1)"):
            with self.subTest(src=src):
                self.assertEqual(uses(src), [])

    def test_semicolons_in_a_table(self):
        self.assertEqual(uses("local function Info(id)\n"
                              "    return GetItemInfo and { id = id; name = GetItemInfo(id) }\n"
                              "end"), [])
        self.assertEqual(names("local a = GetItemInfo and 1; GetItemInfo(2)"), ["GetItemInfo"])

    def test_references_in_parentheses(self):
        self.assertEqual(names("local function Name(id)\n    return (GetItemInfo)(id)\nend"),
                         ["GetItemInfo"])
        hits = g.unsafe_global_uses(g.lua_tokens("local GII = (GetItemInfo)\nlocal n = GII(1)"))
        self.assertEqual(hits, [(1, "GetItemInfo", "alias"), (2, "GetItemInfo", "copy-call")])
        self.assertEqual(uses("foo(GetItemInfo)(1)"), [])

    def test_an_early_exit_inside_a_do_block(self):
        self.assertEqual(uses("local function Name(id)\n"
                              "    do\n"
                              "        if not GetSpecializationInfoByID then return nil end\n"
                              "    end\n"
                              "    return (select(2, GetSpecializationInfoByID(id)))\n"
                              "end"), [])

    def test_a_closure_in_a_loop_header(self):
        self.assertEqual(uses("local function Collect(fill) local t = {} fill(t) return t end\n"
                              "local function f()\n"
                              "    if EllesmereUI.IS_FOREVER then\n"
                              "        for _, v in ipairs(Collect(function(t) for i = 1, 2 do t[i] = i end end)) do\n"
                              "            break\n"
                              "        end\n"
                              "    end\n"
                              "    return GetSpecialization()\n"
                              "end"), [(8, "GetSpecialization")])


class SpansAndFailures(RepoCase):
    def test_a_tag_on_another_line_of_the_statement(self):
        self.assertEqual(self.errors_for(
            "Items.lua",
            "local function Name(id)\n"
            "    local name = select(2, GetItemInfo(id))\n"
            "        or UNKNOWN -- guardrails-allow: deprecated-global by Ellesmere: retail-only path\n"
            "    return name\n"
            "end\n"
            "local id = -- guardrails-allow: deprecated-global by Ellesmere: retail-only path\n"
            "    GetSpecialization()\n"), [])
        dash = chr(0x2014)
        self.assertEqual(self.errors_for(
            "A.lua", "local LABEL = 'Gem: ' .. -- guardrails-allow: ascii by Ellesmere: UI text\n"
                     f"    '{dash}'\n"), [])

    def test_a_file_the_walk_cannot_read_is_one_error(self):
        saved = g.Analysis

        def broken(tokens):
            raise RuntimeError("boom")
        g.Analysis = broken
        try:
            errors = self.errors_for("A.lua", "local n = GetItemInfo(1)\n")
        finally:
            g.Analysis = saved
        self.assertEqual(errors, ["A.lua: could not be analysed (RuntimeError: boom); fix its "
                                  "syntax first, or report this"])

    @unittest.skipUnless(shutil.which(LUAC), f"no Lua 5.1 compiler ({LUAC})")
    def test_a_stray_else_still_reports_the_compile_error(self):
        errors = self.errors_for("Items.lua", "local function Label(id)\n"
                                              "    local name = C_Item.GetItemInfo(id)\n"
                                              "    if name then\n"
                                              "        return name\n"
                                              "    end\n"
                                              "    end\n"
                                              "    else\n"
                                              "        return '?'\n"
                                              "    end\n"
                                              "end\n",
                                 [g.check_compile, g.check_deprecated_globals])
        self.assertTrue(errors and errors[0].startswith("Items.lua:8:"), errors)


def lua(*lines):
    """Lua source lines, each ended with a newline."""
    return "".join(line + "\n" for line in lines)


E_ACUTE = chr(0xE9)


class TagsOnStatementLines(RepoCase):
    """An exception counts on any line of the offending statement."""
    COMBAT = "-- guardrails-allow: combat-deferral by Ellesmere: re-hides after combat"

    def test_combat_registrations(self):
        cases = {
            "T1.lua": lua("local f = CreateFrame('Frame')", "f:RegisterEvent(",
                          "    'PLAYER_REGEN_ENABLED'", ") " + self.COMBAT),
            "T2.lua": lua("local EVENTS = { " + self.COMBAT, "    'PLAYER_ENTERING_WORLD',",
                          "    'PLAYER_REGEN_ENABLED',", "}"),
            "T3.lua": lua("local EVENTS = {", "    'PLAYER_ENTERING_WORLD',",
                          "    'PLAYER_REGEN_ENABLED',", "} " + self.COMBAT),
            "T4.lua": lua("local f = CreateFrame('Frame')",
                          "f:RegisterUnitEvent('PLAYER_REGEN_ENABLED',", "    'player') " + self.COMBAT),
        }
        for path, body in cases.items():
            with self.subTest(path=path):
                self.assertEqual(self.errors_for(path, body), [])

    def test_ascii(self):
        i, v, n, e, a, s = (chr(c) for c in (0x438, 0x432, 0x43D, 0x435, 0x430, 0x441))
        rows = (f'    "{i}", "{v}", "{n}{e}",', f'    "{n}{a}", "{s}",')
        tag = "-- guardrails-allow: ascii by Ellesmere: Russian search stopwords"
        self.assertEqual(self.errors_for("T7.lua", lua("local STOPWORDS = { " + tag, *rows, "}")), [])
        self.assertEqual(self.errors_for("T8.lua", lua("local STOPWORDS = {", *rows, "} " + tag)), [])
        self.assertEqual(self.errors_for("T9.lua", lua(
            "local HELP = [[", chr(0xC9) + "lan", "]] -- guardrails-allow: ascii by Ellesmere: UI text")), [])

    def test_a_tag_on_a_table_first_line_covers_a_new_row(self):
        qian, wan, yi, oku = chr(0x5343), chr(0x4E07), chr(0x4EBF), chr(0x5104)
        zh = f'    zhCN = {{ "{qian}", "{wan}", "{yi}" }},'
        self.repo.write("Num.lua", GATE + lua("local CJK_GLYPHS = {", zh, "}"))
        base = self.repo.commit()
        self.repo.write("Num.lua", GATE + lua(
            "local CJK_GLYPHS = { -- guardrails-allow: ascii by Ellesmere: locale number glyphs", zh,
            f'    jaJP = {{ "{qian}", "{wan}", "{oku}" }},', "}"))
        self.assertEqual(self.repo.check(base, self.repo.commit()), [])


class CombatRound4(RepoCase):
    def lines(self, path, body):
        return [e.split(": ")[0] for e in self.errors_for(path, body, [g.check_combat_deferral])]

    def test_one_frame_under_several_names(self):
        cases = {
            "C1.lua": lua('local popup = CreateFrame("Frame")',
                          'popup:RegisterEvent("PLAYER_REGEN_DISABLED")',
                          'popup:SetScript("OnEvent", function(self, event)',
                          '    if event == "PLAYER_REGEN_DISABLED" then',
                          '        self:Hide()',
                          '        self:RegisterEvent("PLAYER_REGEN_ENABLED")',
                          '    else',
                          '        self:UnregisterEvent("PLAYER_REGEN_ENABLED")',
                          '        self:Show()',
                          '    end',
                          'end)'),
            "S1.lua": lua("ns.watch = CreateFrame('Frame')",
                          "ns.watch:RegisterEvent('PLAYER_REGEN_DISABLED')",
                          "local watch = ns.watch",
                          "watch:RegisterEvent('PLAYER_REGEN_ENABLED')"),
            "S2.lua": lua("function EAB:OnEnable() self:RegisterEvent('PLAYER_REGEN_DISABLED', "
                          "function() self:EnterCombat() end) end",
                          "function EAB:SetupCombatFade() self:RegisterEvent('PLAYER_REGEN_ENABLED', "
                          "function() self:LeaveCombat() end) end"),
            "S3.lua": lua("function EAB:OnEnable() self:RegisterEvent('PLAYER_REGEN_DISABLED', "
                          "function() self:EnterCombat() end) end",
                          "EAB:RegisterEvent('PLAYER_REGEN_ENABLED', function() EAB:LeaveCombat() end)"),
            "S4.lua": lua("local f = CreateFrame('Frame')",
                          "f:HookScript('OnShow', function(frame) "
                          "frame:RegisterEvent('PLAYER_REGEN_DISABLED') end)",
                          "f:RegisterEvent('PLAYER_REGEN_ENABLED')"),
        }
        for path, body in cases.items():
            with self.subTest(path=path):
                self.assertEqual(self.lines(path, body), [])
        self.assertEqual(self.lines("Two.lua", lua(
            "local a = CreateFrame('Frame')",
            "a:SetScript('OnEvent', function(self) self:RegisterEvent('PLAYER_REGEN_DISABLED') end)",
            "local b = CreateFrame('Frame')",
            "b:RegisterEvent('PLAYER_REGEN_ENABLED')")), ["Two.lua:5"])

    def test_lists_count_for_the_frame_they_are_registered_on(self):
        cases = {
            "C2.lua": lua('local f = CreateFrame("Frame")',
                          'local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }',
                          'for _, ev in ipairs(EVENTS) do f:RegisterEvent(ev) end',
                          'f:RegisterEvent("PLAYER_REGEN_DISABLED")'),
            "C3.lua": lua('local f = CreateFrame("Frame")',
                          'for _, ev in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do '
                          'f:RegisterEvent(ev) end',
                          'f:RegisterEvent("PLAYER_REGEN_DISABLED")'),
            "C5.lua": lua('local HANDLERS = { { "PLAYER_REGEN_DISABLED", OnCombatStart }, '
                          '{ "PLAYER_REGEN_ENABLED", OnCombatEnd } }',
                          'local f = CreateFrame("Frame")',
                          'for _, h in ipairs(HANDLERS) do f:RegisterEvent(h[1]) end'),
            "N1.lua": lua("local f = CreateFrame('Frame')",
                          "local EVENTS = { 'PLAYER_REGEN_DISABLED', 'PLAYER_ENTERING_WORLD' }",
                          "for i = 1, #EVENTS do f:RegisterEvent(EVENTS[i]) end",
                          "f:RegisterEvent('PLAYER_REGEN_ENABLED')"),
            "N2.lua": lua("local f = CreateFrame('Frame')",
                          "local HANDLERS = { { 'PLAYER_REGEN_ENABLED', OnCombatEnd } }",
                          "for _, h in ipairs(HANDLERS) do f:RegisterEvent(h[1]) end",
                          "f:RegisterEvent('PLAYER_REGEN_DISABLED')"),
            "K1.lua": lua("local f = CreateFrame('Frame')",
                          "local Events = {",
                          "    PLAYER_REGEN_DISABLED = function() end,",
                          "    PLAYER_REGEN_ENABLED = function() end,",
                          "}",
                          "for event in pairs(Events) do f:RegisterEvent(event) end"),
        }
        for path, body in cases.items():
            with self.subTest(path=path):
                self.assertEqual(self.lines(path, body), [])
        self.assertEqual(self.lines("L.lua", lua(
            'local f = CreateFrame("Frame")',
            'local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }',
            'for _, ev in ipairs(EVENTS) do f:RegisterEvent(ev) end',
            'local other = CreateFrame("Frame")',
            'other:RegisterEvent("PLAYER_REGEN_DISABLED")')), ["L.lua:3"])

    def test_calls_that_do_not_register(self):
        cases = {
            "C15.lua": lua('local f = CreateFrame("Frame")',
                           'local function OnEvent(self, event) ns.Refresh() end',
                           'f:SetScript("OnEvent", OnEvent)',
                           'f:RegisterEvent("PLAYER_ENTERING_WORLD")',
                           'if not InCombatLockdown() then OnEvent(f, "PLAYER_REGEN_ENABLED") end'),
            "C16.lua": lua('function Mod:Init() if not InCombatLockdown() then '
                           'self:OnEvent("PLAYER_REGEN_ENABLED") end end'),
            "C17.lua": lua('local frame = CreateFrame("Frame")',
                           'local function SetEvent(event, on)',
                           '    if on then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end',
                           'end',
                           'SetEvent("PLAYER_REGEN_ENABLED", false)'),
            "C18.lua": lua('EventRegistry:TriggerEvent("PLAYER_REGEN_ENABLED")'),
            "C19.lua": lua('ns.HandleEvent("PLAYER_REGEN_ENABLED")', 'ns.FireEvent("PLAYER_REGEN_ENABLED")',
                           'local h = ns.GetEventHandler("PLAYER_REGEN_ENABLED")'),
        }
        for path, body in cases.items():
            with self.subTest(path=path):
                self.assertEqual(self.lines(path, body), [])

    def test_handler_tables_constants_and_appends(self):
        loop = "for event in pairs(Events) do f:RegisterEvent(event) end"
        frame = "local f = CreateFrame('Frame')"
        cases = {
            "C10.lua": lua(frame, "local Events = {}",
                           "function Events.PLAYER_REGEN_ENABLED() ns.ApplyAll() end", loop),
            "C11.lua": lua(frame, "local Events = {",
                           "    PLAYER_REGEN_ENABLED = function() ns.ApplyAll() end,", "}", loop),
            "C11b.lua": lua(frame, "local Events = {",
                            "    ['PLAYER_REGEN_ENABLED'] = function() ns.ApplyAll() end,", "}", loop),
            "C11c.lua": lua(frame, "local Events = {}",
                            "Events.PLAYER_REGEN_ENABLED = function() ns.ApplyAll() end", loop),
            "C11d.lua": lua(frame, "local Events = {}",
                            "Events['PLAYER_REGEN_ENABLED'] = function() ns.ApplyAll() end", loop),
            "C12.lua": lua(frame, "local COMBAT_END = 'PLAYER_REGEN_ENABLED'",
                           "f:RegisterEvent(COMBAT_END)"),
            "C13.lua": lua(frame, "local EV = { 'PLAYER_ENTERING_WORLD' }",
                           "EV[#EV + 1] = 'PLAYER_REGEN_ENABLED'",
                           "for i = 1, #EV do f:RegisterEvent(EV[i]) end"),
            "C14.lua": lua(frame, "local EV = {}", "tinsert(EV, 'PLAYER_REGEN_ENABLED')",
                           "for _, e in ipairs(EV) do f:RegisterEvent(e) end"),
            "C14b.lua": lua(frame, "local EV = {}", "table.insert(EV, 'PLAYER_REGEN_ENABLED')",
                            "for _, e in ipairs(EV) do f:RegisterEvent(e) end"),
        }
        for path, body in cases.items():
            with self.subTest(path=path):
                self.assertEqual(self.lines(path, body), [f"{path}:4"])

    def test_a_key_added_to_a_registered_handler_table(self):
        def body(extra):
            return GATE + lua("local logFrame = CreateFrame('Frame')", "local events = {",
                              "    ZONE_CHANGED_NEW_AREA = function() C_Timer.After(2, Apply) end,",
                              *extra, "}", "local function Sync(want)",
                              "    for ev in pairs(events) do",
                              "        if want then logFrame:RegisterEvent(ev) "
                              "else logFrame:UnregisterEvent(ev) end",
                              "    end", "end")
        self.repo.write("Log.lua", body([]))
        base = self.repo.commit()
        self.repo.write("Log.lua", body(["    PLAYER_REGEN_ENABLED = function() Apply() end,"]))
        errors = self.repo.check(base, self.repo.commit(), [g.check_combat_deferral])
        self.assertEqual([e.split(": ")[0] for e in errors], ["Log.lua:5"])

    def test_a_new_loop_over_an_old_handler_table(self):
        table = ("local f = CreateFrame('Frame')", "local events = {",
                 "    PLAYER_REGEN_ENABLED = function() Apply() end,", "}")
        self.repo.write("Loop.lua", GATE + lua(*table))
        base = self.repo.commit()
        self.repo.write("Loop.lua", GATE + lua(*table, "for ev in pairs(events) do f:RegisterEvent(ev) end"))
        errors = self.repo.check(base, self.repo.commit(), [g.check_combat_deferral])
        self.assertEqual([e.split(": ")[0] for e in errors], ["Loop.lua:6"])

    def test_event_helpers_named_register_event(self):
        self.assertEqual(self.lines("H.lua", lua(
            'ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() ns.Rebuild() end)',
            'Addon.RegisterEvent("PLAYER_REGEN_ENABLED")')), ["H.lua:2", "H.lua:3"])
        cases = {
            "C6.lua": lua('local frame = CreateFrame("Frame")',
                          'local function RegisterEvent(event) frame:RegisterEvent(event) end',
                          'RegisterEvent("PLAYER_REGEN_DISABLED")', 'RegisterEvent("PLAYER_REGEN_ENABLED")'),
            "C7.lua": lua('function ns.RegisterEvent(event) ns.frame:RegisterEvent(event) end',
                          'ns.RegisterEvent("PLAYER_REGEN_DISABLED")', 'ns.RegisterEvent("PLAYER_REGEN_ENABLED")'),
        }
        for path, body in cases.items():
            with self.subTest(path=path):
                self.assertEqual(self.lines(path, body), [])

    def test_xpcall(self):
        self.assertEqual(self.lines("X.lua", lua(
            "local f = CreateFrame('Frame')",
            "xpcall(f.RegisterEvent, CallErrorHandler, f, 'PLAYER_REGEN_ENABLED')")), ["X.lua:3"])
        self.assertEqual(self.lines("Y.lua", lua(
            "local f = CreateFrame('Frame')",
            "xpcall(f.RegisterEvent, CallErrorHandler, f, 'PLAYER_REGEN_DISABLED')",
            "f:RegisterEvent('PLAYER_REGEN_ENABLED')")), [])


class ExceptionsRound4(RepoCase):
    def test_a_date_after_the_approver_is_malformed(self):
        past = g.utc_today() - datetime.timedelta(days=9)
        errors = self.errors_for("Stop.lua", f"local s = 'caf{E_ACUTE}' -- guardrails-allow: ascii "
                                             f"by Ellesmere until {past}: stopgap\n")
        self.assertEqual(len(errors), 2, errors)
        self.assertTrue(any("malformed guardrails-allow" in e for e in errors))
        self.assertTrue(any("U+00E9" in e for e in errors))

    def test_a_tag_in_a_string_never_expires(self):
        past = g.utc_today() - datetime.timedelta(days=9)
        self.assertEqual(self.errors_for("Help.lua", f'local HELP = "Write: -- guardrails-allow: ascii '
                                                     f'until {past} by <name>: <why>"\n'), [])
        before = self.repo.git("rev-parse", "HEAD").strip()
        self.repo.write("Other.lua", GATE + "local y = 1\n")
        self.assertEqual(self.repo.check(before, self.repo.commit()), [])

    def test_prose_about_tags_is_not_a_tag(self):
        self.assertEqual(self.errors_for("Note.lua", "-- Exceptions need a guardrails-allow comment; "
                                                     "see AGENTS.md.\nlocal y = 1\n"), [])
        errors = self.errors_for("Bad.lua", "local y = 1 -- guardrails-allow : ascii by A: spaced colon\n")
        self.assertEqual(len(errors), 1)
        self.assertIn("malformed guardrails-allow", errors[0])

    def test_an_expired_tag_in_a_file_git_calls_binary(self):
        past = g.utc_today() - datetime.timedelta(days=3)
        self.repo.write("Dump.lua", GATE + "-- dump: " + chr(0) + "\n"
                        f"local x = 1 -- guardrails-allow: ascii until {past} by Ellesmere: stopgap\n")
        before = self.repo.commit()
        self.repo.write("Other.lua", GATE + "local y = 1\n")
        self.assertEqual(self.repo.check(before, self.repo.commit()),
                         [f"Dump.lua:3: guardrails-allow for 'ascii' expired on {past}"])


class GitRound4(RepoCase):
    V = "f:RegisterEvent('PLAYER_REGEN_ENABLED')"

    def test_the_diff_algorithm_is_pinned(self):
        V = self.V
        cases = (
            (["do end", "ns.Refresh()", "ns.Refresh()", V, "do end", "do end"],
             ["do end", "ns.Refresh()", "ns.Refresh()", "", "do end", "do end", V], ["S.lua:9"]),
            (["do end", "", "do end", "do end", "", "", V, "local a = 1", "do end"],
             ["local a = 1", "", "do end", "do end", "", "", "do end", V, "do end", "do end"], []))
        for k, (old, new, want) in enumerate(cases):
            self.repo.write("S.lua", GATE + lua("local f = CreateFrame('Frame')", *old))
            base = self.repo.commit()
            self.repo.write("S.lua", GATE + lua("local f = CreateFrame('Frame')", *new))
            head = self.repo.commit()
            for setting in (None, ("diff.algorithm", "histogram"), ("diff.algorithm", "patience"),
                            ("diff.indentHeuristic", "false")):
                with self.subTest(case=k, setting=setting):
                    if setting:
                        self.repo.git("config", *setting)
                    try:
                        errors = self.repo.check(base, head, [g.check_combat_deferral])
                    finally:
                        if setting:
                            self.repo.git("config", "--unset", setting[0])
                    self.assertEqual([e.split(": ")[0] for e in errors], want)

    def test_blank_context_lines_and_git_diff_opts(self):
        self.repo.write("A.lua", GATE + "local a = 1\n\nlocal b = 2\n")
        self.repo.write("B.lua", GATE + "local x = 1\n")
        base = self.repo.commit()
        self.repo.write("A.lua", GATE + "local a = 10\n\nlocal b = 20\n")
        self.repo.write("B.lua", GATE + "local x = 1\nlocal f = CreateFrame('Frame')\n"
                                        "f:RegisterEvent('PLAYER_REGEN_ENABLED')\n"
                                        f"local id = GetSpecialization()\n-- caf{E_ACUTE}\n")
        head = self.repo.commit()
        want = ["B.lua:4: new PLAYER_REGEN_ENABLED", "B.lua:5: bare GetSpecialization",
                "B.lua:6: non-ASCII character(s) U+00E9"]
        self.repo.git("config", "diff.interHunkContext", "3")
        self.repo.git("config", "diff.suppressBlankEmpty", "true")
        for opts in (None, "--unified=3"):
            with self.subTest(GIT_DIFF_OPTS=opts):
                saved = os.environ.get("GIT_DIFF_OPTS")
                if opts:
                    os.environ["GIT_DIFF_OPTS"] = opts
                try:
                    errors = self.repo.check(base, head)
                finally:
                    if saved is None:
                        os.environ.pop("GIT_DIFF_OPTS", None)
                    else:
                        os.environ["GIT_DIFF_OPTS"] = saved
                self.assertEqual(len(errors), 3, errors)
                for w, got in zip(want, errors):
                    self.assertTrue(got.startswith(w), got)

    def test_parse_patch_counts_a_blank_context_line(self):
        patch = ("diff --git a/A.lua b/A.lua\n--- a/A.lua\n+++ b/A.lua\n@@ -2,3 +2,3 @@\n"
                 "-local a = 1\n+local a = 10\n\n-local b = 2\n+local b = 20\n"
                 "diff --git a/B.lua b/B.lua\n--- a/B.lua\n+++ b/B.lua\n@@ -2,0 +3,1 @@\n+local f = 1\n")
        self.assertEqual(g.parse_patch(patch), [("A.lua", 2, "local a = 10"), ("A.lua", 4, "local b = 20"),
                                                ("B.lua", 3, "local f = 1")])

    def test_moves_without_git_mv_pair_as_git_pairs_them(self):
        def block(tag, count):
            return "".join(f"local {tag}{i} = {i}\n" for i in range(count))

        def half(tag):
            return (block(tag, 20) + f"local {tag}f = CreateFrame('Frame')\n"
                    f"{tag}f:RegisterEvent('PLAYER_REGEN_ENABLED')\n")
        old = GATE + block("v", 30) + "local f = CreateFrame('Frame')\n" + self.V + "\n"
        cases = (
            ("grown", {"Old/Thing.lua": old}, {"New/Thing.lua": old + block("w", 45)}),
            ("split", {"Big.lua": GATE + half("a") + half("b")},
             {"Big_PartA.lua": GATE + half("a"), "Big_PartB.lua": GATE + half("b")}),
        )
        for name, before, after in cases:
            with self.subTest(case=name):
                for path, text in before.items():
                    self.repo.write(path, text)
                base = self.repo.commit(f"{name} before")
                for path in before:
                    os.remove(os.path.join(self.repo.dir, path))
                for path, text in after.items():
                    self.repo.write(path, text)
                untracked = self.repo.check(base, checks=[g.check_combat_deferral])
                status = self.repo.git("status", "--porcelain", "--untracked-files=all")
                for path in after:
                    self.assertIn(f"?? {path}", status)      # the real index is untouched
                self.repo.git("add", "-A")
                staged = self.repo.check(base, checks=[g.check_combat_deferral])
                committed = self.repo.check(base, self.repo.commit(f"{name} after"),
                                            [g.check_combat_deferral])
                self.assertTrue(staged)
                self.assertEqual(untracked, staged)
                self.assertEqual(staged, committed)

    def test_a_file_with_a_nul_byte(self):
        self.repo.write("Dump.lua", GATE + "-- pasted from a dump: " + chr(0) + "\n"
                        "local f = CreateFrame('Frame')\n" + self.V + "\n"
                        f"local id = GetSpecialization()\n-- caf{E_ACUTE}\n")
        untracked = self.repo.check(self.base)
        committed = self.repo.check(self.base, self.repo.commit())
        self.assertEqual([e.split(": ")[0] for e in committed], ["Dump.lua:4", "Dump.lua:5", "Dump.lua:6"])
        self.assertEqual(untracked, committed)

    def test_the_newer_of_upstream_and_origin_is_the_base(self):
        a = self.repo.git("rev-parse", "HEAD").strip()
        self.repo.write("Other.lua", GATE + "local f = CreateFrame('Frame')\n" + self.V + "\n")
        b = self.repo.commit("upstream work, synced to the fork")
        self.repo.git("checkout", "-q", "-b", "feat")
        self.repo.write("Mine.lua", GATE + "local y = 1\n")
        self.repo.commit("feature")
        saved = g.ROOT
        g.ROOT = self.repo.dir
        try:
            self.repo.git("update-ref", "refs/remotes/upstream/main", a)   # stale
            self.repo.git("update-ref", "refs/remotes/origin/main", b)
            stale_upstream = g.default_base()
            self.repo.git("update-ref", "refs/remotes/upstream/main", b)
            self.repo.git("update-ref", "refs/remotes/origin/main", a)     # stale fork
            stale_origin = g.default_base()
        finally:
            g.ROOT = saved
        self.assertEqual((stale_upstream, stale_origin),
                         ("refs/remotes/origin/main", "refs/remotes/upstream/main"))
        self.assertEqual(self.repo.check("upstream/main"), [])

    def test_a_bad_head_names_the_head_flag(self):
        with self.assertRaises(g.GitError) as ctx:
            self.repo.check(self.base, "feature-typo")
        self.assertIn("pass another --head", str(ctx.exception))


def deferral_lines(src):
    """Lines of the one-way PLAYER_REGEN_ENABLED registrations in a Lua source."""
    return sorted({r.line for r in g.Analysis(g.lua_tokens(src)).deferrals})


FRAME = "local f = CreateFrame('Frame')"


class CombatRound5(unittest.TestCase):
    """Shapes the fourth adversarial pass found (deferral lines, no git needed)."""

    def assert_lines(self, cases):
        for name, (src, want) in cases.items():
            with self.subTest(case=name):
                self.assertEqual(deferral_lines(src), want)

    def test_named_handlers_and_methods(self):
        self.assert_lines({
            "named": (lua('local frame = CreateFrame("Frame")', 'local function OnEvent(self, event)',
                          '    if event == "PLAYER_REGEN_DISABLED" then self:RegisterEvent("PLAYER_REGEN_ENABLED")',
                          '    else self:UnregisterEvent("PLAYER_REGEN_ENABLED") end', 'end',
                          'frame:SetScript("OnEvent", OnEvent)', 'frame:RegisterEvent("PLAYER_REGEN_DISABLED")'), []),
            "local fn value": (lua(FRAME, 'local H = function(self) self:RegisterEvent("PLAYER_REGEN_ENABLED") end',
                                   'f:SetScript("OnEvent", H)', 'f:RegisterEvent("PLAYER_REGEN_DISABLED")'), []),
            "field fn": (lua(FRAME, 'function ns.WatchOnEvent(self) self:RegisterEvent("PLAYER_REGEN_ENABLED") end',
                             'f:SetScript("OnEvent", ns.WatchOnEvent)', 'f:RegisterEvent("PLAYER_REGEN_DISABLED")'), []),
            "colon method as handler": (lua(FRAME, 'function ns:OnEvent() self:RegisterEvent("PLAYER_REGEN_ENABLED") end',
                                            'f:SetScript("OnEvent", ns.OnEvent)',
                                            'f:RegisterEvent("PLAYER_REGEN_DISABLED")'), []),
            "named hook": (lua(FRAME, "local function Shown(frame) frame:RegisterEvent('PLAYER_REGEN_DISABLED') end",
                               "f:HookScript('OnShow', Shown)", "f:RegisterEvent('PLAYER_REGEN_ENABLED')"), []),
            "colon methods of one object": (lua("function EAB:OnEnable() self:RegisterEvent('PLAYER_REGEN_DISABLED') end",
                                                "function EAB:Fade() self:RegisterEvent('PLAYER_REGEN_ENABLED') end"), []),
            "field = local": (lua("local watch = CreateFrame('Frame')", "ns.combatWatch = watch",
                                  "watch:RegisterEvent('PLAYER_REGEN_DISABLED')",
                                  "ns.combatWatch:RegisterEvent('PLAYER_REGEN_ENABLED')"), []),
            "shared handler, tracker wired first": (lua(
                "local tracker, bags = CreateFrame('Frame'), CreateFrame('Frame')",
                "local function H(self) self:RegisterEvent('PLAYER_REGEN_ENABLED') end",
                "tracker:RegisterEvent('PLAYER_REGEN_DISABLED')", "tracker:SetScript('OnEvent', H)",
                "bags:SetScript('OnEvent', H)"), [2]),
            "shared handler, bags wired first": (lua(
                "local tracker, bags = CreateFrame('Frame'), CreateFrame('Frame')",
                "local function H(self) self:RegisterEvent('PLAYER_REGEN_ENABLED') end",
                "tracker:RegisterEvent('PLAYER_REGEN_DISABLED')", "bags:SetScript('OnEvent', H)",
                "tracker:SetScript('OnEvent', H)"), [2]),
            "handler of another frame": (lua("local a, b = CreateFrame('Frame'), CreateFrame('Frame')",
                                             "local function H(self) self:RegisterEvent('PLAYER_REGEN_DISABLED') end",
                                             "a:SetScript('OnEvent', H)", "b:RegisterEvent('PLAYER_REGEN_ENABLED')"), [4]),
            "dot function is not a method": (lua("function EAB:OnEnable() self:RegisterEvent('PLAYER_REGEN_DISABLED') end",
                                                 "function EAB.RetryTick(self) self:RegisterEvent('PLAYER_REGEN_ENABLED') end"),
                                             [2]),
        })

    def test_one_line_statements(self):
        self.assert_lines({
            "key after then": (lua(FRAME, "local Events = {}", "if ns.x then Events.PLAYER_REGEN_ENABLED = ns.Apply end",
                                   "for event in pairs(Events) do f:RegisterEvent(event) end"), [3]),
            "append after then": (lua(FRAME, "local events = { 'PLAYER_ENTERING_WORLD' }",
                                      "if not EllesmereUI.IS_FOREVER then events[#events + 1] = 'PLAYER_REGEN_ENABLED' end",
                                      "for _, e in ipairs(events) do f:RegisterEvent(e) end"), [3]),
            "append after ;": (lua(FRAME, "local events = {}; events[#events + 1] = 'PLAYER_REGEN_ENABLED'",
                                   "for _, e in ipairs(events) do f:RegisterEvent(e) end"), [2]),
            "alias after then": (lua("ns.watch = CreateFrame('Frame')", "ns.watch:RegisterEvent('PLAYER_REGEN_DISABLED')",
                                     "local watch", "if not watch then watch = ns.watch end",
                                     "watch:RegisterEvent('PLAYER_REGEN_ENABLED')"), []),
        })
        hits = g.unsafe_global_uses(g.lua_tokens("local y\nif c then y = GetItemInfo end\ny(link)\n"))
        self.assertEqual([h[2] for h in hits], ["store", "copy-call"])

    def test_calls_that_run_a_handler(self):
        self.assert_lines({
            "lowercase replay": (lua(FRAME, "f:RegisterEvent('PLAYER_ENTERING_WORLD')",
                                     "local onEvent = f:GetScript('OnEvent')",
                                     "if onEvent then onEvent(f, 'PLAYER_REGEN_ENABLED') end"), []),
            "Prefix_OnEvent": (lua(FRAME, "local function Watcher_OnEvent(self, event) end",
                                   "Watcher_OnEvent(f, 'PLAYER_REGEN_ENABLED')"), []),
            "camelCase handler": (lua(FRAME, "TrackerOnEvent(f, 'PLAYER_REGEN_ENABLED')"), []),
            "validity check": (lua(FRAME, "local EV = { 'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED' }",
                                   "for _, e in ipairs(EV) do if EventValid(e) then f:RegisterEvent(e) end end"), []),
            "registrar still caught": (lua("EventUtil.RegisterOnceFrameEventAndCallback('PLAYER_REGEN_ENABLED', fn)"), [1]),
            "Lite registrar still caught": (lua("function M:Go() EUILite._RegisterEvent(self, 'PLAYER_REGEN_ENABLED', fn) end"),
                                            [1]),
            "callback owner is no event list": (lua("local Owner = {}", "function Owner.PLAYER_REGEN_ENABLED() end",
                                                    "EventRegistry:RegisterCallback('SomeEvent', Owner.Fn, Owner)"), []),
        })

    def test_lists_held_in_fields(self):
        self.assert_lines({
            "append": (lua("inst.events = { 'PLAYER_ENTERING_WORLD' }",
                           "inst.events[#inst.events + 1] = 'PLAYER_REGEN_ENABLED'"), [2]),
            "tinsert": (lua("inst.events = { 'PLAYER_ENTERING_WORLD' }", "tinsert(inst.events, 'PLAYER_REGEN_ENABLED')"), [2]),
            "table.insert at 1": (lua("inst.events = {}", "table.insert(inst.events, 1, 'PLAYER_REGEN_ENABLED')"), [2]),
            "constructor and append are one list": (lua("inst.events = { 'PLAYER_REGEN_DISABLED' }",
                                                        "inst.events[#inst.events + 1] = 'PLAYER_REGEN_ENABLED'"), []),
            "factories keep their own lists": (lua(
                "function A() local inst = {}", "    inst.events = { 'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED' }", "end",
                "function B() local inst = {}", "    inst.events = {}",
                "    inst.events[#inst.events + 1] = 'PLAYER_REGEN_ENABLED'", "end"), [6]),
        })

    def test_event_names_and_tables_through_locals(self):
        loop = "for event in pairs(handlers) do f:RegisterEvent(event) end"
        self.assert_lines({
            "copy": (lua(FRAME, "local H = { PLAYER_ENTERING_WORLD = ns.Init, PLAYER_REGEN_ENABLED = ns.Apply }",
                         "local handlers = H", loop), [2]),
            "and/or choice": (lua(FRAME, "local R = { PLAYER_REGEN_ENABLED = ns.Apply }", "local V = { X = ns.Init }",
                                  "local handlers = EllesmereUI.IS_FOREVER and V or R", loop), [2]),
            "assigned later": (lua(FRAME, "local handlers",
                                   "handlers = { PLAYER_ENTERING_WORLD = ns.Init, PLAYER_REGEN_ENABLED = ns.Apply }",
                                   loop), [3]),
            "inline keyed table": (lua(FRAME, "ns.RegisterEvents(f, { X = ns.Init, PLAYER_REGEN_ENABLED = ns.Apply })"), [2]),
            "conditional constant": (lua(FRAME, "local EV = IS_FOREVER and 'PLAYER_ENTERING_WORLD' or 'PLAYER_REGEN_ENABLED'",
                                         "f:RegisterEvent(EV)"), [3]),
            "constant set later": (lua(FRAME, "local EV", "EV = 'PLAYER_REGEN_ENABLED'", "f:RegisterEvent(EV)"), [4]),
            "constant set in a branch": (lua(FRAME, "local ev = 'PLAYER_ENTERING_WORLD'",
                                             "if InCombatLockdown() then ev = 'PLAYER_REGEN_ENABLED' end",
                                             "f:RegisterEvent(ev)"), [4]),
            "parenthesized constant": (lua(FRAME, "local ev = ('PLAYER_REGEN_ENABLED')", "f:RegisterEvent(ev)"), [3]),
            "literal in the argument": (lua(FRAME, "f:RegisterEvent(c and 'PLAYER_REGEN_ENABLED' or 'X')",
                                            "f:RegisterEvent(event or 'PLAYER_REGEN_ENABLED')"), [2, 3]),
            "record list": (lua(FRAME, "local H = { { event = 'X', fn = ns.Init }, { event = 'PLAYER_REGEN_ENABLED' } }",
                                "for _, h in ipairs(H) do f:RegisterEvent(h.event) end"), [2]),
            "element copied in a numeric loop": (lua(FRAME, "local EVENTS = { 'X', 'PLAYER_REGEN_ENABLED' }",
                                                     "for i = 1, #EVENTS do local event = EVENTS[i]; f:RegisterEvent(event) end",
                                                     "f:RegisterEvent('PLAYER_REGEN_DISABLED')"), []),
            "tracker list through a copy": (lua(FRAME, "local EV = { 'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED' }",
                                                "local ev2 = EV", "for _, e in ipairs(ev2) do f:RegisterEvent(e) end"), []),
            "per-client inline lists": (lua(FRAME, "local EVENTS = IS_FOREVER and { 'PLAYER_REGEN_ENABLED' } "
                                                   "or { 'PLAYER_REGEN_ENABLED', 'X' }",
                                            "for _, e in ipairs(EVENTS) do f:RegisterEvent(e) end",
                                            "f:RegisterEvent('PLAYER_REGEN_DISABLED')"), []),
        })

    def test_inline_lists(self):
        self.assert_lines({
            "only unregistered": (lua(FRAME, "for _, ev in ipairs({ 'PLAYER_REGEN_ENABLED', 'UNIT_AURA' }) do",
                                      "    f:UnregisterEvent(ev)", "end"), []),
            "FrameUtil unregister": (lua(FRAME, "FrameUtil.UnregisterFrameForEvents(f, { 'PLAYER_REGEN_ENABLED', 'X' })"), []),
            "registered by a loop": (lua(FRAME, "for _, ev in ipairs({ 'PLAYER_REGEN_ENABLED', 'X' }) do "
                                                "f:RegisterEvent(ev) end"), [2]),
            "given to a factory": (lua("return MakeBlock(cfg, {", "    events = { 'X', 'PLAYER_REGEN_ENABLED' },", "})"), [2]),
            "stored": (lua("inst.events = { 'PLAYER_REGEN_ENABLED' }"), [1]),
        })

    def test_every_loop_owns_its_copy_and_a_new_frame_is_new(self):
        self.assert_lines({
            "two frames, one list": (lua("local a, b = CreateFrame('Frame'), CreateFrame('Frame')",
                                         "local EV = { 'PLAYER_REGEN_ENABLED' }",
                                         "for _, e in ipairs(EV) do a:RegisterEvent(e) end",
                                         "a:RegisterEvent('PLAYER_REGEN_DISABLED')",
                                         "for _, e in ipairs(EV) do b:RegisterEvent(e) end"), [2]),
            "a local given a new frame": (lua("local f = ns.combatWatch", "f:RegisterEvent('PLAYER_REGEN_DISABLED')",
                                              "f:RegisterEvent('PLAYER_REGEN_ENABLED')", "f = CreateFrame('Frame')",
                                              "f:RegisterEvent('PLAYER_REGEN_ENABLED')"), [5]),
            "lazy init keeps the frame": (lua("local f", "f = f or CreateFrame('Frame')",
                                              "f:RegisterEvent('PLAYER_REGEN_DISABLED')",
                                              "f:RegisterEvent('PLAYER_REGEN_ENABLED')"), []),
        })


class CombatRound5Repo(RepoCase):
    def test_editing_the_constant_or_the_loop_header_is_new(self):
        self.repo.write("K.lua", GATE + lua(FRAME, "local EV = 'PLAYER_ENTERING_WORLD'", "f:RegisterEvent(EV)"))
        self.repo.write("H.lua", GATE + lua(FRAME, "local A = { 'X' }", "local B = { 'PLAYER_REGEN_ENABLED' }",
                                            "for _, e in ipairs(A) do f:RegisterEvent(e) end"))
        base = self.repo.commit()
        self.repo.write("K.lua", GATE + lua(FRAME, "local EV = 'PLAYER_REGEN_ENABLED'", "f:RegisterEvent(EV)"))
        self.repo.write("H.lua", GATE + lua(FRAME, "local A = { 'X' }", "local B = { 'PLAYER_REGEN_ENABLED' }",
                                            "for _, e in ipairs(B) do f:RegisterEvent(e) end"))
        errors = self.repo.check(base, self.repo.commit(), [g.check_combat_deferral])
        self.assertEqual(sorted(e.split(": ")[0] for e in errors), ["H.lua:5", "K.lua:3"])


class TagsRound5(RepoCase):
    COMBAT = "-- guardrails-allow: combat-deferral by Ellesmere: re-applies after combat"
    ASCII = "-- guardrails-allow: ascii by Ellesmere: German labels"
    DEP = "-- guardrails-allow: deprecated-global by Ellesmere: retail-only path"

    def lines_of(self, path, body, checks=None):
        return [e.split(": ")[0] for e in self.errors_for(path, body, checks)]

    def test_a_tag_inside_a_function_body_covers_only_that_body(self):
        oe, ss = chr(0xF6) + chr(0xDF), chr(0x201C) + "Reset" + chr(0x201D)
        self.assertEqual(self.lines_of("A1.lua", lua(f"btn:SetScript('OnClick', function(self) -- {ss} button",
                                                     f"    self.label:SetText('Gr{oe}e') {self.ASCII}", "end)")),
                         ["A1.lua:2"])
        self.assertEqual(self.lines_of("P1.lua", lua("hooksecurefunc('EquipItemByName', function(item)",
                                                     f"    local name = GetItemInfo(item) {self.DEP}", "end)")),
                         ["P1.lua:2"])
        self.assertEqual(self.lines_of("C1.lua", lua(FRAME, "local handlers = {",
                                                     "    PLAYER_ENTERING_WORLD = function(self)",
                                                     f"        self:RegisterEvent('X') {self.COMBAT}", "    end,",
                                                     "    PLAYER_REGEN_ENABLED = function(self) self:Show() end,", "}",
                                                     "for ev in pairs(handlers) do f:RegisterEvent(ev) end"),
                                       [g.check_combat_deferral]), ["C1.lua:7"])
        self.assertEqual(self.lines_of("C3.lua", lua("function Mod:OnEnable()",
                                                     "    self:RegisterEvent('PLAYER_REGEN_ENABLED', function()",
                                                     f"        self:ApplyPending() {self.COMBAT}", "    end)", "end"),
                                       [g.check_combat_deferral]), ["C3.lua:3"])
        self.assertEqual(self.lines_of("R1.lua", lua("ns.RegisterEvent(function()",
                                                     f"    ns.Apply() {self.COMBAT}", "end, 'PLAYER_REGEN_ENABLED')"),
                                       [g.check_combat_deferral]), ["R1.lua:4"])
        # A call or table that holds a function takes the tag on one of its own lines
        self.assertEqual(self.lines_of("H1.lua", lua(f"ns.RegisterEvent('PLAYER_REGEN_ENABLED', function() {self.COMBAT}",
                                                     "    ns.Apply()", "end)"), [g.check_combat_deferral]), [])
        self.assertEqual(self.lines_of("H2.lua", lua("ns.RegisterEvent('PLAYER_REGEN_ENABLED', function()",
                                                     "    ns.Apply()", f"end) {self.COMBAT}"), [g.check_combat_deferral]), [])

    def test_a_table_tag_covers_rows_that_hold_a_function(self):
        oe, ho = chr(0xF6) + chr(0xDF), "H" + chr(0xF6) + "he"
        quote = chr(0x201C) + "helper" + chr(0x201D)
        self.assertEqual(self.lines_of("N1.lua", lua(f"local ROWS = {{ {self.ASCII}",
                                                     f"    {{ text = 'Gr{oe}e', get = function() return db.size end }},",
                                                     f"    {{ text = '{ho}' }},", "}")), [])
        self.assertEqual(self.lines_of("N4.lua", lua("local ROWS = {",
                                                     f"    {{ text = 'Gr{oe}e', onClick = function() end }},",
                                                     f"}} {self.ASCII}")), [])
        self.assertEqual(self.lines_of("N5.lua", lua(f"local T = {{ {self.ASCII}", f"    size = 'Gr{oe}e',",
                                                     "    get = function()", "        return 1", f"    end, -- {quote}",
                                                     "}")), [])
        self.assertEqual(self.lines_of("P1.lua", lua(f"local f = function() {self.ASCII}", "    return 1",
                                                     f"end -- {quote}")), [])
        # A string inside a function body belongs to the body
        self.assertEqual(self.lines_of("P3.lua", lua(f"local ROWS = {{ {self.ASCII}",
                                                     f"    {{ label = function() return 'Gr{oe}e' end }},", "}")),
                         ["P3.lua:3"])

    def test_a_tag_on_a_function_statement_end(self):
        self.assertEqual(self.lines_of("FnEnd.lua", lua(FRAME, "local Events = {}", "function Events.PLAYER_REGEN_ENABLED()",
                                                        "    ns.ApplyAll()", f"end {self.COMBAT}",
                                                        "for event in pairs(Events) do f:RegisterEvent(event) end"),
                                       [g.check_combat_deferral]), [])


class ExceptionsRound5(RepoCase):
    def test_tag_parsing(self):
        past = g.utc_today() - datetime.timedelta(days=9)
        cafe = "local s = 'caf" + chr(0xE9) + "'"
        cases = {
            "date after the approver": f"{cafe} -- guardrails-allow: ascii by Ellesmere {past}: stopgap",
            "Until in the approver": f"{cafe} -- guardrails-allow: ascii by Ellesmere Until {past}: stopgap",
            "blank approver": f"{cafe} -- guardrails-allow: ascii by   : French label",
            "reason is the comment close": f"{cafe} --[[ guardrails-allow: ascii by Ellesmere: ]]",
        }
        for name, line in cases.items():
            with self.subTest(case=name):
                errors = self.errors_for("T.lua", line + "\n")
                self.assertTrue(any("malformed guardrails-allow" in e for e in errors), errors)
                self.assertTrue(any("U+00E9" in e for e in errors), errors)

    def test_a_tag_never_borrows_the_next_ones_reason(self):
        line = ("local s = GetItemInfo(id) .. 'caf" + chr(0xE9) + "' -- guardrails-allow: ascii by Ellesmere; "
                "guardrails-allow: deprecated-global by Ellesmere: retail-only French tooltip\n")
        errors = self.errors_for("M.lua", line)
        self.assertEqual(len(errors), 2, errors)
        self.assertTrue(any("malformed guardrails-allow" in e for e in errors))
        self.assertTrue(any("U+00E9" in e for e in errors))

    def test_block_comments_are_read_whole(self):
        cafe = "local s = 'caf" + chr(0xE9) + "'"
        self.assertEqual(self.errors_for("B1.lua", f"{cafe} --[[ French label;\n"
                                                   "guardrails-allow: ascii by Ellesmere: French UI text ]]\n"), [])
        self.assertEqual(self.errors_for("B2.lua", f"{cafe} --[[ guardrails-allow: ascii by Ellesmere:\n"
                                                   "French UI text ]]\n"), [])
        errors = self.errors_for("B3.lua", "local y = 1 --[[ notes\nguardrails-allow: asci by Ellesmere: typo\nmore ]]\n")
        self.assertEqual([e.split(": ")[0] for e in errors], ["B3.lua:3"])


class GitRound5(RepoCase):
    BAD = GATE + "local f = CreateFrame('Frame')\nf:RegisterEvent('PLAYER_REGEN_ENABLED')\n"

    def test_pathspec_environment_is_ignored(self):
        self.repo.write("Mod/A.lua", self.BAD)
        head = self.repo.commit()
        self.repo.write("Mod/B.lua", self.BAD)
        for var in ("GIT_LITERAL_PATHSPECS", "GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS", "GIT_ICASE_PATHSPECS"):
            with self.subTest(var=var):
                saved = os.environ.get(var)
                os.environ[var] = "1"
                try:
                    worktree = self.repo.check(self.base, checks=[g.check_combat_deferral])
                    committed = self.repo.check(self.base, head, [g.check_combat_deferral])
                finally:
                    if saved is None:
                        os.environ.pop(var, None)
                    else:
                        os.environ[var] = saved
                self.assertEqual([e.split(": ")[0] for e in worktree], ["Mod/A.lua:3", "Mod/B.lua:3"])
                self.assertEqual([e.split(": ")[0] for e in committed], ["Mod/A.lua:3"])

    def test_no_index_yet(self):
        self.repo.write("Mod/A.lua", GATE + "local x = 1\n")
        base = self.repo.commit()
        os.remove(os.path.join(self.repo.dir, ".git", "index"))
        self.repo.write("Mod/A.lua", self.BAD)
        self.repo.write("Mod/New.lua", self.BAD)
        errors = self.repo.check(base, checks=[g.check_combat_deferral])
        self.assertEqual([e.split(": ")[0] for e in errors], ["Mod/A.lua:3", "Mod/New.lua:3"])

    def test_the_real_index_and_hooks_are_untouched(self):
        hooks = os.path.join(self.repo.dir, "myhooks")
        os.makedirs(hooks)
        with open(os.path.join(hooks, "post-index-change"), "w", newline="\n") as f:
            f.write("#!/bin/sh\necho ran >> hook-ran.txt\n")
        os.chmod(os.path.join(hooks, "post-index-change"), 0o755)
        self.repo.git("config", "core.hooksPath", "myhooks")
        self.repo.git("config", "core.splitIndex", "true")
        self.repo.write("Base.lua", GATE + "local x = 2\n")          # tracked, changed
        index = os.path.join(self.repo.dir, ".git", "index")
        for untracked in (False, True):
            with self.subTest(untracked=untracked):
                if untracked:
                    self.repo.write("Mod/New.lua", self.BAD)
                before = Path(index).read_bytes()
                shared = {p for p in os.listdir(os.path.join(self.repo.dir, ".git")) if p.startswith("sharedindex")}
                self.repo.check(self.base, checks=[g.check_combat_deferral])
                self.assertEqual(Path(index).read_bytes(), before)
                self.assertEqual({p for p in os.listdir(os.path.join(self.repo.dir, ".git"))
                                  if p.startswith("sharedindex")}, shared)
                self.assertFalse(os.path.exists(os.path.join(self.repo.dir, "hook-ran.txt")))

    def test_sparse_checkout(self):
        self.repo.write("ModA/A.lua", GATE + "local x = 1\n")
        self.repo.write("ModB/B.lua", GATE + "local x = 1\n")
        base = self.repo.commit()
        self.repo.git("sparse-checkout", "set", "--cone", "ModA")
        self.repo.write("ModC/New.lua", self.BAD)
        errors = self.repo.check(base, checks=[g.check_combat_deferral])
        self.assertEqual([e.split(": ")[0] for e in errors], ["ModC/New.lua:3"])

    def test_default_base_ignores_unrelated_and_local_refs(self):
        other = Repo()
        try:
            other.write("X.lua", GATE + "local x = 1\n")
            other.commit("unrelated")
            self.repo.git("update-ref", "refs/remotes/origin/main", "HEAD")
            self.repo.git("fetch", "-q", other.dir, "main:refs/remotes/upstream/main")
        finally:
            other.close()
        self.repo.git("branch", "origin/main", "HEAD")      # a local branch with that name
        saved = g.ROOT
        g.ROOT = self.repo.dir
        try:
            self.assertEqual(g.default_base(), "refs/remotes/origin/main")
        finally:
            g.ROOT = saved

    def test_a_note_when_origin_is_ahead_of_upstream(self):
        a = self.repo.git("rev-parse", "HEAD").strip()
        self.repo.write("Early.lua", self.BAD)
        b = self.repo.commit("on the fork's main")
        self.repo.git("checkout", "-q", "-b", "feat")
        self.repo.write("Mine.lua", GATE + "local y = 1\n")
        self.repo.commit("feature")
        self.repo.git("update-ref", "refs/remotes/upstream/main", a)
        self.repo.git("update-ref", "refs/remotes/origin/main", b)
        saved = g.ROOT
        g.ROOT = self.repo.dir
        try:
            base = g.default_base()
            note = g.base_note(base)
        finally:
            g.ROOT = saved
        self.assertEqual(base, "refs/remotes/origin/main")
        self.assertIn("pass --base upstream/main", note or "")

    def test_odd_committed_paths(self):
        self.repo.write("-Old/A.lua", GATE + "local name = GetItemInfo(6948)\n")
        head = self.repo.commit()
        errors = self.repo.check(self.base, head, [g.check_deprecated_globals])
        self.assertEqual([e.split(": ")[0] for e in errors], ["-Old/A.lua:2"])

    def test_upper_case_extensions(self):
        self.repo.write("Mod/Foo.Lua", "local f = CreateFrame('Frame')\nf:RegisterEvent('PLAYER_REGEN_ENABLED')\n")
        self.repo.write("Mod/Bar.LUA", GATE + "local id = GetSpecialization()\n")
        errors = self.repo.check(self.base, self.repo.commit())
        self.assertEqual(sorted(e.split(": ")[0] for e in errors), ["Mod/Bar.LUA:2", "Mod/Foo.Lua:1", "Mod/Foo.Lua:2"])


class Annotations(unittest.TestCase):
    def test_github_form(self):
        self.assertEqual(g.Error("Bad.lua", 2, "x\ny").annotation(),
                         "::error file=Bad.lua,line=2::Bad.lua:2: x%0Ay")
        self.assertEqual(g.Error(None, None, "no compiler").annotation(), "::error::no compiler")


if __name__ == "__main__":
    unittest.main()
