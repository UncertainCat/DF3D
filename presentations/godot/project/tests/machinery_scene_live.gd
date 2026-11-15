extends "res://tests/furniture_scene_live.gd"
func expected_filename() -> String:return "machinery-wire-expected.json"
func result_filename() -> String:return "machinery-scene-result.json"
func open_furniture(entry: Dictionary) -> bool:
	if OS.get_environment("DF3D_MACHINERY_WORKFLOW")!="1":return await super.open_furniture(entry)
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
	if not check(hit.get("tile",Vector3i(-1,-1,-1))==tile,"Projected ray missed machinery"):return false
	print("MACHINERY_MAP_PICK ",JSON.stringify({"id":entry.id,"tile":str(tile),"point":str(point),"hit":hit,"entity":world.inspect_entity(3,int(entry.id)),"piece":scene._interaction._pick_piece(point)}))
	await pointer(point)
	await drain()
	print("MACHINERY_MAP_OWNER ",scene._ui.host.active," selection=",scene._ui.tile_selection.navigation.state.snapshot if scene._ui.tile_selection!=null else {})
	if not await chest_ready():return false
	key(KEY_ESCAPE);await drain()
	scene._ui.open_building_holder(int(entry.type),int(entry.id))
	return await chest_ready()
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	for entry in expected.buildings:
		if int(entry.type)==13:continue
		if not await open_furniture(entry):return
		await panel_capture("machinery-"+str(int(entry.type)),"machinery-sheet-"+str(int(entry.type)))
		if OS.get_environment("DF3D_MACHINERY_WORKFLOW")=="1":
			var prefix: String="machinery-sheet-"+str(int(entry.type))
			if not await rename_to(entry.name+"x"):return
			await panel_capture(prefix+"-renamed",prefix+"-renamed")
			if not await rename_to(entry.name):return
			await panel_capture(prefix+"-restored",prefix+"-restored")
			await pointer(Vector2(832,82));if not await chest_ready():return
			check(owner.state.snapshot.removing,"Machinery removal failed")
			await panel_capture(prefix+"-removing",prefix+"-removing")
			await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
			if not await chest_ready():return
			check(not owner.state.snapshot.removing,"Machinery removal not cancelled")
			await panel_capture(prefix+"-removal-cancelled",prefix+"-removal-cancelled")
		if int(entry.type)==33:
			for step in [1,2]:
				await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.pump_rect().get_center())
				if not await chest_ready():return
				check(owner.state.snapshot.machinery.pump_manual==(1 if step==1 else 0),"Pump gesture did not change native flag")
				await panel_capture("machinery-pump-"+str(step),"machinery-pump-manual-"+str(step))
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null,"Machinery retained panel ownership")
	exercised=true
