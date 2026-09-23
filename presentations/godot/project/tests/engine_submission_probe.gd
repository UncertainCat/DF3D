extends RefCounted
# Benchmark-only snapshots of cumulative application -> engine counters.
# No render-server readbacks. Retained rows are bounded; totals cover all rows.
const MAX_ROWS := 512
var previous: Dictionary = {}
var rows: Array = []
var totals: Dictionary = {}
var frames := 0
var resets := 0
var detail_drops := {"building": 0, "batch": 0}

func begin(counters: Dictionary) -> void:
	previous = counters.duplicate()
	rows.clear()
	totals.clear()
	frames = 0
	resets = 0
	detail_drops = {"building": 0, "batch": 0}

func record(counters: Dictionary, frame: int, details: Dictionary = {}, frame_ms := 0.0) -> void:
	var delta := {}
	for key in counters:
		var value: int = int(counters[key]) - int(previous.get(key, counters[key]))
		if value < 0:
			resets += 1
			value = 0
		delta[key] = value
		totals[key] = int(totals.get(key, 0)) + value
	previous = counters.duplicate()
	frames += 1
	detail_drops.building += int(details.get("building_dropped", 0))
	detail_drops.batch += int(details.get("batch_dropped", 0))
	rows.append({"frame": frame, "counts": delta, "frame_ms": frame_ms, "details": details})
	if rows.size() > MAX_ROWS: rows.pop_front()

static func distribution(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	var sum := 0.0
	for value in values: sum += value
	return {"mean": sum / values.size(), "p50": values[(values.size() - 1) / 2],
		"p95": values[mini(values.size() - 1, ceili(values.size() * 0.95) - 1)], "max": values[-1]}

func summary() -> Dictionary:
	var stats := {}
	for key in totals:
		var values := []
		for row in rows: values.append(row.counts.get(key, 0))
		stats[key] = distribution(values)
	var outliers := rows.duplicate()
	outliers.sort_custom(func(a, b): return _payload(a.counts) > _payload(b.counts))
	outliers.resize(mini(8, outliers.size()))
	var slowest := rows.duplicate()
	slowest.sort_custom(func(a, b): return a.frame_ms > b.frame_ms)
	slowest.resize(mini(3, slowest.size()))
	return {"frames": frames, "retained_frames": rows.size(), "counter_resets": resets,
		"totals": totals.duplicate(), "per_frame": stats, "largest_payload_frames": outliers,
		"slowest_frames": slowest,
		"detail_drops": detail_drops.duplicate(),
		"semantics": "Logical API payload bytes, not PCIe traffic; allocation requests are separate. Distributions describe retained frames."}

static func _payload(counts: Dictionary) -> int:
	var value := 0
	for key in ["instance_payload_bytes", "mesh_payload_bytes", "texture_payload_bytes"]:
		value += int(counts.get(key, 0))
	return value
