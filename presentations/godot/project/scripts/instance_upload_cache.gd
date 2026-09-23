extends RefCounted
# Physical residency only. Source selection belongs to presentation preparation;
# exact output comparisons avoid redundant writes into retained engine buffers.
class Layer:
	extends RefCounted
	var transforms: Array = []
	var custom_data: Array = []
	var colors: Array = []
	var counters: Dictionary
	var force_write := false

	func prepare(count: int) -> void:
		if transforms.size() == count: return
		# Native count changes replace the buffer, not just its live prefix.
		transforms.resize(count); transforms.fill(null)
		custom_data.resize(count); custom_data.fill(null)
		colors.resize(count); colors.fill(null)

	func write(mm: MultiMesh, index: int, transform: Transform3D, custom: Variant = null, color: Variant = null) -> void:
		if force_write or transforms[index] != transform:
			mm.set_instance_transform(index, transform)
			transforms[index] = transform
			counters.transforms_written += 1
		if custom != null and (force_write or custom_data[index] != custom):
			mm.set_instance_custom_data(index, custom)
			custom_data[index] = custom
			counters.custom_written += 1
		if color != null and (force_write or colors[index] != color):
			mm.set_instance_color(index, color)
			colors[index] = color
			counters.colors_written += 1

var _layers: Dictionary = {}
var _region_keys: Dictionary = {}
var generation := 0
var counters := {"instances_considered": 0,
	"transforms_written": 0, "custom_written": 0, "colors_written": 0,
	"ceiling_evaluations": 0, "ceiling_cache_hits": 0, "cache_invalidations": 0}
var enabled := true:
	set(value):
		if enabled == value: return
		enabled = value
		_layers.clear()
		generation += 1
		counters.cache_invalidations += 1

func begin(mm: MultiMesh) -> Layer:
	var id := mm.get_instance_id()
	if not _layers.has(id):
		_layers[id] = Layer.new()
		_layers[id].counters = counters
	var layer: Layer = _layers[id]
	layer.force_write = not enabled
	layer.prepare(mm.instance_count)
	return layer

func invalidate(mm: MultiMesh) -> void:
	# Resizing reallocates Godot's instance buffer, even if a former count is
	# restored later. Removed layers must therefore discard cached output too.
	_layers.erase(mm.get_instance_id())
	counters.cache_invalidations += 1

func stats() -> Dictionary:
	return counters.duplicate()

func retain_regions(slots: Dictionary) -> void:
	for slot in _region_keys.keys():
		if not slots.has(slot): _region_keys.erase(slot)

func submission_stats() -> Dictionary:
	# Logical float32 payload, not driver traffic or Godot's dirty-buffer upload.
	return {"instance_transform_calls": counters.transforms_written,
		"instance_custom_calls": counters.custom_written,
		"instance_color_calls": counters.colors_written,
		"instance_payload_bytes": counters.transforms_written * 48 +
			(counters.custom_written + counters.colors_written) * 16}

func region_key(slot: int, region: Color) -> String:
	if not _region_keys.has(slot): _region_keys[slot] = {}
	var regions: Dictionary = _region_keys[slot]
	# Display-formatted Color strings round components; distinct native atlas
	# rectangles must never alias the same MultiMesh. Encode exact components.
	if not regions.has(region): regions[region] = str(slot) + ":" + var_to_bytes(region).hex_encode()
	return regions[region]
