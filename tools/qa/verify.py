"""Evidence-aware gate. Default: build and run core + installed-asset offline checks."""
import argparse
import datetime
import json
import math
import os
from pathlib import Path
import re
import subprocess
import shutil
import sys
from catalog import load_catalog, ordered_checks
from evidence import ROOT, checks, digest, execute, source_identity, is_success, overall_status, EXIT_CODES
from diagnostics import console_summary, status_label

BRIDGE_BINARY = ROOT / "external/dfhack/build/VC2022/plugins/external/df3d-plugin/Release/df3d.plug.dll"
MINGW_BIN_DEFAULT = "C:/msys64/mingw64/bin"
RUN_DIR_FORMAT = "%Y%m%d-%H%M%S-%f"
RUN_DIR_PATTERN = re.compile(r"^\d{8}-\d{6}-\d{6}$")
RUN_DIRS_KEPT = 10

def prune_run_dirs(base, current, keep=RUN_DIRS_KEPT):
    """Drop the oldest auto-named run directories under build/qa beyond the newest `keep`.

    Only directories named by RUN_DIR_FORMAT are candidates: user-named --output
    directories and the build stamps are never touched, nor is the run being written.
    """
    current = Path(current).resolve()
    try:
        runs = sorted(p for p in Path(base).iterdir() if p.is_dir() and RUN_DIR_PATTERN.match(p.name) and p.resolve() != current)
    except OSError:
        return []
    # Names sort chronologically; keep the newest, counting an auto-named current run among them.
    current_counts = current.parent == Path(base).resolve() and bool(RUN_DIR_PATTERN.match(current.name))
    doomed = runs[:max(0, len(runs) - (keep - 1 if current_counts else keep))]
    removed = []
    for path in doomed:
        try:
            shutil.rmtree(path)
            removed.append(path)
        except OSError as exc:
            print(f"could not prune old QA run {path}: {exc}", file=sys.stderr, flush=True)
    return removed

def powershell_executable(path=None):
    # Lane scripts target Windows PowerShell 5.1 (Add-Type console apps); pwsh is the fallback.
    for name in ("powershell", "pwsh"):
        found = shutil.which(name, path=path)
        if found: return found
    return None

def bridge_ready(identity, df_path):
    stamp = ROOT / "build/qa/bridge_build.json"
    installed = Path(df_path) / "hack/plugins/df3d.plug.dll"
    if not stamp.exists() or not BRIDGE_BINARY.is_file() or not installed.is_file(): return False
    prior = json.loads(stamp.read_text())
    return prior.get("source") == identity and prior.get("sha256") == digest(BRIDGE_BINARY) == digest(installed)

def check_environment(spec, env, output=None):
    # No interactive profiling, live-connect or capture flags leak into a check.
    result = {key: value for key, value in env.items()
              if not key.startswith("DF3D_") or key in {"DF3D_DF_PATH", "DF3D_GODOT"}}
    for key, value in spec.get("environment", {}).items():
        result[key] = value.replace("{root}", str(ROOT)).replace("{output}", str(output or ROOT / "build/qa"))
    if spec["kind"] == "ctest":
        # Core asset-locator tests deliberately exercise missing installations.
        result.pop("DF3D_DF_PATH", None)
    return result


def recorded_mature_fixture_ready():
    # The tracked artifact is the deterministic gzip plus manifest; the uncompressed
    # fixture the Godot tests read is expanded (and hash-verified) on demand.
    # An expansion failure reports the fixture absent instead of crashing the gate.
    try:
        import expand_fixtures
        expand_fixtures.expand_all(ROOT, log=lambda *_: None)
    except Exception as error:  # noqa: BLE001 - any failure means "not ready", with the reason
        print("recorded_mature_fixture unavailable:", error, file=sys.stderr, flush=True)
        return False
    return (ROOT / "fixtures/recorded/mature_fort_pause_53.16.df3dfix").is_file()

def optional_readiness(df_path, godot, env, allow_live=False, identity=None):
    # Import in a child of the actual runner interpreter: another Python's lupa
    # installation is not usable evidence for this process.
    def imports(code):
        try:
            return subprocess.run([sys.executable, "-c", code], env=env,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                  timeout=20).returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False
    return dict(python_lupa=imports("from lupa import LuaRuntime; LuaRuntime()"),
                cmake_tool=bool(shutil.which("cmake", path=env.get("PATH"))),
                installed_lua=Path(df_path, "hack/lua53.dll").is_file(),
                df_assets=Path(df_path, "data/vanilla").is_dir(),
                real_renderer=bool(godot and Path(godot).is_file()), protected_live=allow_live,
                bridge_attested=bridge_ready(identity, df_path) if identity else False,
                bridge_configured=(ROOT / "external/dfhack/build/VC2022/CMakeCache.txt").is_file(),
                recorded_mature_fixture=recorded_mature_fixture_ready(),
                synthetic_demo_fixture=(ROOT / "fixtures/synthetic/demo_fort.df3dfix").is_file())

