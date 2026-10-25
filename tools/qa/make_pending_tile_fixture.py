"""Replay recorded pending construction artwork with exact cell-position expectations."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
source = json.loads((root / "fixtures/construction/pending_tile_rendering.json").read_text())
materials = ["INORGANIC:GRANITE", "INORGANIC:IRON", "GLASS_GREEN", "PLANT:OAK:WOOD"]
empty = hashlib.sha256(bytes(32 * 32 * 4)).hexdigest()
rows, lines = [], []
for i, case in enumerate(source["cases"]):
    assert case["stage"] == 0 and case["maximum"] == 1
    values = [case["subtype_id"], materials.index(case["material"])]
    cells = {}
    for tile in case["tiles"]:
        assert "two" not in tile and "signpost" not in tile
        if tile.get("one", empty) != empty:
            cells[f"{tile['x']},{tile['y']}"] = tile["one"]
    rows.append({"source_case": i, "state": values, "cells": cells})
    lines.append(" ".join(map(str, values)))
(root / "build/pending-tile-input.txt").write_text("\n".join(lines) + "\n")
(root / "build/pending-tile-pixels.json").write_text(json.dumps(rows))
subprocess.run([str(root / "build/tools/make_pending_tile_fixture.exe"), str(root / "build/pending-tile-input.txt"), str(root / "build/pending-tile.df3dfix")], check=True)
print("QA_PENDING_TILE_FIXTURE_PASS", len(rows))
