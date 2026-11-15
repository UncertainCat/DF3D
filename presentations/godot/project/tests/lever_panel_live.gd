extends "res://tests/lever_wire_live.gd"
class Interaction:
	extends RefCounted
	var construction_active:=false
	var shell_blocked:=false
	var shell_enabled:=false
	var panel:=Control.new()
	func cancel_selection() -> void:pass
	func set_play_enabled(_value: bool) -> void:pass
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
		owner.panel.tasks.link_requested.emit()
		deadline=Time.get_ticks_msec()+10000
		while Time.get_ticks_msec()<deadline and not owner.lever.view.visible:world.poll();await process_frame
		check(owner.lever.view.visible and not owner.panel.visible and owner.modal_input,"Lever Link did not transfer panel/map ownership")
		owner.handle_escape();await process_frame
		check(owner.panel.visible and not owner.lever.view.visible and not owner.modal_input,"Lever Link cancellation did not restore panel")
	owner.close_panel();owner.queue_free();await process_frame
	host.interaction.panel.free();host.queue_free();service.queue_free();await process_frame
