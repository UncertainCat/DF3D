extends SceneTree
var failures := 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	var world := Df3dWorld.new()
	root.add_child(world)
	check(world.load_assets(OS.get_environment("DF3D_DF_PATH")), "installed assets load")
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/item-updates.df3dfix")), "contents fixture loads")
	world.set_replay_speed(0)
	world.set_top_z(1)
	world.set_window_depth(2)
	var images: Array[PackedByteArray] = []
	var slots: Array[int] = []
	var position := Vector3.ZERO
	for frame in range(10,17):
		world.set_replay_elapsed(10.0 * frame + 5.0)
		world.poll()
		check(world.bridge_tick() == 100 + frame, "exact contents revision")
		var i: int = world.item_ids().find(600)
		check(i >= 0, "stationary bin remains present")
		if i < 0: continue
		var slot: int = world.item_sprite_slots()[i]
		check(slot >= 0, "container has resolved artwork")
		if slot < 0: continue
		var texture: Texture2D = world.sprite_texture(slot)
		var region: Color = world.item_sprite_regions()[i]
		var rect := Rect2i(roundi(region.r*texture.get_width()),roundi(region.g*texture.get_height()),roundi(region.b*texture.get_width()),roundi(region.a*texture.get_height()))
		images.append(texture.get_image().get_region(rect).get_data())
		slots.append(slot)
		if frame == 10: position=world.item_positions()[i]
		check(world.item_positions()[i] == position, "contents changes preserve physical placement")
		var revision: int = world.item_render_group_delta(-1).revision
		world.poll()
		check(world.item_render_group_delta(-1).revision == revision, "unchanged contents retain resident groups")
	if images.size() == 7:
		check(images[0] != images[1], "filling an empty bin changes its actual pixels")
		check(images[1] != images[2], "replacing contents changes its actual pixels")
		check(images[0] == images[3], "emptying restores the original artwork")
		check(slots[0] == slots[3], "returning to an observed state reuses its resource")
		check(images[4] != images[5], "dye-only changes recolor contents without replacing them")
		check(images[0] == images[6], "emptying clears the previous dye color")
	check(world.load_assets(OS.get_environment("DF3D_DF_PATH")), "asset replacement succeeds")
	for slot in slots: check(not world.sprite_slot_valid(slot), "asset replacement retires container resources")
	world.queue_free()
	await process_frame
	print("CONTAINER_CONTENTS_PASS" if failures == 0 else "CONTAINER_CONTENTS_FAIL")
	quit(failures)
