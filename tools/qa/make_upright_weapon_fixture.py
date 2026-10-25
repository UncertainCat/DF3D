"""Build upright references, keeping approved spike corrections explicit."""
from pathlib import Path
import gzip
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
source = json.loads(gzip.decompress((root / "fixtures/construction/weapon_rendering.json.gz").read_bytes()))
materials = ["INORGANIC:GRANITE", "INORGANIC:IRON", "GLASS_GREEN", "PLANT:OAK:WOOD"]
empty = hashlib.sha256(bytes(32 * 32 * 4)).hexdigest()
cases = []
for index, case in enumerate(source["cases"]):
    if case["kind"] != "Weapon": continue
    weapon = next((item for item in case["components"] if item["class"] in ["item_weaponst", "item_trapcompst"]), None)
    if weapon and weapon["raw"] not in ["ITEM_WEAPON_SPEAR", "ITEM_TRAPCOMP_MENACINGSPIKE"]: continue
    cases.append({**case, "source_index": index})
rows, lines = [], []
for i, case in enumerate(cases):
    weapon = next((item for item in case["components"] if item["class"] in ["item_weaponst", "item_trapcompst"]), None)
    values = [case["stage"], case["maximum"], case["contained_item_count"], case["weapon_flags"] & 1,
              case["weapon_count"], materials.index(weapon["material"]) if weapon else -1,
              materials.index(case.get("building_material", "INORGANIC:GRANITE")), weapon["raw"] if weapon else "NONE"]
    hashes = set()
    corrected = (case["stage"] == case["maximum"] and not (case["weapon_flags"] & 1)
                 and weapon and weapon["raw"] == "ITEM_TRAPCOMP_MENACINGSPIKE" and case["weapon_count"] >= 5)
    for tile in case["tiles"]:
        assert "two" not in tile, (i, tile)
        for layer in ["one", "signpost"]:
            if layer in tile and tile[layer] != empty:
                if not (corrected and tile["x"] == 0 and tile["y"] == 0 and layer == "one"):
                    hashes.add(tile[layer])
    if corrected:
        hashes.add(source["upright_spike_bug"]["approved_bottom_pixels"]["hashes"][weapon["material"]][str(min(10, case["weapon_count"]))])
    rows.append({"source_case": case["source_index"], "approved_spike_correction": bool(corrected), "state": values, "hashes": sorted(hashes)})
    lines.append(" ".join(map(str, values)))
(root / "build/upright-weapon-input.txt").write_text("\n".join(lines) + "\n")
(root / "build/upright-weapon-pixels.json").write_text(json.dumps(rows))
exe = root / "build/tools/make_upright_weapon_fixture.exe"
subprocess.run([str(exe), str(root / "build/upright-weapon-input.txt"), str(root / "build/upright-weapon.df3dfix")], check=True)
print("QA_UPRIGHT_WEAPON_FIXTURE_PASS", len(rows))
