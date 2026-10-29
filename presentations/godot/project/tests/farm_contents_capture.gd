extends "res://tests/farm_body_capture.gd"
class Contents:
	extends RefCounted
	signal changed
	enum Phase {Ready,Reading,Applying}
	var phase:=Phase.Ready
	var ticket:=0
	var snapshot: Dictionary={}
	var calls: Array=[]
	func rows() -> Array:return snapshot.get("rows",[]).duplicate(true)
	func set_flag(id: int,operation: int,value: bool) -> void:calls.append([id,operation,value])
	func seek(cursor: int) -> void:calls.append(["seek",cursor])
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(472,216)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Contents assets unavailable");return
	var background:=ColorRect.new();root.add_child(background);background.size=Vector2(472,216)
	background.color=world.ui_texture("HOVER_RECTANGLE").get_image().get_pixel(8,12)
	var model:=Contents.new()
	var view=preload("res://scripts/farm_contents_view.gd").new();root.add_child(view);view.configure(world,model)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
	var cases: Array=fixture.contents_rows_reference.cases
	for sample in cases:
		model.snapshot={"rows":sample.rows.duplicate(true),"cursor":0,"total":int(sample.total),"completed":true,"removing":false}
		for row in model.snapshot.rows:
			for key in ["id","role","item_type"]:row[key]=int(row[key])
		model.changed.emit()
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		image.save_png(ProjectSettings.globalize_path("res://../../../build/contents-"+sample.name+"-viewer.png"))
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
		if hash.finish().hex_encode()!=sample.rgb_sha256:fail("Native contents pixels differ: "+sample.name);return
	model.snapshot.rows=cases[0].rows.duplicate(true)
	for row in model.snapshot.rows:
		for key in ["id","role","item_type"]:row[key]=int(row[key])
	model.changed.emit();model.calls.clear()
	for entry in [[0,"permanent"],[1,"view"],[2,"forbid"],[3,"dump"],[4,""],[5,"visibility"]]:
		if view.help_at(view.control_rect(0,entry[0]).get_center())!=entry[1]:fail("Contents help hitbox differs");return
	model.snapshot.rows[0].role=0;model.changed.emit()
	if view.help_at(view.control_rect(0,0).get_center())!="other":fail("Temporary role help differs");return
	model.snapshot.rows[0].in_job=true;model.changed.emit()
	if view.help_at(view.control_rect(0,0).get_center())!="task":fail("Task role help precedence differs");return
	model.snapshot.rows[0].in_job=false;model.snapshot.rows[0].role=2
	model.snapshot.rows[0].can_melt=true;model.changed.emit()
	if view.help_at(view.control_rect(0,4).get_center())!="melt":fail("Eligible melt help missing");return
	model.snapshot.rows[0].can_melt=false;model.changed.emit()
	view.view_requested.connect(func(id):model.calls.append(["view",id]))
	for control in range(1,6):click(view.control_rect(0,control).get_center())
	if model.calls!=[["view",47492],[47492,6,true],[47492,7,true],[47492,9,true]]:fail("Contents explicit intents/eligibility differ: "+str(model.calls));return
	model.calls.clear();model.phase=Contents.Phase.Applying;model.changed.emit();click(view.control_rect(0,2).get_center())
	model.phase=Contents.Phase.Ready;view.input_allowed=func():return false;click(view.control_rect(0,2).get_center())
	if not model.calls.is_empty():fail("Contents bypassed pending/owner input gate");return
	view.input_allowed=Callable();model.snapshot={};model.changed.emit();click(view.control_rect(0,2).get_center())
	if not model.calls.is_empty() or not view.rows.is_empty() or view.scrollbar.visible:fail("Retired contents retained input/rows");return
	view.queue_free();world.queue_free();background.queue_free();await process_frame
	print("FARM_CONTENTS_CAPTURE_PASS");quit(0)
