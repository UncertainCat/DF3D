extends "res://tests/farm_body_capture.gd"
class Service:
	extends RefCounted
	var intent: Dictionary={}
	func submit(_domain,request,_observer):intent=request.duplicate(true);return 1
	func detach(_ticket):pass
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Workshop assets unavailable");return
	var background:=ColorRect.new();root.add_child(background)
	background.color=world.ui_texture("HOVER_RECTANGLE").get_image().get_pixel(8,12);background.size=Vector2(1200,800)
	var state=preload("res://scripts/workshop_tasks_state.gd").new()
	var service:=Service.new();state.service=service
	state.building_id=4;state.phase=state.Phase.Ready
	state.snapshot={"jobs":[{"id":42,"name":"Make bed","repeat":false,"suspended":false,"editable":true}],"recipes":[]}
	var view=preload("res://scripts/workshop_tasks_view.gd").new();root.add_child(view)
	view.configure(world,state);view.position=Vector2(432,106);view.size=Vector2(464,564)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/workshop-tasks-queue.png"))
	click(Vector2(868,154))
	if service.intent.get("job_id")!=42 or not service.intent.get("cancel",false):fail("Workshop cancel click missed selected job");return
	state.ticket=0;state.phase=state.Phase.Ready;service.intent={}
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_workshop.json"))
	for row in fixture.availability_wire_reference.native_reactions.rows:
		state.snapshot.recipes.append({"key":"reaction:"+row.code,"name":row.caption,"availability":{"available":row.available,"objection":row.objection}})
	view.choose_mode(true)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/workshop-tasks-picker.png"))
	click(Vector2(600,190))
	if service.intent.get("recipe")!=state.snapshot.recipes[0].key:fail("Workshop recipe click missed selected task");return
	state.ticket=0;state.service=null
	view.queue_free();world.queue_free();background.queue_free();await process_frame
	print("WORKSHOP_TASKS_CAPTURE_PASS");quit(0)
