extends "res://tests/lever_wire_live.gd"
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
	check(false,"Lever gesture did not settle: "+str([owner.state.phase,owner.tasks.phase,owner.lever.state.phase,owner.tasks.jobs().size(),count]));return false
func compare(label: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var native:=Image.load_from_file(directory+"/lever-"+label+".png");native.convert(Image.FORMAT_RGB8)
	var rect:=Rect2i(416,52,488,708)
	image.get_region(rect).save_png(directory+"/lever-panel-"+label+"-viewer.png")
	check(image.get_region(rect).get_data()==native.get_region(rect).get_data(),"Composed lever pixels differ: "+label)
func gestures(owner) -> void:
	for count in [1,2]:
		click(Vector2(840,154+(count-1)*36))
		if not await settle(owner,count):return
		await compare("pull-"+str(count))
	var first: int=owner.tasks.jobs()[0].id;var second: int=owner.tasks.jobs()[1].id
	click(Vector2(748,154));if not await settle(owner,2):return
	check(owner.tasks.jobs()[0].repeat,"Repeat click did not apply");await compare("pull-repeat")
	click(Vector2(748,154));if not await settle(owner,2):return
	click(Vector2(844,190));if not await settle(owner,2):return
	check(owner.tasks.jobs()[1].suspended,"Suspend click did not apply");await compare("pull-suspended")
	click(Vector2(844,190));if not await settle(owner,2):return
	click(Vector2(796,190));if not await settle(owner,2):return
	check(owner.tasks.jobs()[0].id==second,"Move up click changed wrong job");await compare("pull-moved")
	click(Vector2(772,190));if not await settle(owner,2):return
	check(owner.tasks.jobs()[0].id==first and owner.tasks.jobs()[0].priority,"Priority click changed wrong job");await compare("pull-priority")
	click(Vector2(772,154));if not await settle(owner,2):return
	click(Vector2(868,190));if not await settle(owner,1):return
	await compare("pull-cancel-second")
	click(Vector2(868,154));if not await settle(owner,0):return
	await compare("pull-cancel-all")
	for index in [1,2]:
		click(owner.panel.global_position+owner.panel.tab_rect(index).get_center())
		var model=owner.workers if index==1 else owner.orders
		var deadline:=Time.get_ticks_msec()+10000
		while Time.get_ticks_msec()<deadline and model.phase!=model.Phase.Ready:world.poll();await process_frame
		check(model.phase==model.Phase.Ready,"Lever tab did not load")
		await compare("workers" if index==1 else "work-orders")
	click(owner.panel.global_position+owner.panel.tab_rect(0).get_center());await process_frame
func inspect_prompt(_snapshot: Dictionary,_expected: Dictionary) -> void:
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Lever panel assets unavailable"):return
	var preferences=preload("res://scripts/presentation_settings.gd");preferences.loaded=true;preferences.ui_scale=1.0
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=Interaction.new();root.add_child(host)
	var owner=preload("res://scripts/lever_panel.gd").new();root.add_child(owner);owner.configure(world,service,host)
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline and (service._needs_claim or service._active!=0 or service._epoch<=0):world.poll();await process_frame
	owner.open_target(55)
	deadline=Time.get_ticks_msec()+10000
	var ready:=false
	while Time.get_ticks_msec()<deadline:
		world.poll();await process_frame
		ready=owner.state.phase==owner.state.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready and owner.links.phase==owner.links.Phase.Ready and owner.lever.state.phase==owner.lever.state.Phase.Ready
		if ready:break
	check(ready,"Composed lever initial state unavailable: "+str([owner.state.phase,owner.tasks.phase,owner.contents.phase,owner.links.phase,owner.lever.state.phase]))
	if ready:
		await create_timer(0.5).timeout;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var native:=Image.load_from_file(directory+"/lever-initial.png");native.convert(Image.FORMAT_RGB8)
		var rect:=Rect2i(416,52,488,708)
		image.get_region(rect).save_png(directory+"/lever-panel-viewer.png")
		check(image.get_region(rect).get_data()==native.get_region(rect).get_data(),"Composed lever initial pixels differ")
		if OS.get_environment("DF3D_LEVER_TASK_CONTROLS")=="1":await gestures(owner)
		click(Vector2(744,154))
		deadline=Time.get_ticks_msec()+10000
		while Time.get_ticks_msec()<deadline and not owner.lever.view.visible:world.poll();await process_frame
		check(owner.lever.view.visible and not owner.panel.visible and owner.modal_input,"Lever Link did not transfer panel/map ownership")
		owner.handle_escape();await process_frame
		check(owner.panel.visible and not owner.lever.view.visible and not owner.modal_input,"Lever Link cancellation did not restore panel")
	owner.close_panel();owner.queue_free();await process_frame
	host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
