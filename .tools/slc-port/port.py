"""Ports EllesmereUI's edits of the Simple Loot Council module back into Laxx's two repos.

Usage: python -I port.py --eui <EllesmereUI repo> --dev <SimpleLootCouncil-dev clone>
           --port <EllesmereUI-SimpleLootCouncilPort clone> --out <work dir>
           [--branch NAME] [--message-file FILE] [--dry-run] [--pylib DIR]

The module folder (EllesmereUISimpleLootCouncil/) and the options page
(EllesmereUIOptions/EUI_SimpleLootCouncil_Options.lua) at our HEAD are his exporter's
output: for every shared file, HEAD == gate + transform(strip(source)), line for line
(the comments stripped, the line numbers kept). So an edit of ours against HEAD can be
replayed onto his source by line position. The tool:

  1. rebuilds his export from the two commits the module .toc names and refuses to go on
     unless it matches our HEAD byte for byte (the .tocs: everything but the lines EUI
     generates or edits by hand);
  2. diffs our HEAD against the working tree, maps each changed file back to the repo
     and path it came from, and replays the line edits onto the source read from that
     repo's base commit (a replaced or dropped source line that carried a comment is
     listed in the report so the comment can be put back by hand);
  3. writes the result (under <out>/ported/ on --dry-run, else as one commit on a branch
     per repo), then assembles the ported trees, runs his exporter in-process on them and
     proves the output equals the live module and options page byte for byte, and that
     every exported Lua file compiles under Lua 5.1.

Only stdlib plus lupa (for the Lua 5.1 compile check). ASCII only.
"""
import argparse
import difflib
import importlib
import io
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

SCRATCH = Path(r"C:/Users/elles/AppData/Local/Temp/claude/D--Program-Files--x86--World-of-Warcraft"
               r"--retail--Interface-AddOns-EllesmereUI/9e067576-c29b-4381-98dd-a059412e42b4/scratchpad")
DEFAULT_EUI = Path(r"D:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/EllesmereUI")
DEFAULT_DEV = SCRATCH / "slcport" / "dev"
DEFAULT_PORT = SCRATCH / "slcport" / "port"
DEFAULT_OUT = SCRATCH / "slcport" / "out"
DEFAULT_PYLIB = Path(r"C:/Users/elles/Desktop/Ellesmere Gaming/Addon Testing/EUIPerf/dev/pylib")

FOLDER = "EllesmereUISimpleLootCouncil"
TOC_NAME = FOLDER + ".toc"
CAMELOT_TOC = FOLDER + "_Camelot.toc"
OPTIONS_PAGE = "EllesmereUIOptions/EUI_SimpleLootCouncil_Options.lua"
OPTIONS_PORT = "options/EUI_SimpleLootCouncil_Options.lua"
OPTIONS_TREE = "eui/EUI_SimpleLootCouncil_Options.lua"
# Module files that come from the port repo's edition/ folder; everything else is SLC's.
EDITION_FILES = {"Edition.lua", "Locale.lua", "OptionsBridge.lua", "CombatQueue.lua",
                 "LICENSE.txt", TOC_NAME, CAMELOT_TOC}
# How tools/assemble.py lays the port repo's tracked files into the assembled tree.
PORT_DIRS = [("edition", "eui", None), ("options", "eui", None), ("style", "UI/EUI", None),
             ("tests", "dev", ".lua")]
PORT_SINGLE = {"tools/eui_export.py": "dev/eui_export.py",
               "docs/eui-edition.md": "docs/decisions/eui-edition.md"}
# .toc lines the exporter generates; compared by nobody, reported by value.
GENERATED_KEYS = ("Interface", "Version", "X-SLC-Commit", "X-SLC-Port-Commit")
# EUI-side .toc lines: the hold block the owner adds by hand, and the sibling-addon line
# the owner drops by hand. Never added to or removed from his .tocs; reported.
HOLD_PREFIXES = ("# Held back (EllesmereUI.HELD_BACK_ADDONS)", "# it, so it never loads")
HOLD_LINE = "## LoadOnDemand: 1"
SIBLING = re.compile(r"\.\.[\\/][A-Za-z0-9][A-Za-z0-9_-]*[\\/](?!\.\.)[^\s]+$")
DEFAULT_STATE = "## DefaultState: disabled"
BOM = b"\xef\xbb\xbf"
LONG_OPEN = re.compile(r"\[(=*)\[")
DIGITS = re.compile(r"[0-9]{1,3}")
BLOCK_COMMENT = re.compile(r"--\[=*\[")


class PortError(Exception):
    pass


# ---------------------------------------------------------------- git and files

