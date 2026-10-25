"""Replay native constructed-ramp artwork across materials and cardinal supports."""
from pathlib import Path
import gzip
import json
import subprocess

root = Path(__file__).resolve().parents[2]
source = json.loads(gzip.decompress((root / "fixtures/construction/constructed_ramp_rendering.json.gz").read_bytes()))
rows, lines = [], []
for i, case in enumerate(source["cases"]):
    mask = sum(bit for letter, bit in [("N",1),("S",2),("E",4),("W",8)] if letter in case["suffix"])
    values = [mask, ["lone","N","S","E","W"].index(case["support"]), int(case["item_type"] == "WOOD")]
    rows.append({"source_case":i, "state":values, "background":case["background_sha256"], "rail":case["rail_sha256"]})
    lines.append(" ".join(map(str, values)))
(root / "build/constructed-ramp-input.txt").write_text("\n".join(lines) + "\n")
(root / "build/constructed-ramp-pixels.json").write_text(json.dumps(rows))
subprocess.run([str(root / "build/tools/make_constructed_ramp_fixture.exe"), str(root / "build/constructed-ramp-input.txt"), str(root / "build/constructed-ramp.df3dfix")], check=True)
print("QA_CONSTRUCTED_RAMP_FIXTURE_PASS", len(rows))
