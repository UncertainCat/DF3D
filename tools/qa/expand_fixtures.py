"""Expand tracked, deterministically gzipped recorded fixtures next to their manifests.

Only ``fixtures/recorded/<name>.df3dfix.gz`` files with a sibling
``<name>.manifest.json`` are handled. The QA gate runs this automatically; run it
by hand before launching a fixture-driven Godot test outside the gate.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
RECORDED = "fixtures/recorded"


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def compress(source, target):
    with Path(source).open("rb") as inp, Path(target).open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as out:
            shutil.copyfileobj(inp, out)


def manifest_for(archive):
    name = archive.name.removesuffix(".df3dfix.gz")
    return archive.with_name(name + ".manifest.json")


def tracked_archives(root):
    archives = sorted((Path(root) / RECORDED).glob("*.df3dfix.gz"))
    return [a for a in archives if manifest_for(a).is_file()]


def expand_one(archive, log=print):
    manifest = json.loads(manifest_for(archive).read_text(encoding="utf-8"))
    expected = manifest["files"][archive.name]
    target = archive.with_name(archive.name.removesuffix(".gz"))
    if target.is_file() and target.stat().st_size == expected["uncompressed_bytes"] and digest(target) == expected["uncompressed_sha256"]:
        log(f"FIXTURE_CURRENT {target.relative_to(ROOT).as_posix()}")
        return target
    if digest(archive) != expected["sha256"]:
        raise ValueError(f"compressed fixture hash mismatch: {archive.relative_to(ROOT).as_posix()}")
    partial = target.with_name(target.name + ".partial")
    with gzip.open(archive, "rb") as inp, partial.open("wb") as out:
        shutil.copyfileobj(inp, out)
    if partial.stat().st_size != expected["uncompressed_bytes"] or digest(partial) != expected["uncompressed_sha256"]:
        partial.unlink(missing_ok=True)
        raise ValueError(f"expanded fixture hash mismatch: {target.relative_to(ROOT).as_posix()}")
    partial.replace(target)
    log(f"FIXTURE_EXPANDED {target.relative_to(ROOT).as_posix()} bytes={expected['uncompressed_bytes']}")
    return target


def expand_all(root=ROOT, archives=None, log=print):
    """Expand every manifest-backed archive (or the explicit list); return uncompressed paths."""
    return [expand_one(Path(a), log) for a in (archives if archives is not None else tracked_archives(root))]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archives", nargs="*", type=Path, help="Explicit .df3dfix.gz archives; default: every manifest-backed archive")
    args = parser.parse_args(argv)
    try:
        paths = expand_all(ROOT, args.archives or None)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print("FIXTURE_EXPAND_FAIL", error)
        return 1
    print(f"QA_FIXTURE_EXPAND_PASS count={len(paths)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