def git(repo, *args, binary=False):
    done = subprocess.run(["git", "-C", str(repo), *args], capture_output=True)
    if done.returncode != 0:
        raise PortError("git %s failed in %s: %s"
                        % (" ".join(args), repo, done.stderr.decode("utf-8", "replace").strip()))
    return done.stdout if binary else done.stdout.decode("utf-8")


def git_show(repo, rev, path):
    """The blob at rev:path, or None when it is not there."""
    done = subprocess.run(["git", "-C", str(repo), "show", "%s:%s" % (rev, path)], capture_output=True)
    if done.returncode != 0:
        return None
    return done.stdout


def git_tracked(repo, rev, prefix=""):
    args = ["ls-tree", "-r", "--name-only", rev]
    if prefix:
        args += ["--", prefix]
    return [line for line in git(repo, *args).splitlines() if line]


def norm(data):
    return data.replace(b"\r\n", b"\n")


def is_text(path):
    return not path.endswith(".tga")


def read_live(path):
    data = path.read_bytes()
    return norm(data) if is_text(path.name) else data


def under(path, root):
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def clear_dir(path, out):
    if not under(path, out):
        raise PortError("refusing to clear %s: not under %s" % (path, out))
    if path.exists():
        shutil.rmtree(path)


def port_map(rel):
    """The assembled-tree path of a port repo file, or None when it goes nowhere."""
    if rel in PORT_SINGLE:
        return PORT_SINGLE[rel]
    for src_dir, dest_dir, suffix in PORT_DIRS:
        if rel.startswith(src_dir + "/") and (suffix is None or rel.endswith(suffix)):
            return dest_dir + "/" + rel[len(src_dir) + 1:]
    return None


def write_tree_file(dest, data):
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)


def assemble_tree(dest, out, dev, dev_rev, port, port_rev, overlay=None):
    """git archive of dev@dev_rev plus port@port_rev laid out as tools/assemble.py does.

    overlay maps ("dev"|"port", repo path) -> bytes written on top (the dry run's ported
    files, which no commit holds yet)."""
    clear_dir(dest, out)
    dest.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(git(dev, "archive", "--format=tar", dev_rev, binary=True))) as tar:
        tar.extractall(dest, filter="data")
    with tarfile.open(fileobj=io.BytesIO(git(port, "archive", "--format=tar", port_rev, binary=True))) as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            mapped = port_map(member.name)
            if mapped is None:
                continue
            target = dest / mapped
            if target.exists():
                raise PortError("SLC %s still carries the port file %s" % (dev_rev, mapped))
            write_tree_file(target, tar.extractfile(member).read())
    for (repo, rel), data in (overlay or {}).items():
        mapped = rel if repo == "dev" else port_map(rel)
        if mapped is None:
            raise PortError("overlay file %s has no place in the assembled tree" % rel)
        write_tree_file(dest / mapped, data)


def load_exporter(dev_dir):
    """His eui_export (and strip_comments beside it) imported from an assembled tree."""
    sys.path.insert(0, str(dev_dir))
    exporter = importlib.import_module("eui_export")
    stripper = importlib.import_module("strip_comments")
    return exporter, stripper


# ---------------------------------------------------------------- the export

def toc_fields(exporter, path, keys):
    headers, _ = exporter.read_toc(path)
    return {key: exporter.header(headers, key) for key in keys}


def export_tree(exporter, tree, eui_toc, slc_commit, port_commit):
    """build() on an assembled tree: {our repo path: bytes} for the module and the page."""
    headers, entries = exporter.read_toc(tree / "eui" / exporter.TOC_NAME)
    cam_headers, cam_entries = exporter.read_toc(tree / "eui" / exporter.CAMELOT_TOC)
    drift = exporter.camelot_drift(headers, entries, cam_headers, cam_entries)
    if drift:
        raise PortError("%s: %s" % (tree, drift))
    files, options, missing = exporter.build(tree, headers, entries, eui_toc, slc_commit, False,
                                             port_commit, cam_headers)
    if missing:
        raise PortError("export from %s skipped files: %s" % (tree, ", ".join(missing)))
    if options is None:
        raise PortError("export from %s made no options page" % tree)
    produced = {FOLDER + "/" + dest: data for dest, data in files.items()}
    produced[OPTIONS_PAGE] = options
    return produced


def toc_line_key(line):
    m = re.match(r"##\s*([\w-]+)\s*:", line.strip())
    return m.group(1) if m else None


def is_generated(line):
    return toc_line_key(line) in GENERATED_KEYS


def is_hold(line):
    s = line.strip()
    return s == HOLD_LINE or any(s.startswith(p) for p in HOLD_PREFIXES)


def is_sibling(line):
    return bool(SIBLING.match(line.strip()))


def toc_compared(text):
    """The .toc lines the comparisons look at: everything but the generated and the
    EUI-side lines (hold block, sibling-addon lines)."""
    return [line for line in text.split("\n")
            if not (is_generated(line) or is_hold(line) or is_sibling(line))]


