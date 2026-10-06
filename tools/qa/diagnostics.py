"""Precisely identify accepted engine diagnostics while preserving unexpected errors."""
from collections import Counter
import re

# Match the pinned engine banner, error AND its adjacent engine callsite. A
# familiar message at a new callsite stays unclassified. Counts are occurrences,
# not distinct defects. Raw logs and gate status remain authoritative.
KNOWN = (
    ("godot-separate-thread-notice", "Configured separate-renderer startup notice", "https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-driver-threads-thread-model",
     r"WARNING: The separate rendering thread feature is experimental\. Feel free to try it since it will eventually become a stable feature\.",
     r"at: setup2 \(main/main\.cpp:3518\)"),
    ("godot-device-finalize", "Godot separate-renderer shutdown", "https://github.com/godotengine/godot/issues/119000",
     r"ERROR: This function \(finalize\) can only be called from the render thread\.\s*",
     r"at: finalize \(servers/rendering/rendering_device\.cpp:8862\)"),
    # Reproduced in an empty project, without DF3D scripts or GDExtension.
    # Only recognize this alongside this process's known D3D12 shutdown below.
    ("godot-shutdown-objects", "Godot D3D12 shutdown object pair", "ENGINEERING.md#tests-and-known-problems",
     r"WARNING: 2 ObjectDB instances were leaked at exit \(run with `--verbose` for details\)\.",
     r"at: cleanup \(core/object/object\.cpp:2536\)"),
    ("godot-font-atlas", "Godot empty-image upload signature", "https://github.com/godotengine/godot/issues/122206",
     r'ERROR: Condition "p_image\.is_null\(\) \|\| p_image->is_empty\(\)" is true\.',
     r"at: _texture_2d_update \(servers/rendering/renderer_rd/storage_rd/texture_storage\.cpp:1617\)"),
    ("godot-font-atlas-update", "Godot empty-image upload signature (texture_update)", "https://github.com/godotengine/godot/issues/122206",
     r"ERROR: Required size for texture update \(\d+\) does not match data supplied size \(0\)\.",
     r"at: texture_update \(servers/rendering/rendering_device\.cpp:2283\)"),
    ("godot-dummy-mesh", "Godot headless mesh signature", "https://github.com/godotengine/godot/issues/121949",
     r'ERROR: Parameter "m" is null\.',
     r"at: mesh_get_surface_count \(servers/rendering/dummy/storage/mesh_storage\.h:151\)"),
)

def error_summary(output):
    lines = output.splitlines()
    known = Counter()
    unexpected = Counter()
    pinned = False
    process_known = set()
    d3d12 = False
    for index, line in enumerate(lines):
        if line.startswith("Godot Engine v"):
            process_known.clear()
            d3d12 = False
            pinned = bool(re.match(r"^Godot Engine v4\.7\.2\.stable\.steam\.ed1daf0bf(?:[ \t]|$)", line))
        if line.startswith("D3D12 ") and "Using Device #" in line:
            d3d12 = True
        if not re.match(r"^\s*(?:SCRIPT ERROR:|ERROR:|WARNING:|FAIL(?:\b|:))", line):
            continue
        # Engine callsites normally immediately follow. Permit one interleaved
        # info line but never search across another error or distant traceback.
        context = []
        for following in lines[index + 1:index + 4]:
            if re.match(r"^\s*(?:SCRIPT ERROR:|ERROR:|WARNING:|FAIL(?:\b|:))", following): break
            context.append(following.strip())
        match = next((entry for entry in KNOWN if pinned and
                      re.fullmatch(entry[3], line.strip()) and
                      any(re.fullmatch(entry[4], at) for at in context)), None)
        if match and match[0] == "godot-shutdown-objects":
            if not (d3d12 and {"godot-separate-thread-notice", "godot-device-finalize"} <= process_known
                    and "godot-shutdown-objects" not in process_known):
                match = None
        if match:
            process_known.add(match[0])
            known[match[0]] += 1
        else:
            unexpected[line.strip()] += 1
    return {
        "known_engine": [{"id": key, "count": count, "reference": next(k[2] for k in KNOWN if k[0] == key)}
                         for key, count in known.items()],
        "unclassified": [{"message": key, "count": count} for key, count in unexpected.items()],
    }

def console_summary(row):
    """Human output is short; JSON and raw logs retain complete evidence."""
    diag = row.get("diagnostics", {})
    known = diag.get("known_engine", [])
    unknown = diag.get("unclassified", [])
    details = []
    if unknown:
        details.append("unclassified: " + "; ".join(f"{r['message']} (x{r['count']})" for r in unknown[:3]))
    if known:
        details.append("deferred known issues: " + ", ".join(f"{r['id']} x{r['count']}" for r in known))
    # Avoid repeating errors already included above. Still show missing markers,
    # process failures, prerequisite failures and probe assertion failures.
    reasons = [r for r in row.get("reasons", []) if not re.match(r"^\s*(?:ERROR:|WARNING:|SCRIPT ERROR:|FAIL\b)", r)]
    details.extend(dict.fromkeys(reasons))
    result = f"{row['id']}: {status_label(row['status'])}"
    if details: result += " | " + " | ".join(details)
    if row["status"] != "passed" and row.get("log"): result += " | log: " + row["log"]
    return result


def status_label(status):
    return "PASSED (KNOWN ISSUES)" if status == "passed_with_known_issues" else status.upper()
