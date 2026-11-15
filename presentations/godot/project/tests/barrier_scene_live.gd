extends "res://tests/furniture_scene_live.gd"
func expected_filename() -> String:return "barrier-wire-expected.json"
func result_filename() -> String:return "barrier-scene-result.json"
func open_furniture(entry: Dictionary) -> bool:
	var tile:=Vector3i(entry.tile[0],entry.tile[1],entry.tile[2])
	scene._ui.focus_tile(tile)
	var camera=scene.camera_rig.get_node("Camera3D")
	var point:=Vector2.ZERO
	var hit: Dictionary={}
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		point=camera.unproject_position(Vector3(tile.x+0.5,tile.z+0.5,tile.y+0.5))
		hit=world.pick_building(camera.project_ray_origin(point),camera.project_ray_normal(point),world.get_top_z())
		if hit.get("tile",Vector3i(-1,-1,-1))==tile and not world.inspect_entity(3,int(entry.id)).is_empty():break
	if not check(hit.get("tile",Vector3i(-1,-1,-1))==tile,"Projected ray missed barrier"):return false
	print("BARRIER_MAP_PICK ",JSON.stringify({"id":entry.id,"tile":str(tile),"point":str(point),"hit":hit,"entity":world.inspect_entity(3,int(entry.id)),"piece":scene._interaction._pick_piece(point)}))
	await pointer(point)
	await drain()
	print("BARRIER_MAP_OWNER ",scene._ui.host.active," selection=",scene._ui.tile_selection.navigation.state.snapshot if scene._ui.tile_selection!=null else {})
	if not await chest_ready():return false
	return true
func access_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if owner.access.phase==owner.access.Phase.Ready:return true
		await create_timer(0.01).timeout
	return check(false,"Hatch access controls not Ready")
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	for entry in expected.buildings:
		if not await open_furniture(entry):return
		if int(entry.type)==35 and not await access_ready():return
		await panel_capture("barrier-"+str(int(entry.type)),"barrier-sheet-"+str(int(entry.type)))
		if int(entry.type)==35:
			for forbidden in [true,false]:
				await pointer(Vector2(852 if forbidden else 876,154))
				if not await access_ready():return
				check(owner.access.snapshot.forbidden==forbidden,"Hatch pointer did not change access")
				var label: String="barrier-hatch-forbidden" if forbidden else "barrier-hatch-passable"
				await panel_capture(label,label)
		var prefix: String="barrier-sheet-"+str(int(entry.type))
		if not await rename_to(entry.custom_name+"x"):return
		await panel_capture(prefix+"-renamed",prefix+"-renamed")
		if not await rename_to(entry.custom_name):return
		await panel_capture(prefix+"-restored",prefix+"-restored")
		await pointer(Vector2(832,82));if not await chest_ready():return
		check(owner.state.snapshot.removing,"Barrier removal failed")
		await panel_capture(prefix+"-removing",prefix+"-removing")
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
		if not await chest_ready():return
		check(not owner.state.snapshot.removing,"Barrier removal not cancelled")
		await panel_capture(prefix+"-removal-cancelled",prefix+"-removal-cancelled")
		key(KEY_ESCAPE);await drain()
		scene._ui.open_building_holder(int(entry.type),int(entry.id))
		if not await chest_ready():return
		check(owner.state.building_id==int(entry.id),"Barrier holder opened wrong building")
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null,"Barrier retained ownership")
	exercised=true