def first_difference(a_lines, b_lines):
    for k, (a, b) in enumerate(zip(a_lines, b_lines)):
        if a != b:
            return "line %d: %r != %r" % (k + 1, a[:120], b[:120])
    if len(a_lines) != len(b_lines):
        return "line %d: one side ends" % (min(len(a_lines), len(b_lines)) + 1)
    return "identical"


def compare_files(produced, reference, reference_paths):
    """[(path, why)] where the produced export differs from the reference.

    reference(path) -> bytes or None (text CRLF-normalized); reference_paths is the set of
    files the reference holds under the module folder plus the options page."""
    mismatches = []
    for path in sorted(set(produced) | set(reference_paths)):
        made = produced.get(path)
        ref = reference(path) if path in reference_paths else None
        if made is None:
            mismatches.append((path, "in the reference but not in the export"))
        elif ref is None:
            mismatches.append((path, "in the export but not in the reference"))
        elif path.endswith(".toc"):
            a = toc_compared(made.decode("utf-8"))
            b = toc_compared(ref.decode("utf-8"))
            if a != b:
                mismatches.append((path, "(.toc, generated and EUI-side lines ignored) "
                                   + first_difference(a, b)))
        elif made != ref:
            if is_text(path):
                why = first_difference(made.decode("utf-8", "replace").split("\n"),
                                       ref.decode("utf-8", "replace").split("\n"))
            else:
                why = "binary content differs"
            mismatches.append((path, why))
    return mismatches


# ---------------------------------------------------------------- our delta

def live_delta(eui):
    """{our repo path: (HEAD bytes or None, live bytes or None)} for the module and page."""
    paths = set(git_tracked(eui, "HEAD", FOLDER))
    folder = eui / FOLDER
    if folder.is_dir():
        for path in folder.rglob("*"):
            if path.is_file():
                paths.add(path.relative_to(eui).as_posix())
    paths.add(OPTIONS_PAGE)
    delta = {}
    for rel in sorted(paths):
        head = git_show(eui, "HEAD", rel)
        if head is not None and is_text(rel):
            head = norm(head)
        live_path = eui / rel
        live = read_live(live_path) if live_path.is_file() else None
        delta[rel] = (head, live)
    return delta


def reverse_map(rel):
    """Our repo path -> ("dev"|"port", path in that repo)."""
    if rel == OPTIONS_PAGE:
        return "port", OPTIONS_PORT
    if not rel.startswith(FOLDER + "/"):
        raise PortError("not a module path: " + rel)
    rest = rel[len(FOLDER) + 1:]
    if rest in EDITION_FILES:
        return "port", "edition/" + rest
    if rest.startswith("UI/EUI/"):
        return "port", "style/" + rest[len("UI/EUI/"):]
    return "dev", rest


def suggest_home(data):
    text = data.decode("utf-8", "replace")
    return "port edition/" if "EllesmereUI" in text else "dev"


# ---------------------------------------------------------------- the positional port

def decode_escapes(text):
    """Turns runs of \\ddd escapes (bytes 128..255) inside quoted strings back into the
    UTF-8 text they encode, so the exporter's transform gives the same escapes again.
    Everything else is copied."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "-" and text.startswith("--", i):
            m = LONG_OPEN.match(text, i + 2)
            if m:
                close = "]" + m.group(1) + "]"
                end = text.find(close, m.end())
                end = n if end < 0 else end + len(close)
            else:
                end = text.find("\n", i)
                end = n if end < 0 else end
            out.append(text[i:end])
            i = end
            continue
        if c == "[" and LONG_OPEN.match(text, i):
            m = LONG_OPEN.match(text, i)
            close = "]" + m.group(1) + "]"
            end = text.find(close, m.end())
            end = n if end < 0 else end + len(close)
            out.append(text[i:end])
            i = end
            continue
        if c in "\"'":
            buf, j = [c], i + 1
            while j < n and text[j] != c:
                ch = text[j]
                if ch != "\\":
                    buf.append(ch)
                    j += 1
                    continue
                values, raw, k = [], [], j
                while True:
                    m = DIGITS.match(text, k + 1) if k < n and text[k] == "\\" else None
                    if not (m and len(m.group()) == 3 and 128 <= int(m.group()) <= 255):
                        break
                    values.append(int(m.group()))
                    raw.append(text[k:m.end()])
                    k = m.end()
                if values:
                    try:
                        buf.append(bytes(values).decode("utf-8"))
                    except UnicodeDecodeError:
                        buf.extend(raw)
                    j = k
                    continue
                buf.append(ch)
                if j + 1 < n:
                    buf.append(text[j + 1])
                j += 2
            if j < n:
                buf.append(c)
                j += 1
            out.append("".join(buf))
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)


def split_gate(exporter, line, allow_bare):
    """The rest of a line that starts with EUI's client gate, or None."""
    gate = exporter.CLIENT_GATE
    if line.startswith(gate):
        return line[len(gate):]
    if allow_bare and line == gate.rstrip():
        return ""
    return None


