"""Build trap replay inputs and pixel expectations from the native reference."""
from pathlib import Path
import gzip
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
source = json.loads(gzip.decompress((root / "fixtures/construction/trap_rendering.json.gz").read_bytes()))
materials = ["INORGANIC:GRANITE", "INORGANIC:IRON", "GLASS_GREEN", "PLANT:OAK:WOOD"]
empty = hashlib.sha256(bytes(32 * 32 * 4)).hexdigest()
rows, lines = [], []
for i, case in enumerate(source["cases"]):
    mechanism = next((item for item in case["components"] if item["class"] == "item_trappartsst"), None)
    values = [case["subtype_id"], case["stage"], case["maximum"], case["contained_item_count"],
              case["state"], case["ready_timeout"], case["fill_timer"], case["plate_flags"],
              materials.index(mechanism["material"]) if mechanism else -1,
              materials.index(case.get("building_material", "INORGANIC:GRANITE"))]
    hashes = set()
    for tile in case["tiles"]:
        assert "two" not in tile, (i, tile)
        for layer in ["one", "signpost"]:
            if layer in tile and tile[layer] != empty:
                hashes.add(tile[layer])
    rows.append({"source_case": i, "state": values, "hashes": sorted(hashes)})
    lines.append(" ".join(map(str, values)))
(root / "build/trap-input.txt").write_text("\n".join(lines) + "\n")
(root / "build/trap-pixels.json").write_text(json.dumps(rows))
exe = root / "build/tools/make_trap_fixture.exe"
subprocess.run([str(exe), str(root / "build/trap-input.txt"), str(root / "build/trap.df3dfix")], check=True)
print("QA_TRAP_FIXTURE_PASS", len(rows))
