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