def port_lua(exporter, stripper, rel, source, head, live, is_options):
    """Replays the HEAD -> live line edits onto the source. Returns (bytes to write,
    info dict for the report). Raises PortError when the invariant does not hold."""
    gate = exporter.CLIENT_GATE
    has_bom = source.startswith(BOM)
    crlf = b"\r\n" in source
    src_text = (source[len(BOM):] if has_bom else source).decode("utf-8").replace("\r\n", "\n")
    stripped = stripper.strip(src_text)
    transformed = exporter.transform(rel, stripped)
    prefix = "" if (is_options and transformed.startswith(gate.rstrip())) else gate
    head_text = head.decode("utf-8")
    if prefix + transformed != head_text:
        raise PortError("%s: HEAD is not gate + transform(strip(source)): %s"
                        % (rel, first_difference((prefix + transformed).split("\n"), head_text.split("\n"))))

    live_text = live.decode("utf-8")
    head_lines = head_text.split("\n")
    live_lines = live_text.split("\n")
    if prefix:
        head_lines[0] = head_lines[0][len(prefix):]
        rest = split_gate(exporter, live_lines[0], allow_bare=True)
    else:
        rest = live_lines[0] if split_gate(exporter, live_lines[0], allow_bare=True) is not None else None
    if rest is None:
        raise PortError("%s: the live file's line 1 does not start with EUI's client gate" % rel)
    live_lines[0] = rest
    src_lines = src_text.split("\n")
    strip_lines = stripped.split("\n")
    if len(src_lines) != len(head_lines):
        raise PortError("%s: source has %d lines, HEAD %d" % (rel, len(src_lines), len(head_lines)))

    out, lost, ops = [], [], []
    added = removed = 0
    matcher = difflib.SequenceMatcher(None, head_lines, live_lines, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            out.extend(src_lines[i1:i2])
            continue
        ops.append("%s HEAD %d-%d -> live %d-%d" % (tag, i1 + 1, i2, j1 + 1, j2))
        if tag in ("delete", "replace"):
            removed += i2 - i1
            for k in range(i1, i2):
                line = src_lines[k].rstrip()
                if strip_lines[k] != line:
                    text = line[len(strip_lines[k]):] if line.startswith(strip_lines[k]) else line
                    lost.append((rel, k + 1, text.strip()))
        if tag in ("insert", "replace"):
            added += j2 - j1
            out.extend(decode_escapes("\n".join(live_lines[j1:j2])).split("\n"))
    ported = "\n".join(out)

    check = prefix + exporter.transform(rel, stripper.strip(ported))
    file_round_trip = "ok" if check == live_text else "MISMATCH " + first_difference(
        check.split("\n"), live_text.split("\n"))

    warnings = []
    for m in BLOCK_COMMENT.finditer(src_text):
        warnings.append("block comment opens at source line %d; the replay is line based, "
                        "the round trip decides" % (src_text.count("\n", 0, m.start()) + 1))
    data = ported.encode("utf-8")
    if crlf:
        data = data.replace(b"\n", b"\r\n")
    if has_bom:
        data = BOM + data
    info = {"ops": ops, "added": added, "removed": removed, "lost": lost,
            "round_trip": file_round_trip, "warnings": warnings,
            "newline": "CRLF" if crlf else "LF", "bom": has_bom}
    return data, info


# ---------------------------------------------------------------- the .tocs

def toc_significant_lines(text, camelot):
    """The lines of his .toc the exporter keeps and the comparisons look at: no blank or
    comment lines, no generated or EUI-side lines, and the twin's DefaultState set aside."""
    out = []
    for k, raw in enumerate(text.split("\n")):
        line = raw.strip()
        if not line or (line.startswith("#") and not line.startswith("##")):
            continue
        if is_generated(line) or is_hold(line) or is_sibling(line):
            continue
        if camelot and line == DEFAULT_STATE:
            continue
        out.append(k)
    return out


def export_form(line):
    line = line.strip()
    return line[4:] if line.lower().startswith("eui\\") or line.lower().startswith("eui/") else line


def source_form(line):
    """An exported .toc line as his .toc writes it (edition files under eui\\)."""
    line = line.strip()
    if line.startswith("##"):
        return line
    name = line.replace("/", "\\").split("\\")[-1]
    if "\\" not in line and name in EDITION_FILES:
        return "eui\\" + line
    return line


def port_toc(his_text, head_text, live_text, camelot):
    """Applies the HEAD -> live edits of the exported .toc to his source .toc. Returns
    (new text or None when nothing changed, [ops], [notes])."""
    raw = his_text.split("\n")
    sig = toc_significant_lines(his_text, camelot)
    his = [export_form(raw[k]) for k in sig]
    head = [line.strip() for line in toc_compared(head_text) if line.strip()]
    live = [line.strip() for line in toc_compared(live_text) if line.strip()]
    if his != head:
        raise PortError("his .toc at the base commit does not read as the exported baseline: "
                        + first_difference(his, head))
    inserts, removed, ops = {}, set(), []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, head, live, autojunk=False).get_opcodes():
        if tag == "equal":
            continue
        ops.append("%s HEAD %d-%d -> live %d-%d" % (tag, i1 + 1, i2, j1 + 1, j2))
        if tag in ("delete", "replace"):
            removed.update(sig[k] for k in range(i1, i2))
        if tag in ("insert", "replace"):
            at = sig[i1] if i1 < len(sig) else len(raw)
            inserts.setdefault(at, []).extend(source_form(line) for line in live[j1:j2])
    if not ops:
        return None, ops, []
    out = []
    for k, line in enumerate(raw):
        out.extend(inserts.get(k, []))
        if k not in removed:
            out.append(line)
    out.extend(inserts.get(len(raw), []))
    return "\n".join(out), ops, []


