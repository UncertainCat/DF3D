extends RefCounted
# Scene layers and their shared art have one lifetime. Visibility does not
# determine residency: hidden groups can still own valid, deferred payloads.
var unit_layers: Dictionary = {}
var item_layers: Dictionary = {}
var resources: Dictionary = {}
var revision := -1
var _shared_dirty := false

func track(layer: MultiMeshInstance3D, slot: int, resource_key: String) -> void:
	layer.set_meta("sprite_slot", slot)
	layer.set_meta("sprite_resource_key", resource_key)

func remove(cache: Dictionary, key: String, uploads, storage) -> void:
	if not cache.has(key): return
	var layer: MultiMeshInstance3D = cache[key]
	cache.erase(key)
	_shared_dirty = true
	uploads.invalidate(layer.multimesh)
	storage.forget(layer.multimesh)
	layer.hide()
	# Release heavyweight references immediately; node destruction is deferred
	# safely until Godot has completed the current frame.
	layer.material_override = null
	layer.multimesh = null
	layer.queue_free()

func prune_shared(uploads) -> void:
	if not _shared_dirty: return
	_shared_dirty = false
	var used: Dictionary = {}
	var slots: Dictionary = {}
	for cache in [unit_layers, item_layers]:
		for layer in cache.values():
			used[layer.get_meta("sprite_resource_key")] = true
			slots[layer.get_meta("sprite_slot")] = true
	for key in resources.keys():
		if not used.has(key): resources.erase(key)
	uploads.retain_regions(slots)

func reconcile(world, uploads, storage) -> Dictionary:
	var removed := {"units": 0, "items": 0}
	var current: int = world.sprite_resource_revision()
	if current == revision: return removed
	revision = current
	for entry in [[unit_layers, "units"], [item_layers, "items"]]:
		var cache: Dictionary = entry[0]
		for key in cache.keys():
			if not world.sprite_slot_valid(int(cache[key].get_meta("sprite_slot"))):
				remove(cache, key, uploads, storage)
				removed[entry[1]] += 1
	_shared_dirty = true
	prune_shared(uploads)
	return removed

func clear(uploads, storage) -> void:
	for cache in [unit_layers, item_layers]:
		for key in cache.keys(): remove(cache, key, uploads, storage)
	_shared_dirty = true
	prune_shared(uploads)
	revision = -1
