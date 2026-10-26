extends SceneTree
# Native stockpile screen texture positions, independent of the shared formula.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_stockpile_scroll.json"))
	var bar = preload("res://scripts/area_location_scrollbar.gd").new()
	root.add_child(bar); bar.size = Vector2(16,576); bar.page = 16
	var failures := 0
	for sample in fixture.scrollbar.cases:
		bar.set_rows(int(sample.count),int(sample.first))
		if bar.visible != sample.visible:
			failures += 1; push_error("Native scrollbar visibility differs: "+str(sample))
		if sample.has("thumb") and bar.thumb() != Vector2i(int(sample.thumb[0]),int(sample.thumb[1])):
			failures += 1; push_error("Native scrollbar thumb differs: "+str(sample))
	bar.set_rows(12328,30)
	for sample in fixture.scrollbar.input:
		var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true
		event.position = Vector2(4,{"down_arrow":568,"up_arrow":4,"track_below":256}[sample.action])
		bar._gui_input(event)
		if bar.first != int(sample.after):
			failures += 1; push_error("Native scrollbar input differs: "+str(sample))
	var links = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_stockpile_links.json"))
	bar.size = Vector2(16,324); bar.page = 9
	for sample in links.scroll_oracle.inputs:
		if sample.name == "link-scroll-held": continue # Immediate feeds do not establish elapsed repeat cadence.
		bar.set_rows(20,int(sample.get("start",0))); bar.dragging = false
		if sample.name == "link-scroll-drag":
			bar.drag_to((int(sample.y)-11)*12+6)
		else:
			if str(sample.label).begins_with("STANDARDSCROLL"): continue
			var event := InputEventMouseButton.new(); event.pressed = true
			event.position = Vector2(12,(int(sample.y)-11)*12+6)
			if str(sample.label).begins_with("CONTEXT_SCROLL"):
				event.button_index = MOUSE_BUTTON_WHEEL_UP if "UP" in sample.label else MOUSE_BUTTON_WHEEL_DOWN
				event.shift_pressed = "PAGE" in sample.label
			else: event.button_index = MOUSE_BUTTON_LEFT
			bar._gui_input(event)
		if bar.first != int(sample.after):
			failures += 1; push_error("Native link scroll differs: "+str(sample))
	bar.scale = Vector2(1.5,1.5); bar.position = Vector2(100,60)
	bar.set_rows(20,0); bar.dragging = true
	var motion := InputEventMouseMotion.new()
	motion.position = bar.get_global_transform_with_canvas() * Vector2(8,162)
	bar._input(motion)
	if bar.first != 5:
		failures += 1; push_error("Scaled link thumb drag changed native row mapping")
	# Modern owner widgets use the standalone sheet and interior endpoint clamp.
	var owner = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_zone_assignment.json"))
	var owner_bar = preload("res://scripts/reports_scrollbar.gd").new()
	root.add_child(owner_bar); owner_bar.clamp_interior_thumb = true
	owner_bar.size = Vector2(16,600); owner_bar.page = 16
	for sample in owner.owner_scroll.samples:
		owner_bar.set_rows(int(sample.count),int(sample.scroll))
		var expected := Vector2i(int(sample.bar.scroller_sy)-7,int(sample.bar.scroller_ey)-int(sample.bar.scroller_sy)+1)
		if owner_bar.thumb() != expected:
			failures += 1; push_error("Native owner thumb differs: "+str(sample.label))
		if str(sample.label).begins_with("drag-"):
			owner_bar.set_rows(int(sample.count),0)
			owner_bar.drag_to((int(str(sample.label).trim_prefix("drag-"))-7)*12+6)
			if owner_bar.first != int(sample.scroll):
				failures += 1; push_error("Native owner drag mapping differs: "+str(sample.label))
	owner_bar.free()
	bar.free()
	print("STOCKPILE_SCROLLBAR_PASS" if failures == 0 else "STOCKPILE_SCROLLBAR_FAIL")
	quit(failures)
