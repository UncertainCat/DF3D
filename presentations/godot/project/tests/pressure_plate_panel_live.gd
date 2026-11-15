extends "res://tests/pressure_plate_wire_live.gd"
class Interaction:
	extends RefCounted
	var construction_active:=false
	var shell_blocked:=false
	var shell_enabled:=false
	var panel:=Control.new()
	func cancel_selection() -> void:pass
	func set_play_enabled(_value: bool) -> void:pass
func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.global_position=point;event.pressed=pressed;root.push_input(event,true)
func settle(owner,count: int) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();await process_frame
		if owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready and owner.lever.state.phase==owner.lever.state.Phase.Ready and owner.tasks.jobs().size()==count:return true
	check(false,"Plate gesture did not settle: "+str([owner.state.phase,owner.tasks.phase,owner.lever.state.phase,owner.tasks.jobs().size(),count]));return false
func compare(label: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/pressure-plate-"+label+".png");native.convert(Image.FORMAT_RGB8)
	var rect:=Rect2i(416,52,488,708)
	image.get_region(rect).save_png(directory+"/pressure-plate-panel-"+label+"-viewer.png")
	check(image.get_region(rect).get_data()==native.get_region(rect).get_data(),"Composed lever pixels differ: "+label)
func model_ready(model) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();await process_frame
		if model.phase==model.Phase.Ready:return true
	check(false,"Plate subpanel did not become ready: "+str(model.phase));return false
func key(code: int,unicode:=0) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.unicode=unicode;event.pressed=pressed;root.push_input(event,true)
func edit_gestures(owner) -> void:
	var original: String=owner.state.snapshot.custom_name
	click(Vector2(800,82));key(0,120);key(KEY_ENTER)
	if not await settle(owner,0):return
	check(owner.state.snapshot.custom_name==original+"x","Plate rename failed");await compare("renamed")
	click(Vector2(800,82));key(KEY_BACKSPACE);key(KEY_ENTER)
	if not await settle(owner,0):return
	check(owner.state.snapshot.custom_name==original,"Plate name not restored");await compare("name-restored")
	for control in [["forbid",796],["dump",820],["hidden",868]]:
		var before: bool=owner.contents.rows()[0][control[0]]
		for restored in [false,true]:
			click(Vector2(control[1],562))
			if not await settle(owner,0):return
			check(owner.contents.rows()[0][control[0]]==(before if restored else not before),"Plate item flag differs: "+control[0])
			await compare("item-"+control[0]+("-restored" if restored else ""))
	click(Vector2(832,82))
	if not await model_ready(owner.state):return
	if not await model_ready(owner.contents):return
	check(owner.state.snapshot.removing and not owner.panel.tasks.visible,"Plate removal retained tasks")
	await compare("removing")
	click(owner.panel.get_global_transform_with_canvas()*owner.panel.cancel_rect().get_center())
	if not await settle(owner,0):return
	check(not owner.state.snapshot.removing,"Plate removal was not cancelled");await compare("removal-cancelled")
func inspect_prompt(_snapshot: Dictionary,_expected: Dictionary) -> void:
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Plate panel assets unavailable"):return
	var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=Interaction.new();root.add_child(host)
	var owner=preload("res://scripts/pressure_plate_panel.gd").new();root.add_child(owner);owner.configure(world,service,host)
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline and (service._needs_claim or service._active!=0 or service._epoch<=0):world.poll();await process_frame
	owner.open_target(61)
	var ready:=await settle(owner,0)
	if ready:
		if not await model_ready(owner.links):ready=false
	if ready:
		await create_timer(0.5).timeout;await compare("initial")
		if OS.get_environment("DF3D_PRESSURE_PLATE_EDITS")=="1":await edit_gestures(owner)
		for index in [1,2]:
			click(owner.panel.global_position+owner.panel.tab_rect(index).get_center())
			if not await model_ready(owner.workers if index==1 else owner.orders):break
			await create_timer(0.3).timeout;await compare("workers" if index==1 else "work-orders")
		click(owner.panel.global_position+owner.panel.tab_rect(0).get_center());await process_frame
		click(Vector2(744,154))
		deadline=Time.get_ticks_msec()+10000
		while Time.get_ticks_msec()<deadline and not (owner.lever.view.visible and owner.lever.view.ready_art()):world.poll();await process_frame
		check(owner.lever.view.visible and not owner.panel.visible and owner.modal_input,"Plate Link did not transfer input ownership")
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var native:=Image.load_from_file(directory+"/pressure-plate-supplied-link.png");native.convert(Image.FORMAT_RGB8)
		var rect:=Rect2i(32,52,456,156);image.get_region(rect).save_png(directory+"/pressure-plate-prompt-viewer.png")
		check(image.get_region(rect).get_data()==native.get_region(rect).get_data(),"Plate Link prompt pixels differ")
		owner.handle_escape();await process_frame
		check(owner.panel.visible and not owner.lever.view.visible and not owner.modal_input,"Plate Link cancellation did not restore panel")
	owner.close_panel();check(host.active==null,"Plate close retained owner")
	owner.queue_free();await process_frame
	host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
