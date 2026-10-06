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
import re
import struct
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
    archive = Path(archive).resolve()
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


def validate_schema(path, expected):
    """Check every snapshot's schema before scheduling engine tests.

    This bounded header check is not a replacement for the consumer's full
    FlatBuffers and semantic validation.
    """
    path = Path(path)
    end = path.stat().st_size
    count = 0
    with path.open("rb") as stream:
        if stream.read(8) != b"DF3DFIX1":
            raise ValueError("invalid fixture magic")
        offset = 8
        while offset < end:
            def read(fmt, position, low, high):
                size = struct.calcsize(fmt)
                if position < low or position + size > high:
                    raise ValueError("truncated or invalid fixture header")
                stream.seek(position)
                return struct.unpack(fmt, stream.read(size))[0]
            length = read("<I", offset, offset, end)
            start, stop = offset + 4, offset + 4 + length
            if stop > end:
                raise ValueError("truncated fixture snapshot")
            table = start + read("<I", start, start, stop)
            vtable = table - read("<i", table, start, stop)
            vsize = read("<H", vtable, start, stop)
            if vsize < 4 or vtable + vsize > stop:
                raise ValueError("invalid fixture vtable")
            field = read("<H", vtable + 4, start, stop) if vsize >= 6 else 0
            version = read("<I", table + field, start, stop) if field else 0
            if version != expected:
                raise ValueError(f"snapshot {count}: schema {version}, expected {expected}; recapture with the current bridge")
            count += 1
            offset = stop
    if not count:
        raise ValueError("fixture contains no snapshots")


def current_schema(root=ROOT):
    source = (Path(root) / "schema/mirror.fbs").read_text(encoding="utf-8")
    match = re.search(r"enum SchemaVersion\s*:\s*uint32\s*\{\s*Current\s*=\s*(\d+)", source)
    if not match:
        raise ValueError("snapshot schema version unavailable")
    return int(match[1])


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