def toc_notes(label, text):
    """Where the EUI-side lines sit in a .toc, for the report."""
    lines = text.split("\n")
    hold = [k + 1 for k, line in enumerate(lines) if is_hold(line)]
    sib = [(k + 1, line.strip()) for k, line in enumerate(lines) if is_sibling(line)]
    gen = [line.strip() for line in lines if is_generated(line)]
    notes = ["%s: hold block at lines %s" % (label, hold if hold else "(absent)")]
    notes.append("%s: sibling-addon lines %s" % (label, sib if sib else "(none)"))
    notes.append("%s: generated %s" % (label, gen if gen else "(none)"))
    return notes


# ---------------------------------------------------------------- checks

def lua51_check(pylib, files):
    """[(path, error)] for exported Lua files Lua 5.1 refuses to compile."""
    sys.path.insert(0, str(pylib))
    lua51 = importlib.import_module("lupa.lua51")
    runtime = lua51.LuaRuntime()
    loadstring = runtime.globals().loadstring
    bad = []
    for path, data in sorted(files.items()):
        if not path.endswith(".lua"):
            continue
        result = loadstring(data, "=" + path)
        if isinstance(result, tuple) and result[0] is None:
            bad.append((path, str(result[1])))
    return bad


def round_trip(exporter, out, dev, dev_rev, port, port_rev, overlay, eui, eui_toc, commits, pylib):
    tree = out / "assembled-ported"
    assemble_tree(tree, out, dev, dev_rev, port, port_rev, overlay)
    produced = export_tree(exporter, tree, eui_toc, commits["X-SLC-Commit"], commits["X-SLC-Port-Commit"])
    live_paths = set()
    folder = eui / FOLDER
    for path in folder.rglob("*"):
        if path.is_file():
            live_paths.add(path.relative_to(eui).as_posix())
    live_paths.add(OPTIONS_PAGE)

    def reference(rel):
        path = eui / rel
        return read_live(path) if path.is_file() else None

    mismatches = compare_files(produced, reference, live_paths)
    bad_lua = lua51_check(pylib, produced)
    return produced, mismatches, bad_lua


# ---------------------------------------------------------------- report

