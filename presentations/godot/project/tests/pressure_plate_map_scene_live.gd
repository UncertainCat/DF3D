extends "res://tests/lever_map_scene_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	OS.set_environment("DF3D_FIXTURE","")
	var prefs=preload("res://scripts/presentation_settings.gd");prefs.loaded=true;prefs.ui_scale=1.0;prefs.camera_mode="df"
	root.size=Vector2i(1200,800)
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/pressure-plate-wire-expected.json"))
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);world=scene.world
	var deadline:=Time.get_ticks_msec()+30000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	if check(scene._loader.entered,"Main scene did not enter fortress"):await exercise(expected)
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed and exercised,"surface":"actual main scene plate Connections and Link", "pull_job":applied_jobs.get(2,-1),"link_job":applied_jobs.get(3,-1)}));file.close()
	scene.queue_free();await process_frame;quit(1 if failed else 0)
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("pressure_plate")
	owner.lever.applied.connect(func(operation,id):applied_jobs[operation]=id)
	var source_tile:=Vector3i(expected.source_tile[0],expected.source_tile[1],expected.source_tile[2])
	scene._ui.focus_tile(source_tile)
	owner.open_target(61)
	if not await ready_jobs(0):return
	if OS.get_environment("DF3D_PRESSURE_PLATE_ITEM_NAV")=="1":await item_navigation()
	if OS.get_environment("DF3D_PRESSURE_PLATE_CONNECTIONS")=="1":await connection_gestures()
	if failed:return
	var tile:=Vector3i(expected.x,expected.y,expected.z)
	scene._ui.focus_tile(tile)
	await pointer(Vector2(744,154))
	var deadline:=Time.get_ticks_msec()+10000
	while not owner.lever.view.visible and Time.get_ticks_msec()<deadline:await process_frame
	if not check(owner.lever.view.visible and not owner.panel.visible and scene._ui.host.active==owner,"Plate Link did not retain input ownership"):return
	var camera=scene.camera_rig.get_node("Camera3D")
	var point:=Vector2.ZERO
	var picked:=Vector3i(-1,-1,-1)
	deadline=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		point=camera.unproject_position(Vector3(tile.x+0.5,tile.z+0.5,tile.y+0.5))
		picked=world.pick_tile(camera.project_ray_origin(point),camera.project_ray_normal(point),world.get_top_z())
		if picked==tile:break
	if not check(picked==tile,"Plate Link ray missed target"):return
	await pointer(point)
	if not await ready_jobs(1):return
	check(applied_jobs.has(3) and owner.panel.visible and not owner.lever.view.visible and not owner.modal_input,"Plate map Link did not apply and restore panel")
	owner.close_panel();await process_frame
	check(scene._ui.host.active==null,"Plate close retained owner")
	exercised=true
func connections_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if owner.connections.phase==owner.connections.Phase.Ready:return true
	return check(false,"Plate Connections did not become Ready: "+str(owner.connections.phase))
func connection_capture(label: String,height: int) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(400,500);root.push_input(motion,true)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/pressure-plate-connections-"+label+".png");native.convert(Image.FORMAT_RGB8)
	var rect:=Rect2i(56,52,328,height);var crop:=image.get_region(rect)
	crop.save_png(directory+"/pressure-plate-connections-"+label+"-viewer.png")
	check(crop.get_data()==native.get_region(rect).get_data(),"Plate Connections pixels differ: "+label)
func connection_gestures() -> void:
	var native: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/pressure-plate-native.json"))
	var point: Dictionary=native.connections.pile_tile
	var tile:=Vector3i(point.x,point.y,point.z)
	scene._ui.focus_tile(tile)
	await pointer(Vector2(768,82))
	if not await connections_ready():return
	await connection_capture("open",420)
	for entry in [["give",80,1],["take",112,2]]:
		await pointer(Vector2(entry[1],82))
		check(owner.connections.picking and not owner.panel.visible,"Connections picker did not hide plate")
		await connection_capture(entry[0],120)
		await pointer(Vector2(328,82))
		if not await connections_ready():return
		check(owner.panel.visible,"Connections Cancel did not restore plate")
		await pointer(Vector2(entry[1],82))
		for i in 15:await process_frame
		var position: Vector2=owner.camera.unproject_position(Vector3(tile.x+0.5,tile.z+float(world.floor_height()),tile.y+0.5))
		if not check(world.pick_tile(owner.camera.project_ray_origin(position),owner.camera.project_ray_normal(position),world.get_top_z())==tile,"Connections map ray missed pile"):return
		await pointer(position)
		if not await connections_ready():return
		check(owner.connections.rows.size()==1 and owner.connections.rows[0].id==int(native.connections.pile_id) and owner.connections.rows[0].direction==entry[2],"Connections link differs from native")
		await connection_capture("linked-"+entry[0],420)
		await pointer(Vector2(352,154))
		if not await connections_ready():return
		check(owner.connections.rows.is_empty(),"Connections Remove retained link")
		await connection_capture("unlinked-"+entry[0],420)
	await pointer(Vector2(328,82));await process_frame
	check(not owner.connections_view.visible and owner.panel.visible and not owner.modal_input,"Connections Done retained modal input")

func item_navigation() -> void:
	var item_id: int=owner.contents.rows()[0].id
	await pointer(owner.panel.contents.get_global_transform_with_canvas()*owner.panel.contents.control_rect(0,1).get_center())
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline and owner.item_owner.state.phase!=owner.item_owner.state.Phase.Ready:await process_frame
	if not check(owner.item_owner.state.phase==owner.item_owner.state.Phase.Ready and scene._ui.host.active==owner.item_owner,"Plate item did not open"):return
	check(owner.item_owner.state.item_id==item_id and owner.item_owner.state.snapshot.get("holder",{}).get("id",-1)==61,"Plate item holder differs")
	await lever_capture("item-view")
	await pointer(owner.item_owner.panel.get_global_transform_with_canvas()*owner.item_owner.panel.holder_rect().get_center())
	if not await ready_jobs(0):return
	check(scene._ui.host.active==owner and not owner.item_owner.panel.visible and owner.state.building_id==61,"Item holder did not return to plate")
	await lever_capture("item-returned")
func lever_capture(label: String) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,400);root.push_input(motion,true)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/pressure-plate-"+label+".png");native.convert(Image.FORMAT_RGB8)
	var crop:=image.get_region(Rect2i(416,52,488,708));crop.save_png(directory+"/pressure-plate-navigation-"+label+"-viewer.png")
	check(crop.get_data()==native.get_region(Rect2i(416,52,488,708)).get_data(),"Plate navigation pixels differ: "+label)
