extends SceneTree
const Probe = preload("res://scripts/item_upload_probe.gd")
func _initialize() -> void:
	var probe = Probe.new()
	probe.enabled = true
	probe.begin({"transforms_written": 0})
	for i in 100:
		probe.group_selection({"key": i, "slot": 1, "indices": PackedInt32Array([1, 2]),
			"changed_indices": PackedInt32Array([1]), "base_revision": 5, "revision": 6}, 5, false, true)
	assert(probe.row.group_examples.size() == 6 and probe.row.selection_reasons.sparse == 100)
	var patch = preload("res://scripts/item_preparation.gd").Patch.new()
	patch.group = preload("res://scripts/item_preparation.gd").Group.new()
	patch.group.transforms.resize(3)
	patch.transforms = PackedInt32Array([0, 2])
	probe.prepared(patch)
	assert(probe.row.prepared_transforms == 2 and probe.row.largest_changed_group == 3)
	assert(probe.row.groups == 100 and probe.row.changed_groups == 1)
	probe.finish({"transforms_written": 102})
	assert(probe.summary()[0].work.transforms_written == 102)
	probe.enabled = false
	probe.begin({})
	probe.prepared(patch)
	assert(probe.row.is_empty())
	assert(load("res://scripts/world_view.gd") != null)
	print("ITEM_UPLOAD_PROBE_PASS")
	quit()
