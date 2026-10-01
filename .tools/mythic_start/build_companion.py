"""Build an independently installed Ready/Pull addon from the canonical module.

This helper is not loaded by WoW. It never changes the installed EllesmereUI.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import zipfile

HERE = Path(__file__).resolve().parent
DEFAULT_ROOT = HERE.parent.parent
ADDON_NAME = "EllesmereUI_MythicStart"
MODULE_NAME = "EllesmereUIQoL_MythicStart.lua"
BOOTSTRAP_NAME = "companion_bootstrap.lua"
TOC = """## Interface: 120000,120001,120005,120007,120100,16001
## Title: EllesmereUI Ready/Pull Companion
## Notes: Independent READY/PULL controls; settings: /euipull
## Author: SrMths
## Version: 1.0.0
## Dependencies: EllesmereUI, EllesmereUIQoL
## SavedVariables: EllesmereUIMythicStartDB

companion_bootstrap.lua
EllesmereUIQoL_MythicStart.lua
"""


def build(root: Path, output_dir: Path, archive: Path | None = None) -> Path:
    root = root.resolve()
    output_dir = output_dir.resolve()
    module = root / "EllesmereUIQoL" / MODULE_NAME
    bootstrap = root / ".tools" / "mythic_start" / BOOTSTRAP_NAME
    sources = {MODULE_NAME: module.read_bytes(), BOOTSTRAP_NAME: bootstrap.read_bytes()}
    for name, data in sources.items():
        if data.startswith(b"\xef\xbb\xbf") or b"\r" in data:
            raise ValueError(f"{name} must use UTF-8 without BOM and LF line endings")
        data.decode("utf-8")
    package = output_dir / ADDON_NAME
    # Output may live beneath the repository, but never inside a source addon.
    if package.is_relative_to(root / "EllesmereUIQoL"):
        raise ValueError("Output directory must not modify the source addon")
    package.mkdir(parents=True, exist_ok=True)
    files = {f"{ADDON_NAME}.toc": TOC.encode("utf-8"), **sources}
    for name, data in files.items():
        target = package / name
        target.write_bytes(data)
        if hashlib.sha256(target.read_bytes()).digest() != hashlib.sha256(data).digest():
            raise OSError(f"Package verification failed: {name}")
    if archive is not None:
        archive = archive.resolve()
        archive.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
            for name in sorted(files):
                # Fixed metadata makes the generated archive reproducible.
                entry = zipfile.ZipInfo(f"{ADDON_NAME}/{name}", (2026, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o644 << 16
                bundle.writestr(entry, files[name])
    return package


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT, help="Repository root")
    parser.add_argument("--output-dir", type=Path, required=True, help="Parent of generated addon folder")
    parser.add_argument("--zip", type=Path, help="Optional generated addon ZIP path")
    args = parser.parse_args()
    package = build(args.root, args.output_dir, args.zip)
    print(f"Built {package}")
    print(f"Canonical runtime SHA256: {hashlib.sha256((package / MODULE_NAME).read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
