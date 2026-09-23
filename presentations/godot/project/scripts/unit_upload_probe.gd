extends RefCounted
# Intrusive opt-in diagnostic; no per-actor retained data or normal-run clocks.
var enabled := OS.get_environment("DF3D_UNIT_PROBE") == "1" and preload("res://scripts/frame_costs.gd").configured_mode() == "deep"
var rows: Array = []
var row: Dictionary = {}
func begin() -> void:
	row = {"timestamp_us": Time.get_ticks_usec(), "source_detail_us": {}, "partition_rebuilds": 0, "partition_keys_built": 0, "source_changed_actors": 0, "source_membership_changed": false, "preflight_us": 0, "source_us": 0, "setup_us": 0, "flush_us": 0, "demand_us": 0, "bounds_us": 0,
		"motion_us": 0, "animation_us": 0, "clipping_us": 0, "storage_us": 0, "actors": 0,
		"groups_scanned": 0, "unchanged_groups": 0, "full": false, "membership_groups": 0, "deferred_groups": 0, "hidden_groups": 0}
func add(stage: String, start: int) -> void:
	row[stage] += Time.get_ticks_usec() - start
# Children of source_us, intentionally excluded from the disjoint accounted sum.
func source_mark(stage: String, start: int) -> int:
	var now := Time.get_ticks_usec()
	row.source_detail_us[stage] = now - start
	return now
func finish() -> void:
	row.total_us = Time.get_ticks_usec() - row.timestamp_us
	var accounted := 0
	for name in ["preflight_us", "source_us", "setup_us", "flush_us", "demand_us", "bounds_us", "motion_us", "animation_us", "clipping_us", "storage_us"]: accounted += int(row[name])
	row.unaccounted_us = maxi(0, int(row.total_us) - accounted)
	rows.append(row)
	rows.sort_custom(func(a, b): return a.total_us > b.total_us)
	if rows.size() > 32: rows.resize(32)
	row = {}
