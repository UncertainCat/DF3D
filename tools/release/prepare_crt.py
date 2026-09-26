"""Extract a pinned Microsoft VC++ redist without installing it on the machine."""
from __future__ import annotations
import ctypes
import hashlib
from pathlib import Path
import shutil
import struct
import subprocess
import urllib.request
import xml.etree.ElementTree as ET

VERSION = (14, 51, 36247, 0)
URL = "https://aka.ms/vc14/vc_redist.x64.exe"
SHA256 = "843068991daaa1f73ad9f6239bce4d0f6a07a51f18c37ea2a867e9beca71295c"


def file_version(path: Path) -> tuple[int, int, int, int]:
    api = ctypes.windll.version
    size = api.GetFileVersionInfoSizeW(str(path), None)
    if not size:
        raise ValueError(f"Missing file version: {path}")
    data = ctypes.create_string_buffer(size)
    if not api.GetFileVersionInfoW(str(path), 0, size, data):
        raise ValueError(f"Cannot read file version: {path}")
    value, length = ctypes.c_void_p(), ctypes.c_uint()
    if not api.VerQueryValueW(data, "\\", ctypes.byref(value), ctypes.byref(length)):
        raise ValueError(f"Invalid version resource: {path}")
    fixed = ctypes.cast(value, ctypes.POINTER(ctypes.c_uint32))
    return fixed[2] >> 16, fixed[2] & 65535, fixed[3] >> 16, fixed[3] & 65535


def prepare(directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / "vc_redist.x64.exe"
    if not archive.exists():
        urllib.request.urlretrieve(URL, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise ValueError("VC redist hash mismatch. Review the new Microsoft release before updating its pin.")
    if file_version(archive) != VERSION:
        raise ValueError("VC redist version mismatch")
    # Burn embeds a bootstrap CAB and a payload CAB. Unpack as data; never run
    # the installer, msiexec, or an administrative install action.
    data = archive.read_bytes()
    cabinets = []
    at = 0
    while True:
        at = data.find(b"MSCF", at)
        if at < 0:
            break
        size = struct.unpack_from("<I", data, at + 8)[0]
        if size >= 36 and at + size <= len(data):
            cab = directory / f"container-{len(cabinets)}.cab"
            cab.write_bytes(data[at:at + size])
            dest = directory / f"container-{len(cabinets)}"
            dest.mkdir(exist_ok=True)
            subprocess.run(["expand.exe", "-F:*", str(cab), str(dest)], check=True, stdout=subprocess.DEVNULL)
            cabinets.append(dest)
            at += size
        else:
            at += 4
    if len(cabinets) != 2:
        raise ValueError("Unexpected redist container layout")
    manifest = ET.parse(cabinets[0] / "0").getroot()
    payload = next(x for x in manifest if x.tag.endswith("Payload")
                   and x.get("FilePath", "").lower().endswith("vcruntimeminimum_amd64\\cab1.cab"))
    unpacked = directory / "minimum-x64"
    unpacked.mkdir(exist_ok=True)
    subprocess.run(["expand.exe", "-F:*", str(cabinets[1] / payload.attrib["SourcePath"]), str(unpacked)],
                   check=True, stdout=subprocess.DEVNULL)
    target = directory / "crt-14.51.36247"
    target.mkdir(exist_ok=True)
    for source in unpacked.glob("*.dll_amd64"):
        shutil.copy2(source, target / source.name.removesuffix("_amd64"))
    if file_version(target / "msvcp140.dll") != VERSION:
        raise ValueError("Extracted CRT version mismatch")
    return target


if __name__ == "__main__":
    print(prepare(Path(__file__).resolve().parents[2] / "build/release-deps"))
