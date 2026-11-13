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
	state.snapshot={"jobs":[{"id":42,"name":"Make bed","repeat":false,"priority":false,"suspended":false,"editable":true}],"recipes":[]}
	var header=preload("res://scripts/building_header_state.gd").new()
	header.building_id=4;header.phase=header.Phase.Ready
	header.snapshot={"header_name":"Carpenter's Workshop","custom_name":"","removing":false}
	var contents=preload("res://scripts/building_contents_state.gd").new()
	var help=preload("res://scripts/native_hover_view.gd").new();root.add_child(help);help.configure(world);help.layout(Vector2(1200,800))
	help.z_index=50
	var sheet=preload("res://scripts/workshop_sheet_view.gd").new();root.add_child(sheet)
	sheet.configure(world,header,null,contents)
	sheet.configure_tasks(world,state,"BUILDING_ICON_WORKSHOP_CARPENTER",help);sheet.layout(Vector2(1200,800))
	var view=sheet.tasks
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/workshop-tasks-queue.png"))
	var hover_reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_workshop.json")).task_hover_reference
	for sample in hover_reference.samples:
		if sample.kind.ends_with("-control"):continue
		if sample.kind=="repeat-on":state.snapshot.jobs[0].repeat=true
		if sample.kind=="priority-on":state.snapshot.jobs[0].priority=true
		if sample.kind=="suspend-on":state.snapshot.jobs[0].suspended=true
		if sample.kind=="move-up-enabled":
			var second: Dictionary=state.snapshot.jobs[0].duplicate(true);second.id=43;second.can_move_up=true;state.snapshot.jobs.append(second)
		state.changed.emit()
		var motion:=InputEventMouseMotion.new();motion.position=Vector2(sample.x,sample.y);root.push_input(motion,true)
		await create_timer(0.6).timeout;await RenderingServer.frame_post_draw
		var kind: String="move-up" if sample.kind=="move-up-enabled" else sample.kind
		if int(sample.instruction)==-1:
			if help.visible:fail("Workshop blank control retained help");return
		else:
			if help.displayed!="workshop_task_"+kind or help.WORKSHOP_TASK_HELP[kind]!=sample.lines:fail("Workshop native hover differs: "+kind);return
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/workshop-hover-"+kind+".png"))
	# A pending edit cannot leave an actionable tooltip; a hidden panel retires its pointer.
	state.ticket=1;await process_frame;await process_frame
	if help.visible:fail("Pending workshop retained hover");return
	state.ticket=0;await process_frame;await process_frame
	if not help.visible:fail("Ready workshop failed to restore current hover");return
	view.picking=true;await process_frame;await process_frame
	if help.visible:fail("Picker retained job hover");return
	view.picking=false;await process_frame;await process_frame
	sheet.hide();await process_frame;await process_frame
	if help.visible or view.pointer_known:fail("Hidden workshop retained hover ownership");return
	sheet.show();state.snapshot.jobs.resize(1);state.snapshot.jobs[0].repeat=false;state.snapshot.jobs[0].suspended=false;state.changed.emit()
	click(Vector2(868,154))
	if service.intent.get("job_id")!=42 or not service.intent.get("cancel",false):fail("Workshop cancel click missed selected job");return
	state.ticket=0;state.phase=state.Phase.Ready;service.intent={}
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_workshop.json"))
	state.snapshot.recipes=fixture.still_tasks_reference.tasks.rows.duplicate(true)
	header.snapshot.header_name="Still";sheet.building_icon="BUILDING_ICON_WORKSHOP_STILL";header.changed.emit()
	view.choose_mode(true)
	if sheet.contents.visible or view.size.y!=642:fail("Workshop picker did not expand over contents");return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/workshop-tasks-picker.png"))
	click(Vector2(600,154))
	for letter in "BREW":
		var key:=InputEventKey.new();key.unicode=letter.unicode_at(0);key.pressed=true;root.push_input(key,true)
	if service.intent.get("query")!="BREW":fail("Workshop search input did not reach native request");return
	var enter:=InputEventKey.new();enter.keycode=KEY_ENTER;enter.pressed=true;root.push_input(enter,true)
	if view.search_focused:fail("Workshop Enter retained search focus");return
	state.ticket=0;state.phase=state.Phase.Ready
	state.snapshot={"jobs":[],"recipes":fixture.still_tasks_reference.tasks.rows.slice(0,2)}
	state.changed.emit()
	await process_frame;await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/workshop-tasks-search.png"))
	var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGB8)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(rendered.get_region(Rect2i(432,136,456,36)).get_data())
	if hash.finish().hex_encode()!=fixture.search_reference.field_render.native_rgb_sha256:fail("Workshop search field differs from native capture");return
	click(Vector2(600,226))
	if service.intent.get("recipe")!=state.snapshot.recipes[1].key:fail("Workshop recipe click missed selected task");return
	state.ticket=0;state.service=null
	view.choose_mode(false)
	if not sheet.contents.visible or view.size.y!=390:fail("Workshop queue did not restore contents");return
	sheet.queue_free();help.queue_free();world.queue_free();background.queue_free();await process_frame
	print("WORKSHOP_TASKS_CAPTURE_PASS");quit(0)
