"""Validate checksums, Windows PE imports and release payload boundaries."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[2]


def audit_resources(root: Path) -> dict:
    """Inspect the export directory as well as resources hidden inside Godot's PCK."""
    prohibited = {"save", "saves", "installed_mods", "vanilla", "asset-cache", ".git"}
    media = {".png", ".jpg", ".jpeg", ".bmp", ".webp", ".ctex", ".ogg", ".wav", ".mp3", ".ttf", ".otf"}
    upstream_art = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(root)
        if prohibited.intersection(s.lower() for s in rel.parts) or path.name.lower() in {"dwarf fortress.exe", "steam_api64.dll", "steam_appid.txt"} or path.suffix.lower() == ".df3dfix":
            raise ValueError(f"Prohibited game/user payload: {rel}")
        if path.suffix.lower() in media:
            if rel.parent.as_posix() != "bridge/hack/data/art":
                raise ValueError(f"Unexpected media in payload: {rel}")
            original = ROOT / "external/dfhack/data/art" / path.name
            if not original.is_file() or path.read_bytes() != original.read_bytes():
                raise ValueError(f"Artwork is not unchanged upstream DFHack content: {rel}")
            upstream_art.append(rel.as_posix())
    data = (root / "viewer/DF3D.pck").read_bytes()
    magic, version = struct.unpack_from("<II", data)
    if magic != 0x43504447 or version != 4:
        raise ValueError("Review resource audit for this Godot PCK format")
    base, directory = struct.unpack_from("<QQ", data, 24)
    count = struct.unpack_from("<I", data, directory)[0]
    at = directory + 4
    names = []
    allowed = {".bin", ".binary", ".cfg", ".gdc", ".gdextension", ".gdshader", ".gdshaderinc", ".json", ".remap", ".scn"}
    for _ in range(count):
        length = struct.unpack_from("<I", data, at)[0]; at += 4
        name = data[at:at + length].rstrip(b"\0").decode("utf-8"); at += length
        offset, size = struct.unpack_from("<QQ", data, at); at += 16
        checksum = data[at:at + 16]; at += 16
        flags = struct.unpack_from("<I", data, at)[0]; at += 4
        resource = data[base + offset:base + offset + size]
        if flags or len(resource) != size or hashlib.md5(resource).digest() != checksum:
            raise ValueError(f"Invalid/encrypted packed resource: {name}")
        if Path(name).suffix.lower() not in allowed or prohibited.intersection(Path(name).parts) or name.startswith("tests/"):
            raise ValueError(f"Unexpected packed resource: {name}")
        if Path(name).suffix == ".bin" and name != ".godot/uid_cache.bin":
            raise ValueError(f"Unexpected binary cache: {name}")
        names.append(name)
    return {"pck_resources": len(names), "pck_resource_names": names,
            "upstream_dfhack_artwork": upstream_art, "asset_policy": "pass"}


def imports(path: Path) -> list[str]:
    data = path.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3c)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError(f"Not a PE file: {path}")
    sections = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    optional = pe + 24
    directory = optional + (112 if struct.unpack_from("<H", data, optional)[0] == 0x20b else 96)
    import_rva = struct.unpack_from("<I", data, directory + 8)[0]
    table = optional + optional_size

    def offset(rva: int) -> int:
        for i in range(sections):
            virtual_size, address, raw_size, raw_offset = struct.unpack_from("<IIII", data, table + i * 40 + 8)
            if address <= rva < address + max(virtual_size, raw_size):
                return raw_offset + rva - address
        raise ValueError(f"Unmapped RVA in {path}: {rva}")

    if not import_rva:
        return []
    at = offset(import_rva)
    result = []
    while any(data[at:at + 20]):
        name_at = offset(struct.unpack_from("<I", data, at + 12)[0])
        result.append(data[name_at:data.index(0, name_at)].decode("ascii").lower())
        at += 20
    return result


def audit(root: Path) -> dict:
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    names = {f["path"] for f in manifest["files"]}
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()} - {"manifest.json"}
    if names != actual:
        raise ValueError(f"Manifest mismatch: missing={names-actual}, extra={actual-names}")
    for f in manifest["files"]:
        path = root / f["path"]
        if path.stat().st_size != f["size"] or hashlib.sha256(path.read_bytes()).hexdigest() != f["sha256"]:
            raise ValueError(f"Hash mismatch: {f['path']}")
    checked = 0
    system = Path(os.environ["WINDIR"]) / "System32"
    for path in root.rglob("*"):
        if path.suffix.lower() not in (".dll", ".exe"):
            continue
        checked += 1
        # DFHack explicitly loads its libraries from hack/; the host executable
        # loads app-local CRT from the DF root. Godot export siblings are direct.
        local_dirs = [path.parent]
        if "bridge" in path.relative_to(root).parts:
            local_dirs += [root / "bridge", root / "bridge/hack"]
        local_names = {p.name.lower() for d in local_dirs for p in d.glob("*.dll")}
        for name in imports(path):
            if name in local_names:
                continue
            if name.startswith(("msvcp", "vcruntime", "libstdc++", "libgcc", "libwinpthread")):
                raise ValueError(f"Unbundled compiler runtime: {path.name} imports {name}")
            if name.startswith(("api-ms-win-", "ext-ms-win-")) or (system / name).is_file():
                continue
            raise ValueError(f"Unresolved import: {path.name} imports {name}")
    return {"files": len(names), "binaries": checked, "bytes": sum(f["size"] for f in manifest["files"]),
            "checksums": "pass", "imports": "pass", **audit_resources(root)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    print(json.dumps(audit(parser.parse_args().directory), indent=2))