def products(name, binary, env=None):
    paths = {binary}
    if name == "root_build" and binary.exists():
        # The listing needs the gate's PATH (MinGW first). A failing or missing
        # ctest degrades to the binary itself instead of aborting the gate.
        try:
            listing = subprocess.check_output(["ctest", "--test-dir", str(ROOT / "build"), "--show-only=json-v1"],
                                              env=env, timeout=120)
            for test in json.loads(listing)["tests"]:
                command = test.get("command", [])
                if command and Path(command[0]).is_file(): paths.add(Path(command[0]))
        except (OSError, subprocess.SubprocessError, ValueError, KeyError) as exc:
            print(f"{name}: ctest listing unavailable ({exc}); recording build products without it", file=sys.stderr, flush=True)
        paths.update((ROOT / "build/tools").glob("*.exe"))
    return {str(p.resolve()): digest(p) for p in sorted(paths) if p.is_file()}

def command_for(spec, *, godot, df_path, output):
    kind = spec["kind"]
    if kind == "ctest":
        return ["ctest", "--test-dir", str(ROOT / "build"), "--output-on-failure", "--output-junit", str(output / "ctest.xml")]
    if kind == "python":
        return [sys.executable] + [arg.replace("{root}", str(ROOT)).replace("{output}", str(output)) for arg in spec["command"]]
    if kind == "godot":
        # Headless checks use the dummy renderer, where the project's separate
        # render thread races RID creation (intermittent RID errors and
        # segfaults). The GPU lane and the play launcher keep the project setting.
        return [godot] + ([] if spec["lane"] == "gpu" else ["--headless", "--render-thread", "safe"]) + [
            "--path", str(ROOT / "presentations/godot/project"), "--script", spec["script"]]
    if kind == "powershell":
        return [powershell_executable() or "pwsh", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / spec["script"]), "-DfPath", df_path] + spec.get("arguments", [])
    if kind == "native":
        return [str(ROOT / spec["executable"])] + [
            arg.replace("{df_path}", df_path).replace("{root}", str(ROOT)) for arg in spec.get("arguments", [])]
    raise ValueError("Unknown check kind: " + kind)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lane", choices=["offline", "core", "assets", "gpu", "bridge", "live"], default="offline")
    parser.add_argument("--check", action="append", help="Run named manifest checks instead of a whole lane")
    parser.add_argument("--godot", default=os.environ.get("DF3D_GODOT", "C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"))
    parser.add_argument("--df-path", default=os.environ.get("DF3D_DF_PATH", "C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--allow-live", action="store_true", help="Authorize registered protected live lanes; never selected by default")
    parser.add_argument("--reuse-build", action="store_true", help="Require an exact matching prior gate build stamp; never silently use stale binaries")
    parser.add_argument("--check-timeout", type=float, help="Override selected check timeouts in seconds; build timeouts remain unchanged")
    args = parser.parse_args()
    if args.check_timeout is not None and (not math.isfinite(args.check_timeout) or args.check_timeout <= 0):
        parser.error("--check-timeout must be finite and positive")
    catalog_data = load_catalog()
    catalog = catalog_data["checks"]
    lanes = ["core", "assets"] if args.lane == "offline" else [args.lane]
    selected = [c for c in catalog if c["id"] in args.check] if args.check else [c for c in catalog if c["lane"] in lanes]
    if args.check and set(args.check) != {c["id"] for c in selected}:
        unknown = sorted(set(args.check) - {c["id"] for c in selected})
        parser.error("Unknown check ID(s): " + ", ".join(unknown) + "; see tools/qa/checks.json")
    selected = ordered_checks(catalog, {c["id"] for c in selected})
    if args.check_timeout is not None:
        selected = [dict(row, timeout=args.check_timeout) for row in selected]
    if not selected:
        parser.error("No registered checks in this lane")
    output = (args.output or ROOT / "build" / "qa" / datetime.datetime.now().strftime(RUN_DIR_FORMAT)).resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("Output directory must be empty; evidence is never overwritten")
    output.mkdir(parents=True, exist_ok=True)
    prune_run_dirs(ROOT / "build" / "qa", output)
    env = os.environ.copy()
    env["DF3D_DF_PATH"] = args.df_path
    env["DF3D_GODOT"] = args.godot
    # Tests must not inherit live/capture flags from an interactive shell.
    for key in ("DF3D_FIXTURE", "DF3D_SCREENSHOT", "DF3D_DUMP_COMPOSITES"):
        env.pop(key, None)
    compiler = Path(os.environ.get("DF3D_MINGW_BIN") or MINGW_BIN_DEFAULT)
    if compiler.exists(): env["PATH"] = str(compiler) + os.pathsep + env["PATH"]
    identity = source_identity()
    results = []
    readiness = {}
    needed = {p for c in selected for p in c["prerequisites"]}
    builds = {"root_build": (ROOT / "build", ROOT / "build/worldmodel/worldmodel_tests.exe"),
              "extension_build": (ROOT / "build/godot-ext", ROOT / "presentations/godot/project/bin/df3d_godot.dll")}
    # Each build stamp is minted only after an actual dependency-aware build.
    for name, (directory, binary) in builds.items():
        if name not in needed: continue
        stamp = ROOT / "build/qa" / (name + ".json")
        if args.reuse_build:
            try:
                prior = json.loads(stamp.read_text()) if stamp.exists() else {}
            except (OSError, json.JSONDecodeError):
                prior = {}
            readiness[name] = bool(binary.exists() and prior.get("source") == identity and prior.get("products") == products(name, binary, env))
            results.append({"id": name, "status": "passed" if readiness[name] else "incomplete", "reused": True,
                            "reasons": [] if readiness[name] else ["No matching source/binary build evidence"]})
            continue
        if (not shutil.which("cmake", path=env["PATH"]) or
                (name == "root_build" and not shutil.which("ctest", path=env["PATH"])) or
                not (directory / "CMakeCache.txt").exists()):
            readiness[name] = False
            results.append({"id": name, "status": "incomplete", "reasons": ["CMake/CTest and a configured pinned build are required; see README.md"]})
            continue
        # CMake success is the build contract; append our marker only after it returns 0.
        command = [sys.executable, str(Path(__file__).with_name("build_check.py")), str(directory)]
        print(f"{name}: building (log in {output})", flush=True)
        result = execute({"id": name, "completion": "QA_BUILD_PASS", "timeout": 1200}, command, env=env, output_dir=output)
        results.append(result)
        print(console_summary(result), flush=True)
        readiness[name] = is_success(result["status"]) and binary.exists()
        if readiness[name]:
            stamp.parent.mkdir(parents=True, exist_ok=True)
            stamp.write_text(json.dumps({"source": identity, "products": products(name, binary, env)}, indent=2))
        elif is_success(result["status"]):
            result.update(status="incomplete", reasons=["Expected built binary missing"])
    readiness.update(optional_readiness(args.df_path, args.godot, env, args.allow_live, identity))
    for spec in selected:
        absent = [p for p in spec["prerequisites"] if not readiness.get(p, False)]
        if spec["kind"] == "godot" and not Path(args.godot).is_file(): absent.append("Godot executable")
        if spec["kind"] == "native" and not (ROOT / spec["executable"]).is_file(): absent.append("Built native executable")
        if spec["kind"] == "ctest" and not shutil.which("ctest", path=env["PATH"]): absent.append("CTest executable")
        if spec["kind"] == "powershell" and not powershell_executable(env["PATH"]): absent.append("PowerShell executable")
        absent = ["protected_live (pass --allow-live)" if a == "protected_live" else a for a in absent]
        if absent:
            row = {"id": spec["id"], "status": "incomplete", "reasons": ["Missing prerequisites: " + ", ".join(absent)]}
        else:
            command = command_for(spec, godot=args.godot, df_path=args.df_path, output=output)
            row = execute(spec, command, env=check_environment(spec, env, output), output_dir=output)
            if spec["id"] == "bridge_compile" and is_success(row["status"]):
                if not BRIDGE_BINARY.is_file():
                    row.update(status="incomplete", reasons=["Bridge build did not produce expected plugin"])
                else:
                    stamp = ROOT / "build/qa/bridge_build.json"
                    stamp.parent.mkdir(parents=True, exist_ok=True)
                    stamp.write_text(json.dumps({"source": identity, "sha256": digest(BRIDGE_BINARY)}, indent=2))
                    readiness["bridge_attested"] = bridge_ready(identity, args.df_path)
        row["lane"] = spec["lane"]
        readiness[spec["id"]] = is_success(row["status"])
        results.append(row)
        print(console_summary(row), flush=True)
    final_identity = source_identity()
    if final_identity != identity:
        results.append({"id": "stable_source", "status": "incomplete", "reasons": ["Source changed while checks were running; repeat the gate"]})
    binaries = {name: products(name, binary, env) for name, (_, binary) in builds.items() if name in needed and binary.exists()}
    if Path(args.godot).is_file() and any(c["kind"] == "godot" or c["lane"] in ("gpu", "live") for c in selected):
        binaries["godot"] = {args.godot: digest(args.godot)}
    if any(c["lane"] in ("bridge", "live") for c in selected):
        paths = [BRIDGE_BINARY, Path(args.df_path) / "hack/plugins/df3d.plug.dll"]
        binaries["bridge"] = {str(p): digest(p) for p in paths if p.is_file()}
    lua = Path(args.df_path, "hack/lua53.dll")
    if "installed_lua" in needed and lua.is_file(): binaries["lua53"] = {str(lua.resolve()): digest(lua)}
    status = overall_status(results)
    report = {"status": status, "source": identity, "binaries": binaries, "selected": [c["id"] for c in selected],
              "not_selected": [c["id"] for c in catalog if c["id"] not in {row["id"] for row in selected}],
              "excluded_tests": catalog_data["exclusions"], "results": results}
    (output / "summary.json").write_text(json.dumps(report, indent=2))
    print(f"QA {status_label(status)}: {output / 'summary.json'}")
    return EXIT_CODES[status]

if __name__ == "__main__":
    raise SystemExit(main())
