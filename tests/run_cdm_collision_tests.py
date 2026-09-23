"""Run mocked CDM regressions against the production picker and routing code.

Requires npx (Fengari); run from any directory with Python 3.
The routing section is extracted verbatim to avoid booting the WoW frame UI.
"""

from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    hooks = (root / "EllesmereUICooldownManager/EllesmereUICdmHooks.lua").read_text(encoding="utf-8")
    start = hooks.index("local _cdidRouteMap = {}")
    end_marker = "ns._cdidRouteMap = _cdidRouteMap"
    end = hooks.index(end_marker, start) + len(end_marker)
    main_source = (root / "EllesmereUICooldownManager/EllesmereUICooldownManager.lua").read_text(encoding="utf-8")
    repop_start = main_source.index("function ns.RepopulateFromBlizzard()")
    repop_end = main_source.index("\nend\n", repop_start) + len("\nend\n")
    npx = shutil.which("npx.cmd") or shutil.which("npx")
    if not npx:
        raise SystemExit("npx is required for the Fengari Lua harness")
    with tempfile.TemporaryDirectory(prefix="eui-cdm-test-") as folder:
        route = Path(folder) / "routing.lua"
        route.write_text(
            "local _, ns = ...\nlocal ECME = ns.ECME\n"
            "local GHOST_CD_BAR_KEY = '__ghost_cd'\n"
            "local MAIN_BAR_KEYS = { cooldowns = true, utility = true, buffs = true }\n"
            "local SaveCurrentSpecProfile = function() end\n"
            + hooks[start:end] + "\n" + main_source[repop_start:repop_end], encoding="utf-8")
        result = subprocess.run(
            [npx, "--yes", "--package=fengari-node-cli", "fengari",
             "tests/cdm_collision_claims.lua", str(route)],
            cwd=root, check=True, capture_output=True, text=True,
        )
        print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="")
        # Some Fengari errors do not set a nonzero process exit code.
        if "cdm collision claim harness: PASS" not in result.stdout:
            raise SystemExit("CDM harness did not reach its final assertion")


if __name__ == "__main__":
    main()
