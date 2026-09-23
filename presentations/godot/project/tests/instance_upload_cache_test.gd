extends SceneTree
const Uploads = preload("res://scripts/instance_upload_cache.gd")
func _initialize() -> void:
	var cache := Uploads.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = 2
	var layer = cache.begin(mm)
	var positions := [Vector3.ZERO, Vector3(2, 0, 0)]
	for i in 2:
		layer.write(mm, i, Transform3D(Basis.IDENTITY, positions[i]), Color(8,0,0), Color.WHITE)
	assert(cache.stats().transforms_written == 2)
	assert(cache.stats().custom_written == 2 and cache.stats().colors_written == 2)
	# Unchanged resolved outputs never call engine setters again.
	layer = cache.begin(mm)
	for i in 2:
		layer.write(mm, i, Transform3D(Basis.IDENTITY, positions[i]), Color(8,0,0), Color.WHITE)
	assert(cache.stats().transforms_written == 2 and cache.stats().custom_written == 2 and cache.stats().colors_written == 2)
	# Each output channel is independent of the others.
	positions[1] = Vector3(3,0,0)
	layer.write(mm, 1, Transform3D(Basis.IDENTITY, positions[1]), Color(8,0,0), Color.WHITE)
	assert(cache.stats().transforms_written == 3 and cache.stats().custom_written == 2)
	layer.write(mm, 1, Transform3D(Basis.IDENTITY, positions[1]), Color(9,0,0), Color.WHITE)
	layer.write(mm, 1, Transform3D(Basis.IDENTITY, positions[1]), Color(9,0,0), Color.RED)
	assert(cache.stats().transforms_written == 3 and cache.stats().custom_written == 3 and cache.stats().colors_written == 3)
	# Omitted optional channels retain their previous resident value.
	layer.write(mm, 1, Transform3D(Basis.IDENTITY, positions[1]))
	assert(layer.custom_data[1] == Color(9,0,0) and layer.colors[1] == Color.RED)
	var submission: Dictionary = cache.submission_stats()
	assert(submission.instance_payload_bytes == 3*48 + 6*16)
	# Source ordinal changes matter only through the final output.
	positions.reverse()
	for i in 2: layer.write(mm, i, Transform3D(Basis.IDENTITY, positions[i]))
	assert(cache.stats().transforms_written == 5)
	# Buffer recreation must replay even numerically identical payloads.
	mm.instance_count = 0
	cache.invalidate(mm)
	mm.instance_count = 2
	cache.invalidate(mm)
	layer = cache.begin(mm)
	layer.write(mm, 0, Transform3D(Basis.IDENTITY, positions[0]), Color(8,0,0), Color.WHITE)
	assert(cache.stats().transforms_written == 6)
	# Diagnostic bypass forces all requested writes; reenabling starts fresh.
	cache.enabled = false
	layer = cache.begin(mm)
	for i in 2: layer.write(mm, 0, Transform3D(Basis.IDENTITY, positions[0]), Color(8,0,0), Color.WHITE)
	assert(cache.stats().transforms_written == 8)
	cache.enabled = true
	layer = cache.begin(mm)
	layer.write(mm, 0, Transform3D(Basis.IDENTITY, positions[0]), Color(8,0,0), Color.WHITE)
	assert(cache.stats().transforms_written == 9)
	var key: String = cache.region_key(3, Color(0.1,0.2,0.3,0.4))
	assert(key == cache.region_key(3, Color(0.1,0.2,0.3,0.4)))
	assert(key != cache.region_key(4, Color(0.1,0.2,0.3,0.4)))
	assert(key != cache.region_key(3, Color(0.10001,0.2,0.3,0.4)))
	print("INSTANCE_UPLOAD_CACHE_PASS")
	quit()
