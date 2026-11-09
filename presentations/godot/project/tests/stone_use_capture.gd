extends SceneTree
var failed:=false
func check(ok: bool,message: String) -> void:
	if not ok:failed=true;push_error(message)
func button(point: Vector2,pressed: bool=true,kind: int=MOUSE_BUTTON_LEFT,shift: bool=false) -> void:
	var event:=InputEventMouseButton.new();event.button_index=kind;event.pressed=pressed;event.position=point;event.global_position=point;event.shift_pressed=shift
	Input.parse_input_event(event);await process_frame
func click(point: Vector2) -> void:
	await button(point);await button(point,false)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	Engine.max_fps=30
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_stone_use.json"))
	var state=preload("res://scripts/stone_use_state.gd").new();state.phase=state.Phase.Ready
	for row in fixture.display_rows:
		row.category=int(row.category);row.index=int(row.index);state.rows.append(row)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=preload("res://scripts/stone_use_view.gd").new();root.add_child(view)
	view.configure_stone_use(world,state);view.layout(Vector2(1200,800))
	for category in 2:
		state.select_category(category)
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/stone-use-category-%d.png"%category))
	state.select_category(0)
	for dimensions in [Vector2i(960,720),Vector2i(960,600),Vector2i(1600,900),Vector2i(1200,800)]:
		root.size=dimensions;view.layout(Vector2(dimensions))
		await create_timer(0.3).timeout;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/stone-use-%dx%d.png"%[dimensions.x,dimensions.y]))
	await click(Vector2(952,730));check(state.first[0]==1,"Native arrow-down differs")
	await click(Vector2(952,202));check(state.first[0]==0,"Native arrow-up differs")
	await click(Vector2(952,610));check(state.first[0]==15,"Native page-down differs")
	await click(Vector2(240,148));await click(Vector2(952,730))
	await click(Vector2(112,148));check(state.category==0 and state.first==[15,1],"Native category positions not retained")
	for target in [[196,0],[232,0],[340,3],[460,7],[660,12],[736,15]]:
		state.seek(0,view.capacity());await process_frame
		await button(Vector2(944,220))
		var event:=InputEventMouseMotion.new();event.position=Vector2(944,target[0]);event.global_position=event.position;event.button_mask=MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(event);await process_frame
		await button(event.position,false)
		check(state.first[0]==target[1],"Native drag differs at "+str(target[0]))
	state.seek(0,view.capacity());await process_frame
	for point in [Vector2(200,250),Vector2(1100,750),Vector2(944,250)]:
		for shift in [false,true]:
			for kind in [MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_UP]:
				await button(point,true,kind,shift);check(state.first[0]==0,"Native ignored wheel changed scroll")
	view.queue_free();world.queue_free();await process_frame
	if not failed:print("STONE_USE_CAPTURE_PASS")
	quit(1 if failed else 0)
