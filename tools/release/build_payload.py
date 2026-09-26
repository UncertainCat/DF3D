"""Stage and bundle the Windows preview from build outputs, never a DF install.

Developer requirements: Python 3, CMake, built fork/extension/audio_guard,
Godot matching PINS.md with export templates, VS redistributable CRT, MinGW strip.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import zipfile
from audit_payload import audit
from prepare_crt import prepare, file_version, VERSION as CRT_MINIMUM

ROOT = Path(__file__).resolve().parents[2]

def discover_godot() -> Path:
    module = str(ROOT / "tools/SteamPaths.psm1").replace("'", "''")
    value = subprocess.check_output(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
        "$ErrorActionPreference='Stop'; Import-Module '" + module + "'; Resolve-Df3dGodotExe"], text=True).strip()
    return Path(value)


def redist_notice() -> Path:
    vswhere = Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Microsoft Visual Studio/Installer/vswhere.exe"
    installations = json.loads(subprocess.check_output([str(vswhere), "-products", "*", "-format", "json"], text=True))
    for installation in installations:
        path = Path(installation["installationPath"]) / "Licenses/1033/Redist.txt"
        if path.is_file():
            return path
    raise FileNotFoundError("Visual Studio redistribution notice missing; supply --vs-redist-notice")


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def run(args: list[str], log: Path) -> None:
    with log.open("w", encoding="utf-8") as f:
        p = subprocess.run(args, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT)
    if p.returncode:
        raise RuntimeError(f"Command failed ({p.returncode}), see {log}")


def copy(source: Path, target: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def reset_child(path: Path, parent: Path) -> None:
    # Only remove an explicitly named staging child inside the release build dir.
    if path.resolve().parent != parent.resolve() or path.is_symlink():
        raise ValueError(f"Unsafe staging path: {path}")
    if path.exists():
        shutil.rmtree(path)
    path.mkdir()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    app_version = re.search(r'^config/version="([^"]+)"', (ROOT / "presentations/godot/project/project.godot").read_text(), re.M).group(1)
    ap.add_argument("--version", default=app_version)
    ap.add_argument("--output", type=Path, default=ROOT / ("build/release-" + app_version))
    ap.add_argument("--godot", type=Path, help="Godot editor; defaults to DF3D_GODOT or Steam discovery")
    ap.add_argument("--vs-redist-notice", type=Path, help="Visual Studio Redist.txt; defaults to vswhere discovery")
    ap.add_argument("--crt", type=Path, help="Override the pinned Microsoft CRT (must meet the supported host minimum)")
    ap.add_argument("--strip", type=Path, default=Path(os.environ.get("DF3D_MINGW_BIN", "C:/msys64/mingw64/bin")) / "strip.exe")
    ap.add_argument("--payload-only", action="store_true", help="Do not compile the outer launcher")
    args = ap.parse_args()
    args.godot = args.godot or discover_godot()
    args.vs_redist_notice = args.vs_redist_notice or redist_notice()
    if args.version != app_version or not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?", args.version):
        raise ValueError("Release version must be SemVer and match project.godot config/version")
    if args.crt is None:
        args.crt = prepare(ROOT / "build/release-deps")
    # These DLLs load into DF itself, not just our older-toolchain bridge. A
    # runtime matching only the bridge compiler can crash the newer DF host.
    for name in ("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"):
        if file_version(args.crt / name) < CRT_MINIMUM:
            raise ValueError(f"{name} must be >= {CRT_MINIMUM}; older CRTs crash the supported DF host")
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    stage = out / "payload"
    reset_child(stage, out)
    viewer = stage / "viewer"
    viewer.mkdir()
    run([str(args.godot), "--headless", "--path", str(ROOT / "presentations/godot/project"),
         "--export-release", "Windows Preview", str(viewer / "DF3D.exe")], out / "export.log")
    for name in ("DF3D.exe", "DF3D.pck", "df3d_godot.dll"):
        if not (viewer / name).is_file():
            raise RuntimeError(f"Export missing {name}; see export.log")
    run([str(args.strip), "--strip-debug", str(viewer / "df3d_godot.dll")], out / "strip.log")
    bridge = stage / "bridge"
    run(["cmake", "--install", str(ROOT / "external/dfhack/build/VC2022"), "--config", "Release",
         "--prefix", str(bridge)], out / "dfhack-install.log")
    for name in ("dfhooks.dll", "dfhooks_dfhack.ini", "hack/dfhack.dll", "hack/dfhack-run.exe",
                 "hack/plugins/df3d.plug.dll", "hack/symbols.xml"):
        if not (bridge / name).is_file():
            raise RuntimeError(f"DFHack install missing {name}")
    # App-local deployment: no administrator or machine-wide runtime installer.
    for name in ("msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll", "msvcp140_atomic_wait.dll",
                 "msvcp140_codecvt_ids.dll", "vcruntime140.dll", "vcruntime140_1.dll", "vcruntime140_threads.dll", "concrt140.dll"):
        copy(args.crt / name, bridge / name)
        copy(args.crt / name, bridge / "hack" / name)
    copy(ROOT / "build/tools/audio_guard.exe", stage / "helpers/audio_guard.exe")
    notices = stage / "notices"
    for source, name in (
        (ROOT / "LICENSE", "DF3D-LICENSE.txt"),
        (args.godot.parent / "LICENSE.txt", "Godot-LICENSE.txt"),
        (args.godot.parent / "COPYRIGHT.txt", "Godot-COPYRIGHT.txt"),
        (ROOT / "external/godot-cpp/LICENSE.md", "godot-cpp-LICENSE.md"),
        (ROOT / "external/dfhack/LICENSE.rst", "DFHack-LICENSE.rst"),
        (ROOT / "external/dfhack/depends/dfhooks/LICENSE", "dfhooks-LICENSE.txt"),
        (ROOT / "third_party/flatbuffers/LICENSE", "FlatBuffers-LICENSE.txt"),
        (args.vs_redist_notice, "Microsoft-Redist.txt"),
    ):
        copy(source, notices / name)
    # The extension/helper link the MinGW C++ runtime statically. Include its
    # exception and notices even though no compiler DLL is shipped.
    compiler_licenses = args.strip.parent.parent / "share/licenses"
    for component in ("gcc-libs", "crt", "libwinpthread"):
        directory = compiler_licenses / component
        if not directory.is_dir():
            raise FileNotFoundError(directory)
        for source in directory.iterdir():
            if source.is_file():
                copy(source, notices / "MinGW" / component / source.name)
    copy(ROOT / "tools/release/PREVIEW.txt", stage / "README.txt")
    for name in ("ENGINEERING.md", "PINS.md"):
        copy(ROOT / name, stage / name)
    revisions = {}
    for label, directory in (("df3d", ROOT), ("dfhack", ROOT / "external/dfhack"),
                             ("godotCpp", ROOT / "external/godot-cpp")):
        revisions[label] = subprocess.check_output(["git", "-C", str(directory), "rev-parse", "HEAD"], text=True).strip()
        revisions[label + "Dirty"] = bool(subprocess.check_output(["git", "-C", str(directory), "status", "--porcelain"], text=True).strip())
    # Preserve exact input identity even when preparing an uncommitted release candidate.
    source_names = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT).decode().split("\0")
    source_files = [{"path": name, "sha256": digest(ROOT / name)} for name in sorted(set(source_names)) if name and (ROOT / name).is_file()]
    source_bytes = (json.dumps(source_files, indent=2) + "\n").encode()
    (out / "source-inputs.json").write_bytes(source_bytes)
    revisions["sourceInputsSha256"] = hashlib.sha256(source_bytes).hexdigest()
    files = [{"path": p.relative_to(stage).as_posix(), "sha256": digest(p), "size": p.stat().st_size}
             for p in sorted(stage.rglob("*")) if p.is_file()]
    # Reject known accidental game assets and user data in the staging tree.
    for entry in files:
        parts = entry["path"].lower().split("/")
        if any(s in parts for s in ("save", "saves", ".git", ".godot", "installed_mods")) or parts[-1] == "dwarf fortress.exe":
            raise RuntimeError(f"Prohibited payload path: {entry['path']}")
    content_id = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()[:16]
    manifest = {"formatVersion": 1, "version": args.version, "contentId": content_id,
                "dwarfFortress": {"version": "53.16", "steamBuildId": "24557528", "peTimestamp": 0x6A70A6D9},
                "viewerExecutable": "viewer/DF3D.exe", "bridgeRoot": "bridge", "files": files,
                "buildRevisions": revisions}
    (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (out / "payload-audit.json").write_text(json.dumps(audit(stage), indent=2) + "\n", encoding="utf-8")
    archive = out / "payload.zip"
    # Stable ZIP timestamps/order make identical inputs produce identical archives.
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for path in sorted(stage.rglob("*")):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(stage).as_posix(), (2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, path.read_bytes())
    if not args.payload_only:
        csc = Path(os.environ["WINDIR"]) / "Microsoft.NET/Framework64/v4.0.30319/csc.exe"
        exe = out / ("DF3D-" + args.version + "-windows-x64.exe")
        run([str(csc), "/nologo", "/target:winexe", "/platform:x64", "/optimize+", f"/out:{exe}",
             "/reference:System.Windows.Forms.dll", "/reference:System.Drawing.dll", "/reference:System.Web.Extensions.dll",
             "/reference:System.IO.Compression.dll", "/reference:System.IO.Compression.FileSystem.dll",
             f"/resource:{archive},DF3D.Payload.zip", str(ROOT / "tools/release/Launcher.cs")], out / "launcher-build.log")
        (out / "SHA256SUMS.txt").write_text(f"{digest(exe)}  {exe.name}\n", encoding="ascii")
    print(json.dumps({"version": manifest["version"], "files": len(files), "payloadBytes": archive.stat().st_size,
                      "output": str(out)}, indent=2))


if __name__ == "__main__":
    main()
