"""Build trap replay inputs and pixel expectations from the native reference."""
from pathlib import Path
import gzip
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
source = json.loads(gzip.decompress((root / "fixtures/construction/weapon_rendering.json.gz").read_bytes()))
materials = ["INORGANIC:GRANITE", "INORGANIC:IRON", "GLASS_GREEN", "PLANT:OAK:WOOD"]
empty = hashlib.sha256(bytes(32 * 32 * 4)).hexdigest()
cases = [c for c in source["cases"] if c["kind"] == "Trap" and c["subtype_id"] == 4]
initial = json.loads(gzip.decompress((root / "fixtures/construction/simple_construction_rendering.json.gz").read_bytes()))
for case in initial["cases"]:
    if case["kind"] == "Trap" and case["subtype_id"] == 4:
        cases.append({**case, "state": case["trap_state"], "weapon_count": 0, "components": []})
rows, lines = [], []
for i, case in enumerate(cases):
    weapon = next((item for item in case["components"] if item["class"] in ["item_weaponst", "item_trapcompst"]), None)
    values = [case["stage"], case["maximum"], case["contained_item_count"], case["state"],
              case["weapon_count"], materials.index(weapon["material"]) if weapon else -1,
              materials.index(case.get("building_material", "INORGANIC:GRANITE")), weapon["raw"] if weapon else "NONE"]
    hashes = set()
    for tile in case["tiles"]:
        assert "two" not in tile, (i, tile)
        for layer in ["one", "signpost"]:
            if layer in tile and tile[layer] != empty:
                hashes.add(tile[layer])
    rows.append({"source_case": i, "state": values, "hashes": sorted(hashes)})
    lines.append(" ".join(map(str, values)))
(root / "build/weapon-trap-input.txt").write_text("\n".join(lines) + "\n")
(root / "build/weapon-trap-pixels.json").write_text(json.dumps(rows))
exe = root / "build/tools/make_weapon_trap_fixture.exe"
subprocess.run([str(exe), str(root / "build/weapon-trap-input.txt"), str(root / "build/weapon-trap.df3dfix")], check=True)
print("QA_WEAPON_TRAP_FIXTURE_PASS", len(rows))
