extends "res://tests/furniture_scene_live.gd"
func chest_ready() -> bool:
	if not await super.chest_ready():return false
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if owner.links.phase==owner.links.Phase.Ready:return true
		if owner.links.phase in [owner.links.Phase.Rejected,owner.links.Phase.Unavailable]:break
		await create_timer(0.01).timeout
	return check(false,"Floodgate links did not become ready")
func exercise(expected: Dictionary) -> void:
	await super.exercise(expected)
	if failed:return
	var entry: Dictionary=expected.buildings[0]
	owner.open_target(int(entry.id))
	if not await chest_ready():return
	check(not owner.panel.showing_links,"Reopened floodgate retained link tab")
	await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.tab_rect(0).get_center())
	check(owner.panel.showing_links and not owner.panel.contents.visible,"Link tab did not replace contents")
	await panel_capture("floodgate-links","workshop-furniture-9-links")
	if entry.has("link_hover"):
		var motion:=InputEventMouseMotion.new()
		motion.position=owner.panel.links_view.get_global_transform_with_canvas()*owner.panel.links_view.recenter_rect(0).get_center()
		root.push_input(motion,true);await create_timer(0.6).timeout
		var help=owner.panel.links_view.hover_help
		check(entry.link_hover.instruction==315 and entry.link_hover.enabled,"Native linked-building hover evidence missing")
		check(help.displayed=="contents_linked-building" and help.visible,"Linked-building tooltip did not appear on recenter button")
		check(help.CONTENTS_HELP["linked-building"]==entry.link_hover.lines.slice(0,2),"Linked-building tooltip differs from native text")
	if OS.get_environment("DF3D_FURNITURE_RESIZE")=="1":
		for size_case in [["small",Vector2i(960,600)],["medium",Vector2i(1200,720)],["wide",Vector2i(1600,900)],["default",Vector2i(1200,800)]]:
			var motion:=InputEventMouseMotion.new();motion.position=Vector2.ZERO;root.push_input(motion,true)
			root.size=size_case[1];await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
			var region:=Rect2i(Vector2i(owner.panel.position),Vector2i(owner.panel.size))
			var native:=Image.load_from_file(directory+"/workshop-furniture-9-links-resize-"+size_case[0]+".png");native.convert(Image.FORMAT_RGB8)
			var crop:=image.get_region(region);crop.save_png(directory+"/floodgate-links-resize-"+size_case[0]+".png")
			check(crop.get_data()==native.get_region(region).get_data(),"Floodgate links resize differs: "+size_case[0])
	await pointer(owner.panel.links_view.get_global_transform_with_canvas()*Vector2(100,18))
	check(scene._ui.host.active==owner,"Link row body closed panel")
	await panel_capture("floodgate-links-body","workshop-furniture-9-links-body")
	var calls: Array=[];owner.focus_requested.connect(func(tile):calls.append(tile))
	await pointer(owner.panel.links_view.get_global_transform_with_canvas()*owner.panel.links_view.recenter_rect(0).get_center())
	await drain()
	var target: Dictionary=entry.link_target
	check(calls==[Vector3i(target.x,target.y,target.z)] and world.get_top_z()==int(target.z),"Link recenter missed native target level")
	check(scene._ui.host.active==null and not owner.panel.visible and owner.links.building_id<0,"Recenter retained sheet ownership")
	owner.open_target(int(entry.id))
	if not await chest_ready():return
	check(not owner.panel.showing_links,"Recenter/reopen retained link tab")
	await panel_capture("floodgate-reopened","workshop-furniture-9-reopened")
	key(KEY_ESCAPE);await drain()
