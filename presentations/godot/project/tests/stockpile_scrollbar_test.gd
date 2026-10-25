extends SceneTree
# Native stockpile screen texture positions, independent of the shared formula.
func _initialize() -> void:
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
	bar.free()
	print("STOCKPILE_SCROLLBAR_PASS" if failures == 0 else "STOCKPILE_SCROLLBAR_FAIL")
	quit(failures)