def write_report(path, ctx):
    lines = ["# SLC port report", ""]
    lines.append("- EllesmereUI repo: %s (HEAD %s)" % (ctx["eui"], ctx["eui_head"]))
    lines.append("- dev clone: %s, base %s%s" % (ctx["dev"], ctx["dev_base"], ctx["dev_branch_note"]))
    lines.append("- port clone: %s, base %s%s" % (ctx["port"], ctx["port_base"], ctx["port_branch_note"]))
    lines.append("- mode: %s" % ("dry run (files under %s)" % ctx["ported_dir"] if ctx["dry_run"] else "commit"))
    lines.append("")
    lines.append("## Baseline")
    lines.append("")
    lines.append("His export of dev@%s + port@%s matches our HEAD: %d files byte for byte "
                 "(the .tocs: everything but the generated and EUI-side lines)."
                 % (ctx["dev_base"], ctx["port_base"], ctx["baseline_count"]))
    lines.append("")
    lines.append("## Delta (HEAD -> working tree)")
    lines.append("")
    lines.append("- changed: %d, new: %d, deleted: %d, unchanged: %d"
                 % (len(ctx["changed"]), len(ctx["new"]), len(ctx["deleted"]), ctx["unchanged"]))
    lines.append("")
    lines.append("## Ported files")
    lines.append("")
    total_lost = 0
    for rel in ctx["changed"]:
        info = ctx["files"][rel]
        lines.append("### %s" % rel)
        lines.append("")
        lines.append("- source: %s %s (%s%s)" % (info["repo"], info["path"], info.get("newline", "-"),
                                                 ", BOM" if info.get("bom") else ""))
        if info.get("kind") == "copy":
            lines.append("- copied as is (%s)" % info["note"])
        elif info.get("kind") == "toc":
            lines.append("- .toc edits: %s" % (", ".join(info["ops"]) if info["ops"] else "none"))
            for note in info["notes"]:
                lines.append("- %s" % note)
        else:
            lines.append("- lines: +%d -%d; opcodes: %d" % (info["added"], info["removed"], len(info["ops"])))
            for op in info["ops"]:
                lines.append("  - %s" % op)
            if info["lost"]:
                lines.append("- comments lost (%d):" % len(info["lost"]))
                for file, number, text in info["lost"]:
                    lines.append("  - %s:%d: %s" % (file, number, text))
                total_lost += len(info["lost"])
            else:
                lines.append("- comments lost: none")
            for warning in info["warnings"]:
                lines.append("- warning: %s" % warning)
            lines.append("- file round trip: %s" % info["round_trip"])
        lines.append("")
    lines.append("## .toc notes")
    lines.append("")
    for note in ctx["toc_notes"]:
        lines.append("- %s" % note)
    lines.append("")
    lines.append("## Unplaced")
    lines.append("")
    if ctx["new"] or ctx["deleted"]:
        for rel, home in ctx["new"]:
            lines.append("- new in the working tree, not placed: %s (suggested: %s)" % (rel, home))
        for rel in ctx["deleted"]:
            lines.append("- deleted in the working tree, not removed from his repo: %s" % rel)
    else:
        lines.append("- none")
    lines.append("")
    lines.append("## Round trip")
    lines.append("")
    lines.append("- %s" % ctx["round_trip"])
    for rel, why in ctx["mismatches"]:
        lines.append("  - %s: %s" % (rel, why))
    lines.append("- Lua 5.1 compile: %s" % ("all %d files" % ctx["lua_count"] if not ctx["bad_lua"]
                                          else "%d FAILED" % len(ctx["bad_lua"])))
    for rel, err in ctx["bad_lua"]:
        lines.append("  - %s: %s" % (rel, err))
    lines.append("- comments lost in all: %d" % total_lost)
    lines.append("")
    path.write_bytes(("\n".join(lines)).encode("ascii", "backslashreplace"))
    return total_lost


# ---------------------------------------------------------------- main

def default_message(dev_base, port_base, version):
    return ("Port EllesmereUI's review fixes of the %s export\n\n"
            "The edits EllesmereUI made to its exported copy of the module (its\n"
            "EllesmereUISimpleLootCouncil folder and options page), replayed line for\n"
            "line onto the exported commits (SLC %s, port %s) by EllesmereUI's\n"
            ".tools/slc-port/port.py. Comments on the lines the edits replaced are\n"
            "listed in that tool's report.\n" % (version, dev_base, port_base))


def commit_branch(repo, branch, base, files, message_file):
    """git checkout -B branch base; write files; one commit. Returns the branch."""
    if git(repo, "status", "--porcelain").strip():
        raise PortError("%s has uncommitted changes; the port needs a clean tree" % repo)
    git(repo, "checkout", "-B", branch, base)
    for rel, data in files.items():
        write_tree_file(repo / rel, data)
    git(repo, "add", "-A")
    git(repo, "commit", "-F", str(message_file))
    return branch


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--eui", type=Path, default=DEFAULT_EUI)
    ap.add_argument("--dev", type=Path, default=DEFAULT_DEV)
    ap.add_argument("--port", type=Path, default=DEFAULT_PORT)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--branch")
    ap.add_argument("--message-file", type=Path)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--pylib", type=Path, default=DEFAULT_PYLIB)
    args = ap.parse_args()
    try:
        return run(args)
    except PortError as err:
        print("port failed: %s" % err, file=sys.stderr)
        return 1


