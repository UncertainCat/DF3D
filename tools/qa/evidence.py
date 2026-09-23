"""Completion checks, accepted known-issue status, and retained QA evidence."""
import hashlib
import os
import signal
import json
import re
import subprocess
import time
from pathlib import Path
from diagnostics import error_summary

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name("checks.json")
CODE_SUFFIXES = {".cpp", ".h", ".hpp", ".c", ".fbs", ".gd", ".gdshader",
                 ".gdshaderinc", ".tscn", ".json", ".cfg", ".py", ".ps1",
                 ".psm1", ".lua", ".cmake", ".cs", ".cmd", ".bat", ".df3dfix",
                 ".xml", ".pl", ".rb", ".in", ".inc", ".sh", ".godot", ".gdextension"}

def checks():
    from catalog import load_catalog
    return load_catalog(MANIFEST, ROOT)["checks"]


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def tree_identity(root):
    # Include uncommitted/untracked source, never generated build trees or assets.
    paths = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root
    ).decode("utf-8").split("\0")
    combined = hashlib.sha256()
    count = 0
    for name in sorted(set(paths)):
        path = root / name
        if not path.is_file() or not (path.suffix in CODE_SUFFIXES or path.name == "CMakeLists.txt"):
            continue
        combined.update(name.encode("utf-8") + b"\0" + bytes.fromhex(digest(path)))
        count += 1
    submodules = {}
    entries = subprocess.check_output(["git", "ls-files", "--stage", "-z"], cwd=root).decode().split("\0")
    for entry in entries:
        if entry.startswith("160000 "):
            name = entry.split("\t", 1)[1]
            path = root / name
            submodules[name] = tree_identity(path) if (path / ".git").exists() else {"available": False}
    return {"code_sha256": combined.hexdigest(), "source_files": count, "submodules": submodules}

def source_identity():
    identity = tree_identity(ROOT)
    external = {}
    for name in ("dfhack", "godot-cpp"):
        path = ROOT / "external" / name
        if not path.exists():
            external[name] = {"available": False}
            continue
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=path).decode().strip()
        external[name] = {"head": head, **tree_identity(path)}
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip()
    return {"head": head, **identity, "external": external}

def evaluate(spec, code, output):
    reasons = []
    if code != 0:
        reasons.append(f"exit={code}")
    if code != 77 and re.search(r"^QA_INCOMPLETE:", output, re.MULTILINE):
        reasons.append("incomplete marker requires exit 77")
    if not re.search(spec["completion"], output, re.MULTILINE):
        reasons.append("expected completion marker missing")
    # Only exact pinned-engine signatures are accepted. Assertion failures and
    # unfamiliar callsites remain failures, even alongside accepted diagnostics.
    reasons.extend(row["message"] for row in error_summary(output)["unclassified"][:5])
    expected = spec.get("observations")
    if expected is not None:
        observations = []
        for line in output.splitlines():
            if line.startswith("QA_PROBE "):
                try:
                    observations.append(json.loads(line[len("QA_PROBE "):]))
                except json.JSONDecodeError:
                    reasons.append("malformed probe observation")
        valid_rows = [o for o in observations if isinstance(o, dict)
                      and isinstance(o.get("case"), str) and o["case"]]
        if len(valid_rows) != len(observations):
            reasons.append("probe observation must be an object with a named case")
        if len(observations) != expected or len({o["case"] for o in valid_rows}) != expected:
            reasons.append("probe case count/identity mismatch")
        if any(o.get("bug") is not False for o in valid_rows):
            reasons.append("probe reports a defect or omits its result")
    return reasons

def engine_errors(output):
    return re.findall(r"^[ \t]*(?:SCRIPT ERROR:|ERROR:|FAIL(?:\b|:)).*$", output, re.MULTILINE)


def classify(spec, code, text):
    diagnostics = error_summary(text)
    if code == 77 and re.search(r"^QA_INCOMPLETE:", text, re.MULTILINE) and not diagnostics["unclassified"]:
        return "incomplete", [line for line in text.splitlines() if line.startswith("QA_INCOMPLETE:")]
    reasons = evaluate(spec, code, text)
    if reasons:
        return "failed", reasons
    return ("passed_with_known_issues" if diagnostics["known_engine"] else "passed"), []


SUCCESS_STATUSES = {"passed", "passed_with_known_issues"}
EXIT_CODES = {"passed": 0, "passed_with_known_issues": 0, "failed": 1, "incomplete": 2}


def is_success(status):
    return status in SUCCESS_STATUSES


def overall_status(results):
    statuses = {row["status"] for row in results}
    if "failed" in statuses:
        return "failed"
    if not statuses or statuses - SUCCESS_STATUSES:
        return "incomplete"
    return "passed_with_known_issues" if "passed_with_known_issues" in statuses else "passed"


def execute(spec, command, *, env, output_dir):
    log = Path(output_dir) / (spec["id"] + ".log")
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    try:
        with log.open("wb") as stream:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=stream,
                stderr=subprocess.STDOUT, start_new_session=os.name != "nt",
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            try:
                code = process.wait(timeout=spec.get("timeout", 60))
            except subprocess.TimeoutExpired:
                # Stop only the process tree launched for this check. A timed-out
                # build must not leave compilers writing the next check's binaries.
                if os.name == "nt":
                    killer = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32/taskkill.exe"
                    subprocess.run([str(killer), "/PID", str(process.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)
                code = "timeout"
    except OSError as exc:
        return {"id": spec["id"], "status": "incomplete", "reasons": [str(exc)], "log": str(log)}
    text = log.read_text(encoding="utf-8", errors="replace")
    status, reasons = classify(spec, code, text)
    return {"id": spec["id"], "status": status, "exit": code, "reasons": reasons,
            "diagnostics": error_summary(text),
            "command": [str(part) for part in command], "duration_seconds": round(time.monotonic()-started, 3),
            "log": str(log)}
