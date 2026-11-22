extends SceneTree
const State=preload("res://scripts/pet_management_state.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	Engine.max_fps=30;root.size=Vector2i(1200,800)
	var directory:=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var state:=State.new();state.phase=State.Phase.Ready
	var file:=FileAccess.open(directory+"/pet-trainer-6548-0.bin",FileAccess.READ)
	var snapshot: Dictionary=file.get_var();file.close()
	state.snapshot=snapshot;state.ids=snapshot.unit_ids;state.total=state.ids.size()+3
	for offset in [0,64]:
		file=FileAccess.open(directory+"/pet-trainer-6548-"+str(offset)+".bin",FileAccess.READ)
		var page: Dictionary=file.get_var();file.close()
		for row: Dictionary in page.rows:state.rows[row.id]=row
	var view=preload("res://scripts/pet_management_view.gd").new();root.add_child(view)
	view.ticks_override=0;view.configure_pets(world,state);view.layout(Vector2(1200,800))
	for frame in 3:await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/pet-trainers-render.png")
	file=FileAccess.open(directory+"/pet-knowledge-rows.bin",FileAccess.READ)
	var knowledge: Array=file.get_var();file.close()
	state.pane=State.Pane.Knowledge;state.first=0;state.rows={};state.total=knowledge.size()
	for index in knowledge.size():state.rows[index]=knowledge[index]
	view.layout(Vector2(1200,800))
	for frame in 3:await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/pet-knowledge-render.png")
	for offset in [10,20,30,35]:
		state.seek(offset,10);view.refresh()
		for frame in 3:await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/pet-knowledge-render-"+str(offset)+".png")
	view.queue_free();world.queue_free();await process_frame;quit(0)
