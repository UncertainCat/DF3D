extends SceneTree

func _initialize() -> void:
	var view = preload("res://scripts/world_view.gd").new()
	# This isolated harness never enters _ready(), which normally parents these
	# eagerly-created presentation nodes. Give them the same teardown owner.
	view.add_child(view._projectiles)
	view.add_child(view._unit_status)
	view.world = Df3dWorld.new()
	view.add_child(view.world)
	# Item and actor partition controls are independent. A camera/actor grouping
	# choice must not trigger native item ownership work.
	assert(view._spatial_items and not view._spatial_sprites)
	view.configure_item_batches(true, 16, 1)
	var item_revision: int = view.world.item_render_revision()
	view.configure_unit_batches(true, 32, 4)
	assert(view.world.item_render_revision() == item_revision)
	assert(view._item_cell_xy == 16 and view._item_cell_z == 1)
	view._unit_revision_seen = 77
	view.configure_item_batches(false, 8, 4)
	assert(view._unit_revision_seen == 77)
	assert(view._sprite_cell_xy == 32 and view._sprite_cell_z == 4)
	assert(view.world.item_render_revision() > item_revision)
	item_revision = view.world.item_render_revision()
	view.configure_item_batches(false, 8, 4)
	assert(view.world.item_render_revision() == item_revision)
	view.configure_sprite_batches(true, 16, 1)
	view._spatial_sprites = true
	# Finalized Godot coordinates: horizontal X/Z, vertical Y. Floor, not
	# truncation, keeps cells correct across zero and all boundaries.
	assert(view._sprite_cell(Vector3(-0.01, -0.01, -0.01)) == Vector3i(-1,-1,-1))
	assert(view._sprite_cell(Vector3(15.99,0.99,15.99)) == Vector3i.ZERO)
	assert(view._sprite_cell(Vector3(16,1,16)) == Vector3i(1,1,1))
	view._sprite_cell_xy = 32
	view._sprite_cell_z = 4
	assert(view._sprite_cell(Vector3(31.99,3.99,31.99)) == Vector3i.ZERO)
	assert(view._sprite_cell(Vector3(32,4,32)) == Vector3i.ONE)
	var region := Color(0.1,0.2,0.3,0.4)
	assert(view._sprite_batch_key(2,region,Vector3i.ZERO) != view._sprite_batch_key(2,region,Vector3i.ONE))
	assert(view._sprite_batch_key(2,region,Vector3i.ZERO) != view._sprite_batch_key(3,region,Vector3i.ZERO))
	# Test resource sharing without loading or distributing game art.
	var mesh := ArrayMesh.new()
	var material := ShaderMaterial.new()
	var resource_key: String = "item:" + view._instance_uploads.region_key(2,region)
	view._cutout_resources[resource_key] = [mesh,material]
	var a = view._cutout_layer(2,region,view._sprite_layers,view._sprite_batch_key(2,region,Vector3i.ZERO))
	var b = view._cutout_layer(2,region,view._sprite_layers,view._sprite_batch_key(2,region,Vector3i.ONE))
	var c = view._cutout_layer(2,region,view._item_layers,view._sprite_batch_key(2,region,Vector3i.ONE))
	assert(a != b and b != c)
	assert(a.multimesh.mesh == b.multimesh.mesh and b.multimesh.mesh == c.multimesh.mesh)
	assert(a.material_override == b.material_override and b.material_override == c.material_override)
	# Leave engine-generated bounds intact: they include the complete transformed
	# contour (upright style, north spill and current interpolated motion).
	assert(a.multimesh.custom_aabb == AABB())
	view._spatial_sprites = false
	assert(view._sprite_cell(Vector3(999,-99,123)) == Vector3i.ZERO)
	view.free()
	print("SPATIAL_SPRITE_PASS")
	quit()
