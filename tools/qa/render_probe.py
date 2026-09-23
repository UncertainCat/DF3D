"""Retain a standalone, real-renderer reproduction of the font atlas diagnostic."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
from evidence import ROOT, execute, is_success
from diagnostics import console_summary

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--mode", choices=["separate", "safe"], default="separate")
args = parser.parse_args()
output = ROOT / "build/qa-render-probe" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
output.mkdir(parents=True)
(output / "project.godot").write_text("config_version=5\n")
shutil.copyfile(ROOT / "tools/smoke/font_atlas_probe.gd", output / "probe.gd")
godot = os.environ.get("DF3D_GODOT", "C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe")
result = execute({"id": "font_atlas", "completion": "FONT_ATLAS_PROBE_DONE", "timeout": 60},
                 [godot, "--path", str(output), "--render-thread", args.mode, "--script", "res://probe.gd"],
                 env=os.environ.copy(), output_dir=output)
result["render_thread"] = args.mode
(output / "summary.json").write_text(json.dumps(result, indent=2))
# Forward the original diagnostic context to the enclosing gate's retained log.
# Its console reporter groups repeats; it must not lose stack/version evidence
# inside an opaque nested JSON string.
print(Path(result["log"]).read_text(encoding="utf-8", errors="replace"))
print(console_summary(result))
if is_success(result["status"]):
    print("FONT_ATLAS_PASS")
    raise SystemExit(0)
if result["status"] == "incomplete":
    print("QA_INCOMPLETE: standalone real renderer unavailable")
    raise SystemExit(77)
raise SystemExit(1)
