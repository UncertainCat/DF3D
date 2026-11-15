extends "res://tests/furniture_scene_live.gd"
func expected_filename() -> String:return "trap-sheet-expected.json"
func result_filename() -> String:return OS.get_environment("DF3D_DOOR_CAPTURE")+"-result.json"
func chest_ready() -> bool:
	if not await super.chest_ready():return false
	var deadline:=Time.get_ticks_msec()+10000
	while owner.links.phase==owner.links.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		await create_timer(0.01).timeout
	return check(owner.links.phase==owner.links.Phase.Ready,"Trap links did not reach Ready")
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	var tile:=Vector3i(expected.tile[0],expected.tile[1],expected.tile[2])
	scene._ui.focus_tile(tile)
	var camera=scene.camera_rig.get_node("Camera3D")
	var point:=Vector2.ZERO
	var hit: Dictionary={}
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		point=camera.unproject_position(Vector3(tile.x+0.5,tile.z+0.5,tile.y+0.5))
		hit=world.pick_building(camera.project_ray_origin(point),camera.project_ray_normal(point),world.get_top_z())
		if hit.get("tile",Vector3i(-1,-1,-1))==tile and not world.inspect_entity(3,int(expected.id)).is_empty():break
	if not check(hit.get("tile",Vector3i(-1,-1,-1))==tile,"Projected ray missed trap"):return
	await pointer(point)
	if not await chest_ready():return
	key(KEY_ESCAPE);await process_frame
	if not check(scene._ui.host.active==null,"Escape retained trap panel"):return
	await pointer(point)
	if not await chest_ready():return
	if expected.get("observe_only",false):
		await panel_capture(expected.reference,expected.reference)
		owner.close_panel();await process_frame;exercised=true;return
	var prefix: String="trap-sheet-"+str(int(expected.subtype))
	await panel_capture(prefix,prefix)
	if not await rename_to(expected.name+"x"):return
	await panel_capture(prefix+"-renamed",prefix+"-renamed")
	if not await rename_to(expected.name):return
	await panel_capture(prefix+"-restored",prefix+"-restored")
	await pointer(Vector2(796,562));if not await chest_ready():return
	check(owner.contents.rows()[0].forbid!=expected.original_forbid,"Trap item Forbid failed")
	await panel_capture(prefix+"-forbid",prefix+"-forbid")
	await pointer(Vector2(796,562));if not await chest_ready():return
	check(owner.contents.rows()[0].forbid==expected.original_forbid,"Trap item Forbid not restored")
	await pointer(Vector2(540,520));await panel_capture(prefix+"-links",prefix+"-links")
	await pointer(Vector2(720,520))
	await pointer(Vector2(832,82));if not await chest_ready():return
	check(owner.state.snapshot.removing,"Trap removal failed")
	await panel_capture(prefix+"-removing",prefix+"-removing")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
	if not await chest_ready():return
	check(not owner.state.snapshot.removing,"Trap removal was not cancelled")
	await panel_capture(prefix+"-removal-cancelled",prefix+"-removal-cancelled")
	owner.close_panel();await process_frame
	check(scene._ui.host.active==null,"Trap close retained owner");exercised=true
