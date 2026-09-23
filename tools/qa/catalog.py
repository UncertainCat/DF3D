"""QA registration owns executable tests and explicit, reviewable exclusions."""
import json
from pathlib import Path, PurePosixPath
import re

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name("checks.json")
BUILTIN_PREREQUISITES = {
    "root_build", "extension_build", "installed_lua", "df_assets", "real_renderer",
    "protected_live", "bridge_attested", "bridge_configured", "python_lupa", "cmake_tool",
    "recorded_mature_fixture", "synthetic_demo_fixture",
}


def source_path(root, name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name:
        raise ValueError("QA paths must be repository-relative: " + name)
    actual = (root / name).resolve()
    if not actual.is_relative_to(root.resolve()):
        raise ValueError("QA path escapes repository: " + name)
    return actual


def discovered_tests(root):
    return {p.relative_to(root).as_posix() for pattern in (
        "presentations/godot/project/tests/**/*.gd", "tools/**/test_*.py",
    ) for p in root.glob(pattern) if p.is_file()}


def covered_tests(row, root):
    paths = set(row.get("covers", []))
    if row["kind"] == "godot":
        paths.add("presentations/godot/project/" + row["script"].removeprefix("res://"))
    elif row["kind"] == "python":
        command = row["command"]
        if command[:3] == ["-m", "unittest", "discover"]:
            # The inventory uses the exact discovery directory/pattern the runner uses.
            start = command[command.index("-s") + 1]
            pattern = command[command.index("-p") + 1]
            directory = source_path(root, start)
            for path in directory.rglob(pattern):
                # unittest descends into importable packages, not arbitrary
                # nested directories. A skipped file must remain unclassified.
                parents = path.parent.relative_to(directory).parts
                if re.fullmatch(r"[_a-z]\w*\.py", path.name, re.IGNORECASE) and all((directory.joinpath(*parents[:i]) / "__init__.py").is_file()
                       for i in range(1, len(parents) + 1)):
                    paths.add(path.relative_to(root).as_posix())
        elif command and command[0].endswith(".py"):
            paths.add(command[0])
    return paths


def ordered_checks(rows, selected_ids):
    """Dependency closure in execution order; manifest order is only a tie-breaker."""
    by_id = {row["id"]: row for row in rows}
    done, active, result = set(), set(), []
    def visit(name):
        if name in done: return
        if name in active: raise ValueError("Cyclic QA prerequisite: " + name)
        active.add(name)
        for dep in by_id[name]["prerequisites"]:
            if dep in by_id: visit(dep)
        active.remove(name)
        done.add(name)
        result.append(by_id[name])
    for row in rows:
        if row["id"] in selected_ids: visit(row["id"])
    return result


def validate_catalog(data, root=ROOT):
    if data.get("version") != 1:
        raise ValueError("Unsupported QA manifest version")
    rows = data["checks"]
    ids = [row["id"] for row in rows]
    if len(set(ids)) != len(ids) or any(not re.fullmatch(r"[a-z0-9_]+", name) for name in ids):
        raise ValueError("Invalid or duplicate QA check IDs")
    required = {"id", "lane", "kind", "completion", "prerequisites"}
    coverage = set()
    for row in rows:
        name, kind = row["id"], row.get("kind")
        if not required <= row.keys() or row["lane"] not in data["lanes"] or kind not in {"ctest", "python", "godot", "powershell", "native"}:
            raise ValueError("Invalid QA check definition: " + name)
        deps = row["prerequisites"]
        if not isinstance(deps, list) or any(not isinstance(p, str) or p not in set(ids) | BUILTIN_PREREQUISITES for p in deps):
            raise ValueError("Unknown QA prerequisite: " + name)
        if "observations" in row and (type(row["observations"]) is not int or row["observations"] < 1):
            raise ValueError("Invalid QA observation count: " + name)
        if not isinstance(row["completion"], str) or not row["completion"]:
            raise ValueError("Missing QA completion marker: " + name)
        re.compile(row["completion"])
        env = row.get("environment", {})
        if not isinstance(env, dict) or any(not re.fullmatch(r"DF3D_[A-Z0-9_]+", key) or not isinstance(value, str) for key, value in env.items()):
            raise ValueError("Invalid QA environment: " + name)
        if row["lane"] == "live" and "protected_live" not in deps:
            raise ValueError("Live QA check requires protected_live: " + name)
        if kind == "godot":
            if not row.get("script", "").startswith("res://tests/"):
                raise ValueError("Godot QA entrypoint must be in res://tests: " + name)
            if "extension_build" not in deps:
                raise ValueError("Godot QA check requires current extension build: " + name)
            if row["lane"] == "gpu" and "real_renderer" not in deps:
                raise ValueError("GPU QA check requires real_renderer: " + name)
        if kind == "python":
            command = row.get("command")
            if not isinstance(command, list) or not command or not all(isinstance(p, str) for p in command):
                raise ValueError("Invalid Python command: " + name)
            if command[:3] == ["-m", "unittest", "discover"]:
                if "-s" not in command or "-p" not in command:
                    raise ValueError("Python discovery requires explicit directory and pattern: " + name)
            elif not command[0].endswith(".py"):
                raise ValueError("Python QA command requires script or explicit unittest discovery: " + name)
        paths = covered_tests(row, root)
        if kind == "powershell": paths.add(row["script"])
        if kind == "native": source_path(root, row["executable"])
        for path in paths:
            if not source_path(root, path).is_file():
                raise ValueError("Missing QA source: " + path)
        coverage.update(paths)
    ordered_checks(rows, ids)  # Validate cycles even in unselected lanes.
    exclusions = data.get("exclusions", [])
    excluded = set()
    for row in exclusions:
        path = row["path"]
        if path in excluded or path in coverage:
            raise ValueError("Duplicate or actively covered QA exclusion: " + path)
        if row.get("status") not in {"manual", "retired", "helper"} or not isinstance(row.get("reason"), str) or not row["reason"].strip():
            raise ValueError("QA exclusion requires explicit status and reason: " + path)
        if row["status"] == "retired" and row.get("replacement") not in ids:
            raise ValueError("Retired QA entrypoint requires registered replacement: " + path)
        excluded.add(path)
    discovered = discovered_tests(root)
    if excluded - discovered:
        raise ValueError("Stale QA exclusions: " + ", ".join(sorted(excluded - discovered)))
    if discovered - coverage - excluded:
        raise ValueError("Unclassified QA tests: " + ", ".join(sorted(discovered - coverage - excluded)))
    return rows


def load_catalog(manifest=MANIFEST, root=ROOT):
    data = json.loads(Path(manifest).read_text(encoding="utf-8"))
    validate_catalog(data, root)
    return data
