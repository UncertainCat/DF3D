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
	owner=scene._ui.controller("door");scene._ui.open_building_holder(8,id)
	if not await door_ready():return
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
