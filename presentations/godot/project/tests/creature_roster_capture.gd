extends SceneTree
# Render actual recorded wire rows with installed assets; no live DF session.
const State=preload("res://scripts/residents_state.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	Engine.max_fps=30;root.size=Vector2i(1200,800)
	var directory:=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var file:=FileAccess.open(directory+"/creature-render-rows.bin",FileAccess.READ)
	if file==null:push_error("Recorded creature wire rows missing");quit(1);return
	var recorded: Dictionary=file.get_var();file.close()
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var state:=State.new();state.directions=[false,false,false,false,false,false]
	var view=preload("res://scripts/residents_view.gd").new();root.add_child(view)
	view.ticks_override=500;view.configure_residents(world,state);view.layout(Vector2(1200,800))
	for tab in [1,2,3]:
		state.tab=tab;state.ids=PackedInt32Array();state.rows={};state.first=4 if tab==1 else 0
		state.phase=State.Phase.Ready
		for row: Dictionary in recorded[tab]:
			var value:=row.duplicate(true)
			if value.has("portrait"):value.sheet_icon=value.portrait
			value.activity={"caption":row.activity.text,"fg":row.activity.foreground,"bg":row.activity.background,"bright":row.activity.bright}
			var key:=State.row_key(row);state.ids.append(key);state.rows[key]=value
		view.refresh()
		for frame in 3:await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/creature-roster-"+str(tab)+".png")
	view.free();world.queue_free();state.dispose();await process_frame
	print("CREATURE_ROSTER_CAPTURE_PASS");quit()
