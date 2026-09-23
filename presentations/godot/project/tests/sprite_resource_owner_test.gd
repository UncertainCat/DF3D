extends SceneTree
const Owner = preload("res://scripts/sprite_resource_owner.gd")
const Uploads = preload("res://scripts/instance_upload_cache.gd")
const Storage = preload("res://scripts/item_instance_storage.gd")
class FakeWorld:
	extends RefCounted
	var revision := 0
	var slots: Dictionary = {}
	func sprite_resource_revision() -> int: return revision
	func sprite_slot_valid(slot: int) -> bool: return slots.has(slot)
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func layer(owner, cache: Dictionary, key: String, slot: int, uploads, storage) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.mesh = BoxMesh.new()
	node.multimesh.instance_count = 1
	root.add_child(node)
	var resource: String = uploads.region_key(slot, Color(0, 0, 1, 1))
	if not owner.resources.has(resource):
		owner.resources[resource] = [node.multimesh.mesh, StandardMaterial3D.new()]
	node.multimesh.mesh = owner.resources[resource][0]
	node.material_override = owner.resources[resource][1]
	owner.track(node, slot, resource)
	cache[key] = node
	uploads.begin(node.multimesh)
	storage._resident[node.multimesh.get_instance_id()] = {"owner": RefCounted.new(), "version": 1}
	return node
func run():
	var owner := Owner.new()
	var uploads := Uploads.new()
	var storage := Storage.new()
	var world := FakeWorld.new()
	world.slots[1] = true
	var hidden := layer(owner, owner.unit_layers, "hidden", 1, uploads, storage)
	hidden.hide()
	owner.reconcile(world, uploads, storage)
	for slot in range(2, 102):
		world.slots[slot] = true
		layer(owner, owner.item_layers, "current", slot, uploads, storage)
		var material: WeakRef = weakref(owner.item_layers.current.material_override)
		check(owner.resources.size() == 2, "one changing appearance and one hidden live owner retain two shared resources")
		world.slots.erase(slot)
		world.revision += 1
		var retired: Dictionary = owner.reconcile(world, uploads, storage)
		check(retired.items == 1 and retired.units == 0, "only dead handles retire")
		check(owner.resources.size() == 1 and owner.item_layers.is_empty(), "retired appearances release scene and shared ownership")
		check(material.get_ref() == null, "retired material is released, not merely removed from diagnostics")
		check(uploads._layers.size() == 1 and uploads._region_keys.size() == 1 and storage._resident.size() == 1, "auxiliary storage remains bounded during churn")
		check(owner.unit_layers.hidden == hidden and not hidden.visible, "hidden live group survives retirement")
		await process_frame
	# A shared material survives until its final scene owner leaves.
	layer(owner, owner.item_layers, "shared", 1, uploads, storage)
	owner.remove(owner.unit_layers, "hidden", uploads, storage)
	owner.prune_shared(uploads)
	check(owner.resources.size() == 1 and owner.item_layers.size() == 1, "one remaining group retains shared art")
	owner.remove(owner.item_layers, "shared", uploads, storage)
	owner.prune_shared(uploads)
	check(owner.resources.is_empty() and uploads._region_keys.is_empty() and storage._resident.is_empty(), "actual group removal retires live-slot resources too")
	layer(owner, owner.unit_layers, "reset", 1, uploads, storage)
	owner.clear(uploads, storage)
	check(owner.unit_layers.is_empty() and owner.item_layers.is_empty() and owner.resources.is_empty(), "explicit reset releases every owner")
	await process_frame
	print("SPRITE_RESOURCE_OWNER_TEST ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
