extends "res://tests/pending_selection_scene_live.gd"
func enter_selection(tile: Vector3i,id: int) -> bool:
	var camera=scene.camera_rig.get_node("Camera3D")
	var deadline:=Time.get_ticks_msec()+10000
	var point:=Vector2.ZERO
	var hit: Dictionary={}
	while Time.get_ticks_msec()<deadline:
		world.poll();await process_frame
		point=camera.unproject_position(Vector3(tile.x+0.5,tile.z+0.5,tile.y+0.5))
		hit=world.pick_building(camera.project_ray_origin(point),camera.project_ray_normal(point),world.get_top_z())
		if hit.get("id",-1)==id:break
	if not check(hit.get("id",-1)==id,"Pending map ray did not hit building "+str(id)):return false
	await pointer(point)
	await key(KEY_ESCAPE);await drain()
	if not check(scene._ui.host.active==null and scene._ui.tile_selection!=null and scene._ui.tile_selection.navigation.state.ticket==0,"Escape retained pending map selection"):return false
	var picked: Dictionary=scene._interaction._pick_piece(point)
	print("PENDING_MAP_PICK ",id," point=",point," picked=",picked," info=",world.inspect_entity(3,id))
	await pointer(point)
	await drain()
	print("PENDING_MAP_STATE ",id," phase=",scene._ui.tile_selection.navigation.state.phase," snapshot=",scene._ui.tile_selection.navigation.state.snapshot," tabs=",scene._ui.tile_selection.tabs.alternatives," owner=",scene._ui.host.active)
	return true
