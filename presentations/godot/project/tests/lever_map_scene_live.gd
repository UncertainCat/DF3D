extends "res://tests/chest_scene_live.gd"
var applied_jobs: Dictionary={}
func ready_jobs(count: int) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.lever.state.phase==owner.lever.state.Phase.Ready and owner.tasks.jobs().size()==count:return true
	return check(false,"Main-scene lever did not settle: "+str([owner.state.phase,owner.tasks.phase,owner.lever.state.phase,owner.tasks.jobs().size()]))
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty() or DisplayServer.get_name()=="headless":quit(77);return
	OS.set_environment("DF3D_FIXTURE","")
	var prefs=preload("res://scripts/presentation_settings.gd");prefs.loaded=true;prefs.ui_scale=1.0;prefs.camera_mode="df"
	root.size=Vector2i(1200,800)
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/lever-wire-expected.json"))
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);world=scene.world
	var deadline:=Time.get_ticks_msec()+30000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	if check(scene._loader.entered,"Main scene did not enter fortress"):await exercise(expected)
	var file:=FileAccess.open(directory+"/workshop-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed and exercised,"surface":"actual main scene projected Link", "pull_job":applied_jobs.get(2,-1),"link_job":applied_jobs.get(3,-1)}));file.close()
	scene.queue_free();await process_frame;quit(1 if failed else 0)
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("lever")
	owner.lever.applied.connect(func(operation,id):applied_jobs[operation]=id)
	owner.open_target(55)
	if not await ready_jobs(0):return
	if OS.get_environment("DF3D_LEVER_NAVIGATION")=="1":
		await navigation_gestures()
		if failed:return
	if OS.get_environment("DF3D_LEVER_CONNECTION_VIEWER")=="1":
		await connection_gestures()
		if failed:return
	await pointer(Vector2(840,154))
	if not await ready_jobs(1):return
	if not check(applied_jobs.has(2),"Main-scene Pull did not apply"):return
	var tile:=Vector3i(expected.x,expected.y,expected.z)
	scene._ui.focus_tile(tile)
	await pointer(Vector2(744,190))
	var deadline:=Time.get_ticks_msec()+10000
	while not owner.lever.view.visible and Time.get_ticks_msec()<deadline:await process_frame
	if not check(owner.lever.view.visible and not owner.panel.visible and scene._ui.host.active==owner,"Link did not retain main-scene input ownership"):return
	var camera=scene.camera_rig.get_node("Camera3D")
	var point:=Vector2.ZERO
	var picked:=Vector3i(-1,-1,-1)
	deadline=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		point=camera.unproject_position(Vector3(tile.x+0.5,tile.z+0.5,tile.y+0.5))
		picked=world.pick_tile(camera.project_ray_origin(point),camera.project_ray_normal(point),world.get_top_z())
		if picked==tile:break
	if not check(picked==tile,"Projected Link ray missed target: "+str([tile,picked,point])):return
	await pointer(point)
	if not await ready_jobs(2):return
	check(applied_jobs.has(3) and owner.panel.visible and not owner.lever.view.visible and not owner.modal_input,"Map Link did not apply and restore panel")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/lever-map-linked.png")
	owner.close_panel();await process_frame
	check(scene._ui.host.active==null,"Lever close retained main-scene owner")
	exercised=true
func header_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready:return true
	return check(false,"Lever header gesture did not settle")
func lever_capture(label: String) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,400);root.push_input(motion,true)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/lever-"+label+".png");native.convert(Image.FORMAT_RGB8)
	var crop:=image.get_region(Rect2i(416,52,488,708));crop.save_png(directory+"/lever-navigation-"+label+"-viewer.png")
	check(crop.get_data()==native.get_region(Rect2i(416,52,488,708)).get_data(),"Lever navigation pixels differ: "+label)
func navigation_gestures() -> void:
	var original: String=owner.state.snapshot.custom_name
	await pointer(Vector2(800,82));key(0,120);key(KEY_ENTER)
	if not await header_ready():return
	check(owner.state.snapshot.custom_name==original+"x","Lever rename failed")
	await lever_capture("header-renamed")
	await pointer(Vector2(800,82));key(KEY_BACKSPACE);key(KEY_ENTER)
	if not await header_ready():return
	check(owner.state.snapshot.custom_name==original,"Lever name not restored")
	await lever_capture("header-restored")
	await pointer(Vector2(832,82))
	if not await header_ready():return
	check(owner.state.snapshot.removing and not owner.panel.tasks.visible,"Lever removal retained tasks")
	await lever_capture("header-removing")
	await pointer(Vector2(796,562))
	if not await header_ready():return
	check(owner.contents.rows()[0].forbid,"Removal item Forbid did not apply")
	await lever_capture("header-removing-forbid")
	await pointer(Vector2(796,562))
	if not await header_ready():return
	check(not owner.contents.rows()[0].forbid,"Removal item Forbid did not restore")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
	if not await ready_jobs(0):return
	await lever_capture("header-cancelled")
	var deadline:=Time.get_ticks_msec()+10000
	while owner.links.phase!=owner.links.Phase.Ready and Time.get_ticks_msec()<deadline:await process_frame
	if not check(owner.links.phase==owner.links.Phase.Ready,"Lever linked rows unavailable"):return
	await pointer(Vector2(540,520));await lever_capture("linked-buildings")
	check(owner.panel.showing_links,"Lever linked tab did not open")
	var row: Dictionary=owner.links.rows()[0]
	var target:=Vector3i(row.x,row.y,row.z)
	var focused: Dictionary={}
	owner.focus_requested.connect(func(tile):focused.tile=tile,CONNECT_ONE_SHOT)
	await pointer(Vector2(868,562));await process_frame
	check(scene._ui.host.active==null and not owner.panel.visible,"Lever recenter retained owner")
	check(focused.get("tile",Vector3i(-1,-1,-1))==target and world.get_top_z()==target.z,"Lever recenter selected wrong target")
	owner.open_target(55)
	if not await ready_jobs(0):return
	check(not owner.panel.showing_links,"Lever reopen retained linked tab")
	await lever_capture("linked-reopened")
func connections_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if owner.connections.phase==owner.connections.Phase.Ready:return true
	return check(false,"Lever Connections did not become Ready: "+str(owner.connections.phase))
func connection_capture(label: String,height: int) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(400,500);root.push_input(motion,true)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/lever-connections-"+label+".png");native.convert(Image.FORMAT_RGB8)
	var rect:=Rect2i(56,52,328,height);var crop:=image.get_region(rect)
	crop.save_png(directory+"/lever-connections-"+label+"-viewer.png")
	check(crop.get_data()==native.get_region(rect).get_data(),"Lever Connections pixels differ: "+label)
func connection_gestures() -> void:
	var native: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/lever-native.json"))
	var point: Dictionary=native.connections.pile_tile
	var tile:=Vector3i(point.x,point.y,point.z)
	scene._ui.focus_tile(tile)
	await pointer(Vector2(768,82))
	if not await connections_ready():return
	await connection_capture("open",420)
	for entry in [["give",80,1],["take",112,2]]:
		await pointer(Vector2(entry[1],82))
		check(owner.connections.picking and not owner.panel.visible,"Connections picker did not hide lever")
		await connection_capture(entry[0],120)
		await pointer(Vector2(328,82))
		if not await connections_ready():return
		check(owner.panel.visible,"Connections Cancel did not restore lever")
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
