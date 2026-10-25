"""Build siege replay inputs and pixel expectations from the native reference."""
from pathlib import Path
import gzip
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
source = json.loads(gzip.decompress((root / "fixtures/construction/siege_rendering.json.gz").read_bytes()))
materials = ["INORGANIC:GRANITE", "INORGANIC:IRON", "GLASS_GREEN", "PLANT:OAK:WOOD"]
empty = hashlib.sha256(bytes(32 * 32 * 4)).hexdigest()
rows, lines = [], []
for i, case in enumerate(source["cases"]):
    # Cases retain their captured state, including unknown historical fields.
    values = [ ["Catapult", "Ballista", "BoltThrower"].index(case["subtype"]),
               case["stage"], case["maximum"], case["configuration"],
               case.get("facing", -1), case.get("fire_timer", -129),
               case["width"], case["height"], materials.index(case["material"]) ]
    hashes = set()
    for tile in case["tiles"]:
        assert "two" not in tile and "signpost" not in tile, (i, tile)
        if "one" in tile and tile["one"] != empty:
            hashes.add(tile["one"])
    assert hashes, i
    rows.append({"source_case": i, "state": values, "hashes": sorted(hashes)})
    lines.append(" ".join(map(str, values)))
(root / "build/siege-input.txt").write_text("\n".join(lines) + "\n")
(root / "build/siege-pixels.json").write_text(json.dumps(rows))
exe = root / "build/tools/make_siege_fixture.exe"
subprocess.run([str(exe), str(root / "build/siege-input.txt"), str(root / "build/siege.df3dfix")], check=True)
print("QA_SIEGE_FIXTURE_PASS", len(rows))
