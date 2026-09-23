extends RefCounted
# Explicit deep-only probe. Per-operation clocks perturb timings, so use this to
# attribute upload bursts, not to report normal frame rates. Retain bounded rows.
const LIMIT := 32
var enabled := OS.get_environment("DF3D_ITEM_PROBE") == "1" and preload("res://scripts/frame_costs.gd").configured_mode() == "deep"
var rows: Array = []
var row: Dictionary = {}
var _before: Dictionary = {}
var _start := 0

func reset() -> void:
	rows.clear()

func begin(counters: Dictionary) -> void:
	if not enabled: return
	_start = Time.get_ticks_usec()
	_before = counters.duplicate()
	row = {"schema_version": 2, "timestamp_us": _start, "groups": 0,
		"changed_groups": 0, "largest_changed_group": 0,
		"prepared_transforms": 0, "prepared_custom": 0, "prepared_colors": 0,
		"resized_groups": 0, "resized_instances": 0,
		"manifest_us": 0, "prepare_us": 0, "write_us": 0,
		"group_examples": [], "selection_reasons": {}}

func group_selection(group: Dictionary, previous: int, allocated: bool, sparse: bool) -> void:
	if not enabled: return
	row.groups += 1
	var reason := "sparse" if sparse else ("allocation" if allocated else ("no_baseline" if previous < 0 else "revision_mismatch_or_cache_disabled"))
	row.selection_reasons[reason] = row.selection_reasons.get(reason, 0) + 1
	row.group_examples.append({"key": group.key, "slot": group.slot,
		"members": group.indices.size(), "changed": group.changed_indices.size(),
		"previous_revision": previous, "base_revision": group.base_revision,
		"revision": group.revision, "selection": reason})
	row.group_examples.sort_custom(func(a, b): return a.members > b.members)
	if row.group_examples.size() > 6: row.group_examples.resize(6)

func prepared(patch) -> void:
	if not enabled: return
	row.prepared_transforms += patch.transforms.size()
	row.prepared_custom += patch.custom.size()
	row.prepared_colors += patch.colors.size()
	if not patch.transforms.is_empty() or not patch.custom.is_empty() or not patch.colors.is_empty():
		row.changed_groups += 1
		row.largest_changed_group = maxi(row.largest_changed_group, patch.group.transforms.size())

func add(stage: String, start: int) -> void:
	row[stage] += Time.get_ticks_usec() - start

func finish(counters: Dictionary) -> void:
	if not enabled: return
	row["total_us"] = Time.get_ticks_usec() - _start
	var delta := {}
	# Unit-cache bookkeeping shares the counter dictionary but is not part of
	# item preparation anymore. Export only measurements this path performs.
	for key in ["instances_considered", "transforms_written", "custom_written", "colors_written", "ceiling_evaluations", "ceiling_cache_hits"]:
		if counters.has(key): delta[key] = counters[key] - _before.get(key, 0)
	row["work"] = delta
	rows.append(row)
	rows.sort_custom(func(a, b): return a.total_us > b.total_us)
	if rows.size() > LIMIT: rows.resize(LIMIT)
	row = {}

func summary() -> Array:
	return rows.duplicate(true)
