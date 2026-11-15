extends "res://tests/item_carrier_wire_live.gd"
var scene
var actions
var owner
var exercised:=false
func pointer(point: Vector2,button:=MOUSE_BUTTON_LEFT) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=button;event.pressed=pressed;root.push_input(event,true)
	await process_frame
func key(code: int,unicode:=0) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.unicode=unicode;event.pressed=pressed;root.push_input(event,true)
func settle(model) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if model.phase not in [model.Phase.Reading,model.Phase.Applying]:break
		await create_timer(0.01).timeout
	return check(model.phase==model.Phase.Ready,"Main-scene model did not reach Ready")
func chest_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready:
			return check(scene._ui.host.active==owner and owner.panel.visible,"Chest does not own active panel")
		if owner.state.phase in [owner.state.Phase.Rejected,owner.state.Phase.Stale,owner.state.Phase.Unknown,owner.state.Phase.Unavailable] or owner.contents.phase in [owner.contents.Phase.Rejected,owner.contents.Phase.Stale,owner.contents.Phase.Unknown,owner.contents.Phase.Unavailable]:break
		await create_timer(0.01).timeout
	return check(false,"Chest header and contents did not both reach Ready: header="+str(owner.state.phase)+" contents="+str(owner.contents.phase)+" transport="+world.last_error()+" receipt="+JSON.stringify(world.poll_management().get("production",{})))
func drain() -> void:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if actions._active==0 and actions._queue.is_empty():return
		await create_timer(0.01).timeout
	check(false,"Main-scene action drain timed out; no replay")
func panel_capture(label: String,reference: String) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,400);root.push_input(motion,true)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var crop:=image.get_region(Rect2i(416,52,488,708));crop.save_png(directory+"/chest-scene-"+label+".png")
	var native:=Image.load_from_file(directory+"/"+reference+".png");native.convert(Image.FORMAT_RGB8)
	check(crop.get_data()==native.get_region(Rect2i(416,52,488,708)).get_data(),"Main-scene chest pixels differ: "+label)
func resize_capture(label: String) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2.ZERO;root.push_input(motion,true)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var region:=Rect2i(Vector2i(owner.panel.position),Vector2i(owner.panel.size))
	var crop:=image.get_region(region);crop.save_png(directory+"/chest-scene-resize-"+label+".png")
	var native:=Image.load_from_file(directory+"/chest-resize-"+label+".png");native.convert(Image.FORMAT_RGB8)
	check(crop.get_data()==native.get_region(region).get_data(),"Chest resize pixels differ at "+label)
func expected_filename() -> String:return "chest-header-expected.json"
func result_filename() -> String:return "chest-scene-result.json"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	OS.set_environment("DF3D_FIXTURE","")
	var prefs=preload("res://scripts/presentation_settings.gd");prefs.loaded=true;prefs.ui_scale=1.0;prefs.camera_mode="df"
	root.size=Vector2i(1200,800)
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/"+expected_filename()))
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);world=scene.world
	var deadline:=Time.get_ticks_msec()+60000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	if check(scene._loader.entered,"Main scene did not enter fortress"):
		actions=scene._ui.actions;actions.set_process(false)
		await exercise(expected)
	check(exercised,"Main-scene workflow did not reach final cleanup")
	var file:=FileAccess.open(directory+"/"+result_filename(),FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"surface":"actual main scene","roundtrip":true}));file.close()
	scene.queue_free();await process_frame
	if not failed:print("CHEST_SCENE_PASS")
	quit(1 if failed else 0)
