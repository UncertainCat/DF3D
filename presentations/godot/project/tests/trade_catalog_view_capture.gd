extends "res://tests/trade_catalog_state_test.gd"
const View=preload("res://scripts/trade_catalog_view.gd")
func click(point: Vector2,button: int=MOUSE_BUTTON_LEFT) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true);await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=button;event.pressed=pressed;root.push_input(event,true);await process_frame
func run() -> void:
	Engine.max_fps=30
	var directory:=OS.get_environment("DF3D_DEPOT_CAPTURE_DIRECTORY")
	if directory.is_empty():quit(77);return
	var world=Df3dWorld.new();root.add_child(world)
	if not check_assets(world):quit(1);return
	var recorded: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-catalog-wire-result.json"))
	var value: Dictionary=recorded.responses[0]
	value.depot_id=int(value.depot_id)
	for row in value.choices:row.token=int(row.token);row.entity_id=int(row.entity_id)
	var service=Service.new();root.add_child(service)
	var state=Model.new();state.configure(service);state.open(value.depot_id);service.reply(state.ticket,value)
	var selected: Array=[];state.choice_requested.connect(func(depot,token):selected.append([depot,token]))
	var view=View.new();root.add_child(view);view.configure_catalog(world,state);view.layout(Vector2(1200,800))
	for i in 4:await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGBA8)
		var native:=Image.load_from_file(directory+"/trade-catalog-wire.png");native.convert(Image.FORMAT_RGBA8)
		rendered.save_png(directory+"/trade-catalog-view.png")
		var rect:=Rect2i(32,52,944,708)
		check(native.get_region(rect).get_data()==rendered.get_region(rect).get_data(),"Merchant chooser pixels differ")
	await click(Vector2(100,154));await click(Vector2(100,118))
	check(selected==[[value.depot_id,value.choices[1].token]],"Visible second merchant did not dispatch its exact token once")
	await click(Vector2(100,154),MOUSE_BUTTON_RIGHT)
	check(state.phase==Model.Phase.Closed,"Right click did not close chooser")
	view.queue_free();await process_frame;state.dispose();service.queue_free();world.queue_free();await process_frame
	if not failed:print("TRADE_CATALOG_VIEW_PASS")
	quit(1 if failed else 0)
func check_assets(world) -> bool:return world.load_assets(OS.get_environment("DF3D_DF_PATH"))
