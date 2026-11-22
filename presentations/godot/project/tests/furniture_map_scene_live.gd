extends "res://tests/furniture_scene_live.gd"
func open_furniture(entry: Dictionary) -> bool:
	# Harness selection happens in the parent; product routes must work without it.
	OS.set_environment("DF3D_FURNITURE_RUNTIME","0")
	var tile:=Vector3i(entry.tile[0],entry.tile[1],entry.tile[2])
	scene._ui.focus_tile(tile)
	var camera=scene.camera_rig.get_node("Camera3D")
	var deadline:=Time.get_ticks_msec()+10000
	var point:=Vector2.ZERO
	var hit: Dictionary={}
	while Time.get_ticks_msec()<deadline:
		world.poll();await process_frame
		point=camera.unproject_position(Vector3(tile.x+0.5,tile.z+0.5,tile.y+0.5))
		hit=world.pick_building(camera.project_ray_origin(point),camera.project_ray_normal(point),world.get_top_z())
		if hit.get("tile",Vector3i(-1,-1,-1))==tile and not world.inspect_entity(3,int(entry.id)).is_empty():break
	if hit.get("tile",Vector3i(-1,-1,-1))!=tile:
		print("FURNITURE_MAP_MISS ",JSON.stringify({"expected":entry.id,"tile":str(tile),"point":str(point),"hit":hit,"entity":world.inspect_entity(3,int(entry.id)),"piece":scene._interaction._pick_piece(point)}))
		root.get_texture().get_image().save_png(directory+"/furniture-map-miss.png")
	# The visible hit may be an overlapping room/zone. DF selects the building;
	# verify its exact identity after the real pointer event below.
	if not check(hit.get("tile",Vector3i(-1,-1,-1))==tile,"Furniture map ray missed tile for "+str(entry.id)):return false
	await pointer(point);key(KEY_ESCAPE);await drain()
	if scene._ui.host.active!=null or scene._ui.tile_selection==null or scene._ui.tile_selection.navigation.state.ticket!=0:
		print("FURNITURE_ESCAPE_STATE ",JSON.stringify({"active":str(scene._ui.host.active),"tile_selection":str(scene._ui.tile_selection),"ticket":scene._ui.tile_selection.navigation.state.ticket if scene._ui.tile_selection!=null else -1,"piece":scene._interaction._pick_piece(point),"actions_active":actions._active,"queued":actions._queue.size()}))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/furniture-escape-state.png")
	if not check(scene._ui.host.active==null and scene._ui.tile_selection!=null and scene._ui.tile_selection.navigation.state.ticket==0,"Escape retained furniture selection request"):return false
	print("FURNITURE_MAP_PICK ",entry.id," ",scene._interaction._pick_piece(point))
	await pointer(point);await drain()
	if scene._ui.host.active!=owner and scene._ui.tile_selection!=null:
		var tabs=scene._ui.tile_selection.tabs
		var index: int=tabs.alternatives.find_custom(func(row):return row.kind==C.SelectionKind.Building and row.id==int(entry.id))
		if not check(index>=0,"Native selection omitted the covered building alternative"):return false
		await pointer(tabs.get_global_transform_with_canvas()*Vector2(24,index*36+18));await drain()
	if not await chest_ready():return false
	return check(owner.state.building_id==int(entry.id),"Map click selected the wrong furniture")