def run(args):
    eui, dev, port, out = (p.resolve() for p in (args.eui, args.dev, args.port, args.out))
    for repo, name in ((eui, "EllesmereUI.toc"), (dev, "SimpleLootCouncil.toc"), (port, "slc.lock")):
        if not (repo / name).is_file():
            raise PortError("%s does not look like the expected repo (no %s)" % (repo, name))
    out.mkdir(parents=True, exist_ok=True)

    # 1. The commits the live module .toc names; HEAD's must agree.
    live_toc = eui / FOLDER / TOC_NAME
    head_toc = git_show(eui, "HEAD", FOLDER + "/" + TOC_NAME)
    if head_toc is None or not live_toc.is_file():
        raise PortError("the module .toc is missing from HEAD or the working tree")
    keys = ("X-SLC-Commit", "X-SLC-Port-Commit", "X-SLC-Version")
    tmp = out / "head.toc"
    tmp.write_bytes(head_toc)
    tree_base = out / "assembled-base"
    # The exporter is his: import it from the base tree, so first assemble that.
    dev_base = (git(dev, "rev-parse", "--verify", "%s^{commit}" % read_header(live_toc, "X-SLC-Commit")).strip())
    port_base = (git(port, "rev-parse", "--verify", "%s^{commit}" % read_header(live_toc, "X-SLC-Port-Commit")).strip())
    assemble_tree(tree_base, out, dev, dev_base, port, port_base)
    exporter, stripper = load_exporter(tree_base / "dev")
    commits = toc_fields(exporter, live_toc, keys)
    head_commits = toc_fields(exporter, tmp, keys)
    tmp.unlink()
    if commits != head_commits:
        raise PortError("the live module .toc names other commits than HEAD's: %s vs %s" % (commits, head_commits))
    for key in ("X-SLC-Commit", "X-SLC-Port-Commit"):
        if not commits[key]:
            raise PortError("the module .toc has no ## %s line" % key)
    eui_toc = toc_fields(exporter, eui / "EllesmereUI.toc", ("Interface", "Version"))
    if not all(eui_toc.values()):
        raise PortError("EllesmereUI.toc has no Interface or Version line")
    eui_head = git(eui, "rev-parse", "--short=12", "HEAD").strip()
    print("base: dev %s, port %s; EllesmereUI HEAD %s" % (dev_base[:12], port_base[:12], eui_head))

    # 2. Baseline: his export of the base commits must be our HEAD.
    produced = export_tree(exporter, tree_base, eui_toc, commits["X-SLC-Commit"], commits["X-SLC-Port-Commit"])
    head_paths = set(git_tracked(eui, "HEAD", FOLDER)) | {OPTIONS_PAGE}

    def head_reference(rel):
        data = git_show(eui, "HEAD", rel)
        return norm(data) if (data is not None and is_text(rel)) else data

    mismatches = compare_files(produced, head_reference, head_paths)
    if mismatches:
        print("BASELINE MISMATCH: HEAD is not his export of the named commits; stopping.")
        for rel, why in mismatches:
            print("  %s: %s" % (rel, why))
        raise PortError("%d baseline mismatches" % len(mismatches))
    print("baseline: OK (%d files)" % len(produced))

    # 3. Our delta.
    delta = live_delta(eui)
    changed, new, deleted, unchanged = [], [], [], 0
    for rel, (head, live) in delta.items():
        if head is None:
            new.append((rel, suggest_home(live)))
        elif live is None:
            deleted.append(rel)
        elif head != live:
            changed.append(rel)
        else:
            unchanged += 1
    print("delta: %d changed, %d new, %d deleted" % (len(changed), len(new), len(deleted)))

    # 4-6. Port each changed file onto the source read from its repo's base commit.
    ported = {"dev": {}, "port": {}}
    files, notes = {}, []
    toc_sources = {}
    for rel in changed:
        repo_key, path = reverse_map(rel)
        repo, base = (dev, dev_base) if repo_key == "dev" else (port, port_base)
        source = git_show(repo, base, path)
        if source is None:
            raise PortError("%s maps to %s %s, which the base commit does not hold" % (rel, repo_key, path))
        head, live = delta[rel]
        info = {"repo": repo_key, "path": path}
        if rel.endswith(".lua"):
            data, extra = port_lua(exporter, stripper, path, source, head, live, rel == OPTIONS_PAGE)
            info.update(extra)
            ported[repo_key][path] = data
        elif rel.endswith(".toc"):
            his_text = source.decode("utf-8-sig").replace("\r\n", "\n")
            text, ops, _ = port_toc(his_text, head.decode("utf-8"), live.decode("utf-8"), rel.endswith("_Camelot.toc"))
            info.update({"kind": "toc", "ops": ops, "notes": [], "newline": "CRLF" if b"\r\n" in source else "LF"})
            if text is not None:
                data = text.encode("utf-8")
                if b"\r\n" in source:
                    data = data.replace(b"\n", b"\r\n")
                ported[repo_key][path] = data
            else:
                info["notes"].append("only generated or EUI-side lines differ; his .toc is not touched")
        else:
            data = live if not is_text(rel) else (live.replace(b"\n", b"\r\n") if b"\r\n" in source else live)
            info.update({"kind": "copy", "note": "binary" if not is_text(rel) else "text, source newline style"})
            ported[repo_key][path] = data
        files[rel] = info
    for rel, (head, live) in delta.items():
        if rel.endswith(".toc") and head is not None and live is not None:
            notes.extend(toc_notes("HEAD " + rel, head.decode("utf-8")))
            notes.extend(toc_notes("live " + rel, live.decode("utf-8")))
            repo_key, path = reverse_map(rel)
            his = git_show(port, port_base, path)
            notes.extend(toc_notes("his " + path, his.decode("utf-8-sig")))
    toc_paths = ("edition/" + TOC_NAME, "edition/" + CAMELOT_TOC)
    if any(path in ported["port"] for path in toc_paths):
        # The twin must still be the plain .toc plus its DefaultState line.
        check_dir = out / "toc-check"
        check_dir.mkdir(exist_ok=True)
        for path in toc_paths:
            data = ported["port"].get(path) or git_show(port, port_base, path)
            (check_dir / path.split("/")[-1]).write_bytes(data)
        hs, es = exporter.read_toc(check_dir / TOC_NAME)
        ch, ce = exporter.read_toc(check_dir / CAMELOT_TOC)
        drift = exporter.camelot_drift(hs, es, ch, ce)
        if drift:
            raise PortError("ported .tocs: " + drift)

    # Write the ported files under <out>/ported/ in every mode.
    ported_dir = out / "ported"
    clear_dir(ported_dir, out)
    for repo_key in ("dev", "port"):
        for path, data in ported[repo_key].items():
            write_tree_file(ported_dir / repo_key / path, data)
    print("ported: %d dev files, %d port files -> %s" % (len(ported["dev"]), len(ported["port"]), ported_dir))

    # 7. Branches and commits, unless --dry-run.
    version = commits.get("X-SLC-Version") or "fixes"
    branch = args.branch or ("eui-port-" + version)
    dev_rev, port_rev, overlay = dev_base, port_base, None
    dev_note = port_note = ""
    if args.dry_run:
        overlay = {}
        for repo_key in ("dev", "port"):
            for path, data in ported[repo_key].items():
                overlay[(repo_key, path)] = data
    else:
        message_file = args.message_file
        if message_file is None:
            message_file = out / "commit-message.txt"
            message_file.write_bytes(default_message(dev_base[:12], port_base[:12], version).encode("ascii"))
        for repo_key, repo, base in (("dev", dev, dev_base), ("port", port, port_base)):
            if not ported[repo_key]:
                print("%s: no changes, no commit" % repo_key)
                continue
            commit_branch(repo, branch, base, ported[repo_key], message_file)
            sha = git(repo, "rev-parse", "--short=12", branch).strip()
            print("%s: committed %s on %s" % (repo_key, sha, branch))
            if repo_key == "dev":
                dev_rev, dev_note = branch, " -> branch %s (%s)" % (branch, sha)
            else:
                port_rev, port_note = branch, " -> branch %s (%s)" % (branch, sha)

    # 8. Round trip: export the ported trees and compare with the live files.
    produced, mismatches, bad_lua = round_trip(exporter, out, dev, dev_rev, port, port_rev, overlay,
                                               eui, eui_toc, commits, args.pylib)
    if mismatches:
        result = "ROUND TRIP: %d MISMATCHES" % len(mismatches)
        print(result)
        for rel, why in mismatches:
            print("  %s: %s" % (rel, why))
    else:
        result = "ROUND TRIP: OK (%d files)" % len(produced)
        print(result)
    lua_count = sum(1 for p in produced if p.endswith(".lua"))
    if bad_lua:
        print("LUA 5.1: %d files failed to compile" % len(bad_lua))
        for rel, err in bad_lua:
            print("  %s: %s" % (rel, err))
    else:
        print("LUA 5.1: all %d files compile" % lua_count)

    # 9. The report.
    ctx = {"eui": eui, "eui_head": eui_head, "dev": dev, "port": port, "dev_base": dev_base[:12],
           "port_base": port_base[:12], "dev_branch_note": dev_note, "port_branch_note": port_note,
           "dry_run": args.dry_run, "ported_dir": ported_dir, "baseline_count": len(produced),
           "changed": changed, "new": new, "deleted": deleted, "unchanged": unchanged, "files": files,
           "toc_notes": notes, "round_trip": result, "mismatches": mismatches, "bad_lua": bad_lua,
           "lua_count": lua_count}
    total_lost = write_report(out / "port-report.md", ctx)
    print("report: %s (%d comments lost)" % (out / "port-report.md", total_lost))
    return 1 if (mismatches or bad_lua) else 0


def read_header(path, key):
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        m = re.match(r"##\s*" + re.escape(key) + r"\s*:\s*(.*)$", raw.strip())
        if m:
            return m.group(1).strip()
    raise PortError("%s has no ## %s line" % (path, key))


if __name__ == "__main__":
    sys.exit(main())