func exercise(expected: Dictionary) -> void:
	var farm=scene._ui.controller("farm")
	farm.item_owner.open_target(5834)
	if not await settle(farm.item_owner.state):return
	await pointer(farm.item_owner.panel.get_global_transform_with_canvas()*farm.item_owner.panel.holder_rect().get_center())
	owner=scene._ui.controller("chest")
	if not await chest_ready():return
	check(owner.state.building_id==int(expected.snapshot.id) and not farm.panel.visible,"Box holder routed to wrong owner")
	await panel_capture("initial","chest-header-wire-idle")
	for sample in [["small",Vector2i(960,600),0],["medium",Vector2i(1200,720),4],["wide",Vector2i(1600,900),9],["default",Vector2i(1200,800),6]]:
		root.size=sample[1]
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		check(owner.panel.contents.page==sample[2],"Chest contents capacity differs at "+sample[0])
		await resize_capture(sample[0])
		if sample[0]=="medium":
			for index in 3:await pointer(owner.panel.contents.get_global_transform_with_canvas()*Vector2(200,18),MOUSE_BUTTON_WHEEL_DOWN)
			if not await chest_ready():return
			check(owner.panel.contents.cell_first==3,"Chest wheel did not reach next item")
			await resize_capture("medium-scrolled")
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(384,30))
	check(owner.panel.name_entry.editing,"Main-scene Rename did not start")
	for character in "scene chest":key(0,character.unicode_at(0))
	key(KEY_ESCAPE);await drain()
	check(scene._ui.host.active==null and not owner.panel.visible,"Escape did not close typing panel")
	owner.open_target(int(expected.snapshot.id))
	if not await chest_ready():return
	check(owner.state.snapshot.custom_name=="scene chest","Closing lost typed name")
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(384,30))
	for index in 30:key(KEY_BACKSPACE)
	for character in String(expected.snapshot.custom_name):key(0,character.unicode_at(0))
	key(KEY_ENTER)
	if not await chest_ready():return
	check(not owner.panel.name_entry.editing and owner.state.snapshot.custom_name==expected.snapshot.custom_name,"Enter did not finish restored name")
	scene._fortress_hud.toggle_game_menu();await process_frame
	check(scene._ui.host.overlay_blocked,"HUD overlay did not block input")
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(416,30));await drain()
	check(not owner.state.snapshot.removing,"Overlay allowed header edit")
	scene._fortress_hud.close_menus();await process_frame
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(416,30))
	if not await chest_ready():return
	check(owner.state.snapshot.removing and owner.contents.snapshot.removing and owner.panel.contents.visible,"Removal hid chest contents")
	await panel_capture("removing","chest-header-remove")
	# Native oracle verifies these controls on installed Box and contained instrument
	# while removal is queued. Drive the real contents owner and viewport here.
	for row_index in 2:
		for entry in [[2,"forbid"],[3,"dump"],[5,"hidden"]]:
			var initial_flag: bool=owner.contents.snapshot.rows[row_index][entry[1]]
			for desired in [not initial_flag,initial_flag]:
				await pointer(owner.panel.contents.get_global_transform_with_canvas()*owner.panel.contents.control_rect(row_index,entry[0]).get_center())
				if not await chest_ready():return
				check(owner.contents.snapshot.rows[row_index][entry[1]]==desired,"Pending-removal contents edit differs: "+entry[1])
				check(owner.state.snapshot.removing and owner.contents.snapshot.removing,"Contents edit lost removal state")
	var contents=owner.panel.contents
	await pointer(contents.get_global_transform_with_canvas()*contents.control_rect(0,1).get_center())
	if not await settle(owner.item_owner.state):return
	check(scene._ui.host.active==owner.item_owner and not owner.panel.visible and owner.item_owner.state.item_id==5834,"Contents View did not hand off input")
	await pointer(owner.item_owner.panel.get_global_transform_with_canvas()*owner.item_owner.panel.holder_rect().get_center())
	if not await chest_ready():return
	check(owner.state.snapshot.removing,"Holder return lost pending removal")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
	if not await chest_ready():return
	check(not owner.state.snapshot.removing,"Main-scene cancellation failed")
	await panel_capture("restored","chest-header-wire-idle")
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(100,200),MOUSE_BUTTON_RIGHT)
	check(scene._ui.host.active==null and not owner.panel.visible,"Right-click did not release chest input")
	exercised=true
