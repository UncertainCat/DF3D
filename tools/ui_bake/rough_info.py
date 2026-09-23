"""Generate reviewable rough Info layouts and a complete exposed-widget inventory.

Only explicit static labels are copied. Concrete rows become blank template
slots, and callbacks remain unavailable. No captured fortress values are shipped.
"""
import argparse
import json
from collections import Counter
from pathlib import Path
import xml.etree.ElementTree as ET

from bake_widgets import flatten, finite

GROUPS = {
    "Creatures": ["Residents", "Pets/Livestock", "Other", "Dead/Missing"],
    "Tasks": [], "Places": ["Zones", "Locations", "Stockpiles", "Workshops", "Farm plots", "Siege engines"],
    "Labor": ["Work Details", "Standing orders", "Kitchen", "Stone use"], "Work orders": [],
    "Nobles and administrators": [], "Objects": ["Artifacts", "Symbols", "Named objects", "Written content"],
    "Justice": ["Open cases", "Closed cases", "Cold cases", "Fortress guard", "Convicts", "Intelligence"]}
STATIC = {"Name", "Cat", "Prof", "Job", "Stress"}


def family(name):
    if "text" in name or name in {"widget_character", "widget_unit_name", "widget_item_name"}: return "label"
    if "portrait" in name or "tile" in name or "nineslice" in name: return "texture"
    if "tabs" in name: return "tabs"
    if "scroll" in name: return "scroll"
    if "table" in name: return "table"
    if any(word in name for word in ("container", "rows", "columns", "stack")): return "container"
    if "button" in name: return "button"
    return "placeholder"


def inventory(directory):
    classes = {}
    for path in sorted(directory.glob("*.xml")):
        for item in ET.parse(path).getroot().findall("class-type"):
            classes[item.get("type-name")] = (item.get("inherits-from"), path.name)
    def is_widget(name, seen=None):
        seen = set() if seen is None else seen
        if name == "widget": return True
        if not name or name in seen or name not in classes: return False
        return is_widget(classes[name][0], seen | {name})
    return [{"native_type": name, "base": base, "source": source,
             "rough_family": family(name), "status": "geometry only; specialized behavior requires binding"}
            for name, (base, source) in sorted(classes.items()) if is_widget(name)]


def page(capture, primary):
    roots = capture.get("roots", [])
    actual = next((root for root in roots if root["id"] != "info"), None)
    out = {"primary": primary, "status": "layout-only", "nodes": [], "remaining": [], "source_extent": [0, 0]}
    if not actual:
        out["remaining"] = ["Native page does not expose a widget tree; body deliberately blank pending reference mapping."]
        return out
    origin = actual["rect"][:2]
    scale = capture["cell_pixels"]
    out["source_extent"] = [(actual["rect"][2]-origin[0]+1)*scale[0], (actual["rect"][3]-origin[1]+1)*scale[1]]
    skipped = 0
    for source in flatten([actual]).values():
        rect = source.get("rect")
        if not finite(rect, 4) or rect[2] < rect[0] or rect[3] < rect[1]:
            skipped += 1
            continue
        kind = family(source.get("native_type", ""))
        if kind == "placeholder" and source.get("custom", {}).get("activated", 0): kind = "button"
        node = {"id": source["id"], "type": kind,
                "rect": [(rect[0]-origin[0])*scale[0], (rect[1]-origin[1])*scale[1],
                         (rect[2]-rect[0]+1)*scale[0], (rect[3]-rect[1]+1)*scale[1]],
                "status": "unbound", "native_type": source.get("native_type", "unknown")}
        if source.get("name") in STATIC and kind in {"label", "button", "placeholder"}:
            node["text"] = source["name"]
        # Runtime values and callback bodies are never part of this output.
        if source.get("row_template"):
            node["repeat_template"] = True
        out["nodes"].append(node)
    out["remaining"] = ["Live data and row-template bindings; unknown values stay blank.",
                         "Native custom rendering, actions, tooltips, clipping and alternate states.",
                         f"{skipped} invalid/unallocated rectangles omitted; verify against native rendering."]
    return out


def build(manifest):
    result = {"format_version": 1, "provenance": "native DF 53.16 fortress info layout, captured from the supported build", "groups": GROUPS, "pages": {}}
    for record in manifest["pages"]:
        primary = record["label"]
        capture = json.loads(Path(record["file"]).read_text(encoding="utf-8"))
        first = GROUPS[primary][0] if GROUPS[primary] else primary
        result["pages"][first] = page(capture, primary)
        for label in GROUPS[primary][1:]:
            result["pages"][label] = {"primary": primary, "status": "unmapped-state", "nodes": [],
                "remaining": ["Native tab label observed; tab body/data/actions need capture and binding."]}
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("xml", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("inventory_output", type=Path)
    args = parser.parse_args()
    result = build(json.loads(args.manifest.read_text(encoding="utf-8")))
    items = inventory(args.xml)
    for target, data in ((args.output, result), (args.inventory_output, items)):
        with target.open("x", encoding="utf-8") as file: json.dump(data, file, indent=2);file.write("\n")
    print(f"{len(result['pages'])} page states; {len(items)} exposed widget classes; {dict(Counter(x['rough_family'] for x in items))}")
