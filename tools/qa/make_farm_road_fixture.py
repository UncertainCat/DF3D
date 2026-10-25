"""Replay recorded farm/road artwork with exact cell-position expectations."""
from pathlib import Path
import gzip
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
source = json.loads(gzip.decompress((root / "fixtures/construction/farm_road_rendering.json.gz").read_bytes()))
materials = ["INORGANIC:GRANITE", "INORGANIC:IRON", "GLASS_GREEN", "PLANT:OAK:WOOD"]
empty = hashlib.sha256(bytes(32 * 32 * 4)).hexdigest()
rows, lines = [], []
for i, case in enumerate(source["cases"]):
    assert case["maximum"] == 3
    extents = case["extents"]
    mask = "NONE" if all(e == -1 for e in extents) else "".join(str(e) for e in extents)
    assert mask == "NONE" or len(mask) == case["width"] * case["height"]
    component = case.get("material", "NONE")
    values = [["FarmPlot", "RoadDirt", "RoadPaved"].index(case["kind"]), case["width"], case["height"], case["stage"],
              materials.index(case.get("building_material", materials[0])), materials.index(component) if component != "NONE" else -1, mask]
    cells = {}
    for tile in case["tiles"]:
        assert "two" not in tile and "signpost" not in tile
        if tile.get("one", empty) != empty:
            cells[f"{tile['x']},{tile['y']}"] = tile["one"]
    rows.append({"source_case": i, "state": values, "cells": cells})
    lines.append(" ".join(map(str, values)))
(root / "build/farm-road-input.txt").write_text("\n".join(lines) + "\n")
(root / "build/farm-road-pixels.json").write_text(json.dumps(rows))
subprocess.run([str(root / "build/tools/make_farm_road_fixture.exe"), str(root / "build/farm-road-input.txt"), str(root / "build/farm-road.df3dfix")], check=True)
print("QA_FARM_ROAD_FIXTURE_PASS", len(rows))
