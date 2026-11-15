extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "workshop-native.json"
func result_filename() -> String:return "workshop-wire-result.json"

func door_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready and owner.door.phase==owner.door.Phase.Ready:return true
		await create_timer(0.01).timeout
	return check(false,"Door sheet failed to load header, contents and controls")

func exercise(expected: Dictionary) -> void:
	var sample: Dictionary=expected.basic_building_reference.door
	var id:=int(sample.id)
	scene._ui.focus_tile(Vector3i(sample.tile[0],sample.tile[1],sample.tile[2]))
	owner=scene._ui.controller("door")
	if OS.get_environment("DF3D_DOOR_MAP_RUNTIME")=="1":
		var camera=scene.camera_rig.get_node("Camera3D")
		var deadline:=Time.get_ticks_msec()+10000
		var point:=Vector2.ZERO
		var hit: Dictionary={}
		while Time.get_ticks_msec()<deadline:
			world.poll();await process_frame
			point=camera.unproject_position(Vector3(sample.tile[0]+0.5,sample.tile[2]+0.5,sample.tile[1]+0.5))
			hit=world.pick_building(camera.project_ray_origin(point),camera.project_ray_normal(point),world.get_top_z())
			if hit.get("id",-1)==id:break
		if not check(hit.get("id",-1)==id,"Door map ray did not hit the expected building"):return
		await pointer(point)
		key(KEY_ESCAPE);await drain()
		if not check(scene._ui.host.active==null and scene._ui.tile_selection.navigation.state.ticket==0,"Escape retained a pending map selection"):return
		await pointer(point)
	elif OS.get_environment("DF3D_DOOR_SELECTION_RUNTIME")=="1":
		var deadline:=Time.get_ticks_msec()+10000
		while world.inspect_entity(3,id).is_empty() and Time.get_ticks_msec()<deadline:
			world.poll();await create_timer(0.01).timeout
		scene._ui.open_tile_selection(Vector3i(sample.tile[0],sample.tile[1],sample.tile[2]))
	else:scene._ui.open_building_holder(8,id)
	if not await door_ready():return
	check(scene._ui.host.active==owner and owner.state.building_id==id,"Door route did not own the selected target")
	for probe in [[Vector2(800,82),"building_rename"],[Vector2(852,154),""],[Vector2(876,154),""],[Vector2(832,82),"building_remove"]]:
		var motion:=InputEventMouseMotion.new();motion.position=probe[0];root.push_input(motion,true)
		await create_timer(0.9).timeout
		var help=scene._fortress_hud.native_help
		check((not help.visible) if probe[1]=="" else (help.visible and help.displayed==probe[1]),"Door hover differs: "+probe[1])
	var away:=InputEventMouseMotion.new();away.position=Vector2.ZERO;root.push_input(away,true);await process_frame
	await panel_capture("door-idle","workshop-basic-building-door")
	for locked in [true,false]:
		await pointer(Vector2(852 if locked else 876,154))
		if not await door_ready():return
		check(owner.door.snapshot.forbidden==locked,"Door click did not change native permission")
		await panel_capture("door-locked" if locked else "door-passable","workshop-basic-building-door-lock" if locked else "workshop-basic-building-door-passable")
	await pointer(Vector2(800,82))
	for character in "Door reference":key(0,character.unicode_at(0))
	key(KEY_ENTER)
	if not await door_ready():return
	check(owner.state.snapshot.custom_name=="Door reference","Door rename did not reach native header")
	await panel_capture("door-renamed","workshop-door-header-renamed")
	# Clear through the same native-style name entry before testing removal.
	await pointer(Vector2(800,82))
	for i in 30:key(KEY_BACKSPACE)
	key(KEY_ENTER)
	if not await door_ready():return
	for locked in [false,true]:
		await pointer(Vector2(852 if locked else 876,154))
		if not await door_ready():return
		await pointer(Vector2(832,82))
		if not await settle(owner.state):return
		if not await settle(owner.contents):return
		check(owner.state.snapshot.removing and not owner.panel.door_controls.visible,"Removal retained door controls")
		await panel_capture("door-remove-"+str(locked),"workshop-door-header-remove-"+str(locked))
		await pointer(Vector2(520,202))
		if not await door_ready():return
		check(not owner.state.snapshot.removing and not owner.door.snapshot.forbidden,"Door cancellation did not preserve native passable result")
		await panel_capture("door-cancel-"+str(locked),"workshop-door-header-cancel-"+str(locked))
	key(KEY_ESCAPE);await process_frame
	check(owner.state.building_id==-1 and owner.door.building_id==-1 and scene._ui.host.active==null,"Door close retained panel authority")
	exercised=true
