"""Bake reviewed native widget observations into editable presentation candidates.

Raw captures are evidence, not templates: text/actions require explicit recipes.
This tool never changes a product definition or executes captured callbacks.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path


TYPES = {"label", "button", "texture", "separator"}
FIELDS = {"binding", "action", "selector", "text", "view", "color"}


def finite(values, length):
    return isinstance(values, list) and len(values) == length and all(
        type(v) in (int, float) and math.isfinite(v) for v in values)


def flatten(roots):
    result = {}
    pending = list(roots)
    while pending:
        node = pending.pop(0)
        if not isinstance(node, dict) or not isinstance(node.get("id"), str):
            raise ValueError("Capture nodes need string IDs")
        if node["id"] in result:
            raise ValueError("Duplicate capture ID: " + node["id"])
        result[node["id"]] = node
        pending.extend(node.get("children", []))
        if len(result) > 2048:
            raise ValueError("Capture exceeds 2048 nodes")
    return result


def bake(capture, recipe):
    if capture.get("format_version") != 1 or recipe.get("format_version") != 1:
        raise ValueError("Unsupported capture/recipe version")
    if capture.get("df_version") != recipe.get("df_version"):
        raise ValueError("DF version changed; review the reference before rebaking")
    if capture.get("coordinate_space") != "native_widget_rect_inclusive":
        raise ValueError("Unknown native coordinate convention")
    scale, origin = recipe.get("pixel_scale"), recipe.get("origin")
    if not finite(scale, 2) or min(scale) <= 0 or not finite(origin, 2):
        raise ValueError("Explicit finite positive pixel_scale and origin required")
    if not isinstance(recipe.get("id"), str) or not recipe["id"]:
        raise ValueError("Recipe id required")
    source = flatten(capture.get("roots", []))
    mappings = recipe.get("widgets", {})
    if not isinstance(mappings, dict):
        raise ValueError("Recipe widgets must map source paths to reviewed bindings")
    nodes, unsupported, used_ids = [], [], set()
    for path, entry in mappings.items():
        if path not in source:
            raise ValueError("Missing reviewed source widget: " + path)
        native = source[path]
        if entry.get("expected_type") != native.get("native_type") or entry.get("expected_name") != native.get("name"):
            raise ValueError("Widget identity changed at " + path)
        if native.get("unsupported"):
            raise ValueError("Incomplete source widget: " + path)
        kind, identity = entry.get("type"), entry.get("id")
        if kind not in TYPES or not isinstance(identity, str) or not identity or identity in used_ids:
            raise ValueError("Unsupported type or duplicate/missing recipe id: " + path)
        if "binding" in entry and "text" in entry:
            raise ValueError("Dynamic bindings cannot contain captured text")
        if kind == "label" and not (entry.get("binding") or "text" in entry):
            raise ValueError("Text needs a binding or explicitly reviewed static label")
        if kind == "button" and not entry.get("action"):
            raise ValueError("Buttons need a reviewed semantic action")
        if kind == "texture" and not (entry.get("selector") or entry.get("binding")):
            raise ValueError("Textures need an original-asset selector or binding")
        rect = native.get("rect")
        if not finite(rect, 4) or rect[2] < rect[0] or rect[3] < rect[1]:
            raise ValueError("Invalid native rectangle: " + path)
        used_ids.add(identity)
        node = {"id": identity, "type": kind, "source_path": path,
                "rect": [(rect[0]-origin[0])*scale[0], (rect[1]-origin[1])*scale[1],
                         (rect[2]-rect[0]+1)*scale[0], (rect[3]-rect[1]+1)*scale[1]]}
        node.update({key: entry[key] for key in FIELDS if key in entry})
        nodes.append(node)
        if any(native.get("custom", {}).values()):
            unsupported.append({"source_path": path, "native_type": native.get("native_type"),
                                "reason": "Geometry imported; custom callbacks still require manual behavioral verification"})
    for path, native in source.items():
        if native.get("truncated_children"):
            unsupported.append({"source_path": path, "native_type": native.get("native_type", "unknown"),
                                "reason": "Capture limit: additional children not observed"})
        if path not in mappings:
            unsupported.append({"source_path": path, "native_type": native.get("native_type", "unknown"),
                                "reason": native.get("unsupported", "No reviewed binding/template; not imported")})
    unsupported.extend(capture.get("unsupported", []))
    return {"format_version": 1, "id": recipe["id"],
            "provenance": {"df_version": capture["df_version"], "status": "import-candidate",
                           "authoring": "native-widget-recipe", "record": recipe.get("record", ""),
                           "capture_sha256": hashlib.sha256(json.dumps(capture, sort_keys=True).encode()).hexdigest()},
            "layout": recipe.get("layout", {}), "nodes": nodes,
            "unsupported_widgets": unsupported}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("recipe", type=Path)
    parser.add_argument("output", type=Path, help="New candidate path; never overwritten")
    args = parser.parse_args()
    result = bake(json.loads(args.capture.read_text(encoding="utf-8-sig")),
                  json.loads(args.recipe.read_text(encoding="utf-8-sig")))
    # Exclusive creation is intentional: promotion into the editable product
    # tree is a separate review step, never an importer side effect.
    with args.output.open("x", encoding="utf-8", newline="\n") as out:
        json.dump(result, out, indent=2, ensure_ascii=False)
        out.write("\n")
    print(f"Baked {len(result['nodes'])} nodes; {len(result['unsupported_widgets'])} explicit diagnostics")


if __name__ == "__main__":
    main()
