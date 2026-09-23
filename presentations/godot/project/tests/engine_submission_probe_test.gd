extends SceneTree

func _initialize() -> void:
	var probe = preload("res://tests/engine_submission_probe.gd").new()
	probe.begin({"mesh_payload_bytes": 100, "terrain_mesh_payload_bytes": 100})
	probe.record({"mesh_payload_bytes": 148, "terrain_mesh_payload_bytes": 148}, 10, {"owner": 42, "building_dropped": 2}, 4.0)
	probe.record({"mesh_payload_bytes": 148, "terrain_mesh_payload_bytes": 148}, 11, {"owner": 77}, 20.0)
	var stats: Dictionary = probe.summary()
	assert(stats.totals.mesh_payload_bytes == 48)
	assert(stats.per_frame.mesh_payload_bytes.mean == 24)
	assert(stats.largest_payload_frames[0].frame == 10)
	assert(stats.largest_payload_frames[0].details.owner == 42)
	assert(stats.slowest_frames[0].frame == 11 and stats.slowest_frames[0].details.owner == 77)
	assert(stats.detail_drops.building == 2 and stats.detail_drops.batch == 0)
	assert(probe._payload(stats.totals) == 48) # Source counters are not additive totals.
	for i in 600: probe.record({"mesh_payload_bytes": 149 + i}, 12 + i)
	stats = probe.summary()
	assert(stats.frames == 602 and stats.retained_frames == 512)
	assert(stats.totals.mesh_payload_bytes == 648)
	assert(stats.largest_payload_frames.size() == 8)
	probe.record({"mesh_payload_bytes": 0}, 999)
	assert(probe.summary().counter_resets == 1)
	print("ENGINE_SUBMISSION_PROBE_PASS")
	quit()
