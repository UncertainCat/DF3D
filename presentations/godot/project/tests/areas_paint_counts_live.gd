extends "res://tests/areas_controller_live.gd"
# Headless actual transport/controller. Reuses native062137's actual-button
# draft-preview-mixed.json (SHA256 D431B7A217A42C02AF48D1294E706EA7A4963243FFDC73761489EFD5A7A6260B).
# Those recorded native captions are independent expected values, not this reader.
# No claim of GPU or physical-pointer acceptance.
var count_observations: Array = []
func spans(rows: Array) -> Array:
	var result: Array = []
	for row in rows: result.append({"y":int(row[0]),"x":int(row[1]),"length":int(row[2])})
	return result

func exercise_location_catalogs() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory+"/location-metadata-comparison.json"))
	var observations: Array = []
	for kind in [2,4]:
		step = "location catalog transport %d" % kind
		var intent := {"action":9,"operation":Contract.AreaOperation.LocationChoices,"kind":1,"location_kind":kind}
		var page := await request(intent)
		if stopped: return
		var catalog: Dictionary = page.get("location_catalog",{})
		var key := "religions" if kind == 2 else "guilds"
		var expected: Array = baseline["bridge" if kind == 2 else "guild_bridge"].choices
		if not check(catalog.get("kind",0) == kind and int(catalog.get("revision",0)) > 0 and catalog.get("cursor",-1) == 0 and catalog.get("next_cursor",-1) == 0 and catalog.get("total",0) == expected.size(),"location catalog envelope differs"): return
		# JSON reference numbers are floats; dictionary equality is type-sensitive.
		# Row numbers are bounded int32, so this comparison preserves every value.
		var comparable: Variant = JSON.parse_string(JSON.stringify(catalog.get(key,[])))
		if not check(comparable == expected,"typed location rows differ from native-validated diagnostic"): return
		var repeat_page := await request(intent)
		if stopped: return
		if not check(repeat_page.location_catalog == catalog,"unchanged catalog receipt changed"): return
		observations.append(catalog)
		intent.expected_list_revision = int(catalog.revision)+1
		var seq: int = world.area_request(intent)
		if not check(seq > 0,"stale catalog request not sent"): return
		var deadline := Time.get_ticks_msec()+30000
		var received := false
		while Time.get_ticks_msec() < deadline:
			world.poll()
			var reply: Dictionary = world.poll_management()
			if int(reply.get("request_seq",0)) == seq and int(reply.get("status",S.Idle)) not in [S.Idle,S.Pending]:
				if not check(int(reply.status) == S.Rejected and not reply.get("area",{}).has("location_catalog") and str(reply.get("message","")) == "","stale catalog returned rows or authored copy"): return
				received = true; break
			await create_timer(0.01).timeout
		if not check(received,"stale catalog receipt timeout; no replay"): return
	var output := FileAccess.open(directory+"/location-transport-comparison.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(observations,"  ")); output.close()

func exercise() -> void:
	await seed_catalog()
	if stopped: return
	await native("paint_counts_begin")
	if stopped: return
	await native("paint_counts_controls")
	if stopped: return
	await native("paint_counts_switches")
	if stopped: return
	await native("paint_counts_brush")
	if stopped: return
	await native("paint_counts_elevation")
	if stopped: return
	await native("paint_counts_repaint_elevation")
	if stopped: return
	await native("paint_counts_location_choices")
	if stopped: return
	await native("paint_counts_location_eligibility")
	if stopped: return
	await native("paint_counts_guild_workers")
	if stopped: return
	await native("paint_counts_location_creation")
	if stopped: return
	await exercise_location_catalogs()
	if stopped: return
	var elevation_ids: Dictionary = {}
	for row in JSON.parse_string(FileAccess.get_file_as_string(directory+"/native-paint-repaint-elevation.json")):
		var label := str(row.label)
		var scope := label.get_slice("-",0)+"-"+label.get_slice("-",1)
		if label.ends_with("-created"): elevation_ids[scope] = int(row.current)
		var remaining := 8 if label.contains("-brush-") else 5
		if not check(int(row.current) == int(elevation_ids[scope]) and int(row.zone_z) == 164 and int(row.tiles) == (remaining if label.ends_with("-return-click") else 9),"native repaint elevation reference changed: "+label): return
	for row in JSON.parse_string(FileAccess.get_file_as_string(directory+"/native-paint-elevation.json")):
		var completed: bool = str(row.label).ends_with("-completed")
		if not check(int(row.tiles) == (9 if completed else 0) and int(row.zone_z) == (165 if completed else -1),"native elevation reference changed: "+str(row.label)): return
	var controls: Array = JSON.parse_string(FileAccess.get_file_as_string(directory+"/native-paint-controls.json"))
	var expected_controls := [[true,false,0],[true,false,0],[true,false,9],[true,true,9],
		[false,true,9],[true,true,9],[true,false,9],[false,false,9],[false,true,9],[false,false,9],[true,false,9],
		[true,true,9],[true,true,5]]
	for i in expected_controls.size():
		var expected: Array = expected_controls[i]
		if not check(controls[i].rectangle == expected[0] and controls[i].erasing == expected[1] and int(controls[i].tiles) == expected[2],"native control reference changed: "+str(controls[i].label)): return
	# Native073047: completed gestures already exist in the world before Accept.
	# Exit keys retain them; on-screen Cancel rolls back this new-zone interaction.
	# These are native reference checks, not claims of controller exit parity.
	var references: Dictionary = {}
	for row in controls: references[str(row.label)] = row
	var baseline: Array = references.initial.world_zones
	var brush: Dictionary = {}
	for row in JSON.parse_string(FileAccess.get_file_as_string(directory+"/native-paint-brush.json")): brush[str(row.label)] = row
	var expected_brush := {"brush-initial":0,"brush-press":1,"brush-diagonal-hold":2,"brush-release":2,"brush-unheld-move":2,
		"brush-second-press":3,"brush-cross-hold":4,"brush-cross-release":4,"brush-erase-press":3,"brush-erase-hold":2,"brush-erase-release":2,
		"rectangle-drag-press":0,"rectangle-drag-hold":0,"rectangle-drag-release":0,"rectangle-drag-second-click":9,"tool-switch-next-click":9}
	for label in expected_brush:
		if not check(int(brush[label].tiles) == int(expected_brush[label]),"native brush/rectangle reference changed: "+str(label)): return
	for suffix in ["before","multi","return","completed"]:
		var row: Dictionary = brush["brush-multi-anchor-"+suffix]
		if not check(row.multi == (suffix == "multi") and row.rectangle == (suffix == "completed") and int(row.tiles) == (9 if suffix == "completed" else 0),"native Brush/Multi corner reference changed: "+suffix): return
	var switches: Dictionary = {}
	for row in JSON.parse_string(FileAccess.get_file_as_string(directory+"/native-paint-switches.json")):
		switches[str(row.label)] = row
	for stage in ["empty-partial","painted","painted-partial","erased-empty"]:
		var prefix: String = "switch-"+stage
		var multi: Dictionary = switches[prefix+"-multi"]
		var paint: Dictionary = switches[prefix+"-paint"]
		if not check(multi.multi and multi.world_zones == baseline and int(multi.current) == -1,"native Multi must discard ordinary zone: "+stage): return
		if not check(not paint.multi and paint.world_zones == baseline and int(paint.current) == -1,"native return to Paint must start fresh: "+stage): return
		var first: Dictionary = switches[prefix+"-paint-first"]
		var second: Dictionary = switches[prefix+"-paint-second"]
		var expected_first := 1 if stage == "painted" else 0
		var expected_second := 0 if stage == "erased-empty" else (1 if stage == "painted" else 9)
		if not check(int(first.tiles) == expected_first and int(second.tiles) == expected_second and paint.erasing == (stage == "erased-empty"),"native shared corner/erase state changed: "+stage): return
	for action in ["escape","right-click","cancel"]:
		for stage in ["empty-partial","painted","painted-partial"]:
			var label: String = action+"-"+stage
			var before: Dictionary = references[label+"-before"]
			var after: Dictionary = references[label+"-after"]
			var created: bool = stage != "empty-partial"
			var retained: bool = created and action != "cancel"
			if not check(before.focus == ["dwarfmode/Zone/Paint/Bedroom"] and before.world_zones.size() == baseline.size()+int(created),"native pre-exit state changed: "+label): return
			if not check(after.focus == ["dwarfmode/Zone" if action == "cancel" else "dwarfmode/Default"],"native exit destination changed: "+label): return
			if retained:
				if not check(after.world_zones == before.world_zones and int(after.current) == int(before.current) and int(after.tiles) == 9,"native exit lost completed footprint: "+label): return
			elif not check(after.world_zones == baseline,"native empty exit/Cancel did not restore baseline: "+label): return
	# Native073705: repaint modifies the existing identity before Accept, and
	# Accept finishes even with a pending rectangle. New-zone erase-to-empty
	# preserves its identity and can be painted again before Cancel removes it.
	for action in ["escape","right-click","accept"]:
		var prefix: String = "repaint-"+action
		var created: Dictionary = references[prefix+"-created"]
		var edited: Dictionary = references[prefix+"-edited"]
		var after: Dictionary = references[prefix+"-after"]
		if not check(int(edited.current) == int(created.current) and int(edited.tiles) == 7 and edited.focus == ["dwarfmode/Zone/Paint/NONE"],"native repaint did not immediately erase: "+action): return
		if not check(after.world_zones == edited.world_zones and after.focus == ["dwarfmode/Zone/Some/Bedroom" if action == "accept" else "dwarfmode/Default"],"native repaint exit changed footprint/destination: "+action): return
	var erased: Dictionary = references["new-erase-all-after"]
	var repainted: Dictionary = references["new-erase-all-readd"]
	if not check(int(erased.current) == int(references["new-erase-all-before"].current) and int(erased.tiles) == 0 and erased.world_zones.size() == baseline.size()+1,"native erase-to-empty lost zone identity"): return
	if not check(int(repainted.current) == int(erased.current) and int(repainted.tiles) == 1 and references["new-erase-all-cancel"].world_zones == baseline,"native empty repaint/Cancel changed"): return
	var nine := [[57,170,3],[58,170,3],[59,170,3]]
	var twelve := [[57,170,4],[58,170,4],[59,170,4]]
	var eight := [[57,172,2],[58,172,2],[59,170,4]]
	var six := [[57,173,1],[58,173,1],[59,170,4]]
	var cases := [
		[nine,[172,59,1,1],9,0],[nine,[171,57,3,3],9,3],
		[twelve,[173,59,1,1],12,0],[twelve,[170,57,2,2],12,0],
		[eight,[171,58,1,1],8,1],[eight,[170,57,3,2],8,4],
		[six,[172,58,1,1],6,1],[six,[173,59,1,1],6,0]]
	for i in cases.size():
		step = "native reference %d" % i
		var sample: Array = cases[i]; var rectangle: Array = sample[1]
		var page := await request({"action":9,"operation":Contract.AreaOperation.PaintCounts,"kind":1,
			"zone_type":92,"paint_z":164,"count_generation":9007199254740993+i,"spans":spans(sample[0]),
			"paint_preview":{"x":rectangle[0],"y":rectangle[1],"width":rectangle[2],"height":rectangle[3]}})
		if stopped: return
		if not check(str(world.poll_management().get("message","")) == "","count read inherited an unrelated status message"): return
		if not check(page.count_generation == 9007199254740993+i and page.painted_count == sample[2] and page.preview_count == sample[3],"native reference count/generation mismatch"): return
		count_observations.append({"reference":i,"generation":str(page.count_generation),"painted":page.painted_count,"preview":page.preview_count,"captured_tick":page.captured_tick})
	step = "controller count setup"
	if not check(world.load_assets(FileAccess.get_file_as_string(directory+"/df-path.txt")),"installed assets unavailable"): return
	world.set_top_z(164)
	interaction = preload("res://tests/areas_test.gd").FakeInteraction.new(); root.add_child(interaction)
	host = preload("res://scripts/ui_host.gd").new(); host.interaction = interaction; root.add_child(host)
	actions = preload("res://scripts/semantic_action_service.gd").new(); actions.configure(world); root.add_child(actions); actions.set_process(false)
	editor = preload("res://scripts/areas.gd").new()
	editor.world = world; editor.action_service = actions; editor.ui_host = host; editor.interaction = interaction
	camera = Camera3D.new(); root.add_child(camera); editor.camera = camera
	root.add_child(editor); host.register(editor); editor.set_process(false)
	editor.set_area_kind(1); editor.open_panel()
	if await wait_ui(func(): return editor.available and settled(),"zone catalog"):
		editor.choose_zone_type(92)
		await exercise_counts()
		if not stopped:
			var retained: Dictionary = editor.zone_paint.area.duplicate(true)
			editor.handle_back()
			if await wait_ui(func(): return actions._active == 0 and actions._queue.is_empty(),"exit drains transport"):
				check(not editor.panel.visible,"Escape must close the actual painter")
				await native("paint_counts_track",{"id":int(retained.id),"tiles":6,"width":4})
				if not stopped: await request({"action":12,"kind":1,"id":int(retained.id),"expected_revision":retained.revision})
	if not stopped: await exercise_zone_lifecycle()
	if not stopped: await exercise_mode_switch()
	if not stopped: await exercise_reopen_order()
	if not stopped: await exercise_brush_inputs()
	if not stopped: await exercise_corner_elevation()
	if not stopped: await exercise_repaint_elevation()
	if not stopped: await exercise_location_selector_views()
	if not stopped: await exercise_location_creation()
	editor.close_panel(); editor.free(); camera.free(); actions.free(); host.free(); interaction.free()
	await process_frame
	if not stopped: await exercise_empty_zone()
	if not stopped: await native("paint_counts_cleanup")
	write_json("count-observations.json",count_observations)
	if not stopped: print("AREAS_PAINT_COUNTS_LIVE_PASS")

func complete_rectangle(first: Vector3i, last: Vector3i) -> void:
	editor.paint_pointer(first,true); editor.paint_pointer(first,false)
	editor.paint_pointer(last,true); editor.paint_pointer(last,false)

func exercise_mode_switch() -> void:
	step = "controller Paint to Multi"
	editor.open_panel()
	if not await wait_ui(func(): return editor.available and settled(),"mode-switch catalog"): return
	editor.choose_zone_type(92)
	var first := Vector3i(170,57,164); var last := Vector3i(172,59,164)
	complete_rectangle(first,last)
	if not await wait_ui(zone_ready,"zone before Multi switch"): return
	var id := int(editor.zone_paint.area.id)
	await native("paint_counts_track",{"id":id,"tiles":9})
	if stopped: return
	# Start a partial rectangle, as in the native transition control.
	editor.paint_pointer(first,true); editor.paint_pointer(first,false)
	editor.paint_view.multi_button.pressed.emit()
	if not check(editor.mode == "paint" and editor.zone_paint.ending == "multi","Multi input must wait for ordinary deletion receipt"): return
	if not await wait_ui(func(): return editor.mode == "multi","Multi after deletion"): return
	await native("paint_counts_absent",{"id":id})
	if stopped: return
	editor.multi_pointer(first,true); editor.multi_pointer(first,false)
	if not await wait_ui(settled,"shared corner completes Multi selection"): return
	editor.paint_view.paint_button.pressed.emit()
	if not check(editor.mode == "paint" and editor.zone_paint.area.is_empty() and not editor.dragging,"completed Multi rectangle must leave no pending corner or ordinary identity"): return
	complete_rectangle(first,last)
	if not await wait_ui(zone_ready,"fresh zone after mode return"): return
	id = int(editor.zone_paint.area.id)
	await native("paint_counts_track",{"id":id,"tiles":9})
	if stopped: return
	editor.paint_view.cancel_button.pressed.emit()
	if not await wait_ui(transport_idle,"mode-switch cleanup"): return
	await native("paint_counts_absent",{"id":id})
	if stopped: return
	# With no ordinary pending corner, one click in Multi leaves an anchor that
	# must become Paint's first corner rather than being discarded on return.
	editor.choose_zone_type(92); editor.paint_view.buttons.erase.pressed.emit()
	editor.paint_view.multi_button.pressed.emit()
	if not await wait_ui(func(): return editor.mode == "multi","empty switch preserving erase"): return
	editor.multi_pointer(first,true); editor.multi_pointer(first,false)
	editor.paint_view.paint_button.pressed.emit()
	if not check(editor.mode == "paint" and editor.dragging and editor.paint_erasing,"mode return must preserve Multi anchor and erase toggle"): return
	editor.paint_view.buttons.erase.pressed.emit()
	editor.paint_pointer(last,true); editor.paint_pointer(last,false)
	if not await wait_ui(zone_ready,"Paint completes carried Multi corner"): return
	id = int(editor.zone_paint.area.id)
	await native("paint_counts_track",{"id":id,"tiles":9})
	if stopped: return
	editor.paint_view.cancel_button.pressed.emit()
	if not await wait_ui(transport_idle,"shared-corner cleanup"): return
	await native("paint_counts_absent",{"id":id})

func zone_ready() -> bool:
	return editor.zone_paint != null and editor.zone_paint.ticket == 0 and not editor.zone_paint.area.is_empty()

func exercise_corner_elevation() -> void:
	for tool in ["rectangle","brush","brush-multi"]:
		step = "controller corner elevation "+tool
		world.set_top_z(164); editor._process(0)
		editor.choose_zone_type(92)
		editor.paint_pointer(Vector3i(170,57,164),true); editor.paint_pointer(Vector3i(170,57,164),false)
		if tool != "rectangle": editor.paint_view.buttons.brush.pressed.emit()
		if tool == "brush-multi":
			editor.paint_view.multi_button.pressed.emit()
			if not await wait_ui(func(): return editor.mode == "multi","Multi before elevation"): return
		world.set_top_z(165); editor._process(0)
		if tool == "brush-multi": editor.paint_view.paint_button.pressed.emit()
		if tool != "rectangle": editor.paint_view.buttons.rectangle.pressed.emit()
		if not check(editor.dragging and editor.drag_start == Vector3i(170,57,165),"saved corner must follow ending elevation: "+tool): return
		editor.paint_pointer(Vector3i(172,59,165),true); editor.paint_pointer(Vector3i(172,59,165),false)
		if not await wait_ui(zone_ready,"complete rectangle on ending elevation"): return
		var id := int(editor.zone_paint.area.id)
		await native("paint_counts_track",{"id":id,"tiles":9,"z":165})
		if stopped: return
		editor.paint_view.cancel_button.pressed.emit()
		if not await wait_ui(transport_idle,"elevation cleanup"): return
		await native("paint_counts_absent",{"id":id})
		if stopped: return
	world.set_top_z(164); editor._process(0)

func exercise_repaint_elevation() -> void:
	for scenario in 4:
		var existing := scenario >= 2
		var brush := scenario % 2 == 1
		step = "controller painted elevation existing="+str(existing)+" brush="+str(brush)
		editor.choose_zone_type(92)
		var first := Vector3i(170,57,164); var last := Vector3i(171,58,164)
		complete_rectangle(first,Vector3i(172,59,164))
		if not await wait_ui(zone_ready,"zone before elevation"): return
		var id := int(editor.zone_paint.area.id)
		await native("paint_counts_track",{"id":id,"tiles":9})
		if stopped: return
		if existing:
			editor.paint_view.accept_button.pressed.emit()
			if not await wait_ui(func(): return editor.zone_paint == null and not editor.selected.is_empty(),"accept before repaint"): return
			editor.begin_paint()
		editor.paint_view.buttons.erase.pressed.emit()
		if brush: editor.paint_view.buttons.brush.pressed.emit()
		else: editor.paint_pointer(first,true); editor.paint_pointer(first,false)
		world.set_top_z(165); editor._process(0)
		editor.paint_pointer(Vector3i(171,58,165),true); editor.paint_pointer(Vector3i(171,58,165),false)
		if not check(editor.paint_state.cells.size() == 9 and (not editor.dragging if brush else editor.dragging and editor.drag_start == first),"other-plane input lost corner or changed footprint"): return
		world.set_top_z(164); editor._process(0)
		editor.paint_pointer(last,true); editor.paint_pointer(last,false)
		if not await wait_ui(zone_ready,"finish retained erase corner"): return
		await native("paint_counts_track",{"id":id,"tiles":8 if brush else 5,"extents":[1,1,1,1,0,1,1,1,1] if brush else [0,0,1,0,0,1,1,1,1]})
		if stopped: return
		editor.paint_view.buttons.remove.pressed.emit()
		if not await wait_ui(transport_idle,"elevation zone removal"): return
		await native("paint_counts_absent",{"id":id})
		if stopped: return
		editor.new_area()

func exercise_brush_inputs() -> void:
	step = "controller sampled brush"
	editor.choose_zone_type(92); editor.paint_view.buttons.brush.pressed.emit()
	var first := Vector3i(170,57,164); var last := Vector3i(172,59,164)
	editor.paint_pointer(first,true)
	if not await wait_ui(zone_ready,"brush press"): return
	var id := int(editor.zone_paint.area.id)
	await native("paint_counts_track",{"id":id,"tiles":1,"width":1,"height":1,"extents":[1]})
	if stopped: return
	editor.paint_motion(last)
	if not await wait_ui(zone_ready,"sparse diagonal sample"): return
	editor.paint_pointer(first+Vector3i(1,1,0),false); editor.paint_motion(first+Vector3i(1,1,0))
	await native("paint_counts_track",{"id":id,"tiles":2,"extents":[1,0,0,0,0,0,0,0,1]})
	if stopped: return
	editor.paint_pointer(first+Vector3i(2,0,0),true); editor.paint_motion(first+Vector3i(0,2,0)); editor.paint_pointer(first+Vector3i(0,2,0),false)
	if not await wait_ui(zone_ready,"crossing brush samples"): return
	await native("paint_counts_track",{"id":id,"tiles":4,"extents":[1,0,1,0,0,0,1,0,1]})
	if stopped: return
	editor.paint_view.buttons.erase.pressed.emit(); editor.paint_pointer(first,true); editor.paint_motion(last); editor.paint_pointer(last,false)
	if not await wait_ui(zone_ready,"sampled brush erase"): return
	await native("paint_counts_track",{"id":id,"tiles":2,"extents":[0,0,1,0,0,0,1,0,0]})
	if stopped: return
	editor.paint_view.cancel_button.pressed.emit()
	if not await wait_ui(transport_idle,"brush cleanup"): return
	await native("paint_counts_absent",{"id":id})
	if stopped: return
	step = "controller rectangle release and tool switch"
	editor.choose_zone_type(92); editor.paint_pointer(first,true); editor.paint_motion(last); editor.paint_pointer(last,false)
	if not check(editor.dragging and editor.zone_paint.area.is_empty() and editor.paint_state.cells.is_empty(),"held first-corner drag must not commit on release"): return
	editor.paint_view.buttons.brush.pressed.emit(); editor.paint_motion(last)
	if not check(editor.paint_state.cells.is_empty(),"switching to Brush must not paint unheld motion"): return
	editor.paint_view.buttons.rectangle.pressed.emit()
	if not check(editor.dragging and editor.drag_start == first,"Rectangle/Brush round trip must retain first corner"): return
	editor.paint_pointer(last,true)
	if not await wait_ui(zone_ready,"second rectangle press"): return
	id = int(editor.zone_paint.area.id)
	await native("paint_counts_track",{"id":id,"tiles":9})
	if stopped: return
	editor.paint_pointer(last,false); editor.paint_view.cancel_button.pressed.emit()
	if not await wait_ui(transport_idle,"rectangle input cleanup"): return
	await native("paint_counts_absent",{"id":id})
	if stopped: return
	step = "controller Brush Multi saved corner"
	editor.choose_zone_type(92)
	editor.paint_pointer(first,true); editor.paint_pointer(first,false)
	editor.paint_view.buttons.brush.pressed.emit()
	editor.paint_view.multi_button.pressed.emit()
	if not await wait_ui(func(): return editor.mode == "multi","Brush to Multi"): return
	if not check(editor.dragging and editor.drag_start == first,"Multi lost Brush's saved rectangle corner"): return
	editor.paint_view.paint_button.pressed.emit()
	if not check(editor.paint_tool == "brush" and not editor.dragging and editor.paint_saved_corner == first,"return to Brush must retain corner without holding pointer"): return
	editor.paint_motion(last)
	if not check(editor.paint_state.cells.is_empty(),"return to Brush painted unheld motion"): return
	editor.paint_view.buttons.rectangle.pressed.emit()
	editor.paint_pointer(last,true); editor.paint_pointer(last,false)
	if not await wait_ui(zone_ready,"rectangle after Brush Multi round trip"): return
	id = int(editor.zone_paint.area.id)
	await native("paint_counts_track",{"id":id,"tiles":9})
	if stopped: return
	editor.paint_view.cancel_button.pressed.emit()
	if not await wait_ui(transport_idle,"Brush Multi cleanup"): return
	await native("paint_counts_absent",{"id":id})

func exercise_reopen_order() -> void:
	step = "controller rapid close/reopen ordering"
	var trace: Array = []
	var record := func(_ticket, result):
		if int(result.get("status",0)) != 2: return
		var action := int(result.get("action",-1))
		if action not in [0,7,10,11,12]: return
		var rows: Array = result.get("areas",[])
		trace.append({"action":action,"sequence":str(result.get("request_seq",0)),
			"id":int(rows[0].id) if not rows.is_empty() else int(result.get("building_id",-1)),
			"tiles":int(rows[0].tile_count) if not rows.is_empty() else -1})
	actions.completed.connect(record)
	editor.choose_zone_type(92)
	var first := Vector3i(170,57,164)
	complete_rectangle(first,first+Vector3i(2,2,0))
	editor.paint_view.buttons.erase.pressed.emit()
	for y in 3: complete_rectangle(first+Vector3i(0,y,0),first+Vector3i(2,y,0))
	editor.close_panel(); editor.open_panel()
	var ready := await wait_ui(func(): return editor.available and settled(),"rapid reopen catalog")
	actions.completed.disconnect(record)
	write_json("paint-order-observations.json",trace)
	if not ready: return
	var observed_actions: Array = []
	for row in trace: observed_actions.append(int(row.action))
	if not check(observed_actions == [10,11,11,11,12,0,7],"reopen overtook old Paint edits: "+str(observed_actions)): return
	var old_id := int(trace[0].id)
	for i in 4:
		if not check(int(trace[i].id) == old_id and int(trace[i].tiles) == 9-3*i,"old Paint identity/footprint order changed"): return
	await native("paint_counts_absent",{"id":old_id,"created_reply":true})
	if stopped: return
	editor.choose_zone_type(92); complete_rectangle(first,first+Vector3i(2,2,0))
	if not await wait_ui(zone_ready,"reopened painter creation"): return
	var new_id := int(editor.zone_paint.area.id)
	if not check(new_id != old_id,"reopened painter reused retired identity"): return
	await native("paint_counts_track",{"id":new_id,"tiles":9})
	if stopped: return
	editor.paint_view.cancel_button.pressed.emit()
	if not await wait_ui(transport_idle,"reopened painter cleanup"): return
	await native("paint_counts_absent",{"id":new_id})

func transport_idle() -> bool:
	return actions._active == 0 and actions._queue.is_empty()

func exercise_zone_lifecycle() -> void:
	step = "controller native Cancel"
	editor.open_panel()
	if not await wait_ui(func(): return editor.available and settled(),"reopen zone catalog"): return
	editor.choose_zone_type(92)
	var first := Vector3i(170,57,164); var last := Vector3i(172,59,164)
	complete_rectangle(first,last)
	if not await wait_ui(zone_ready,"create before Cancel"): return
	var id := int(editor.zone_paint.area.id)
	await native("paint_counts_track",{"id":id,"tiles":9})
	if stopped: return
	editor.paint_view.cancel_button.pressed.emit()
	if not await wait_ui(transport_idle,"Cancel deletion"): return
	if not check(editor.panel.visible and editor.mode == "zone_select","Cancel must return to chooser"): return
	await native("paint_counts_absent",{"id":id})
	if stopped: return
	step = "controller empty Paint Escape"
	editor.choose_zone_type(92); complete_rectangle(first,last)
	if not await wait_ui(zone_ready,"create before erase-all"): return
	id = int(editor.zone_paint.area.id)
	await native("paint_counts_track",{"id":id,"tiles":9})
	if stopped: return
	editor.paint_view.buttons.erase.pressed.emit(); complete_rectangle(first,last)
	if not await wait_ui(zone_ready,"erase-all receipt"): return
	await native("paint_counts_track",{"id":id,"tiles":0})
	if stopped: return
	editor.paint_view.accept_button.pressed.emit()
	if not check(editor.mode == "paint" and editor.zone_paint != null,"empty Accept must remain in Paint"): return
	editor.handle_back()
	if not await wait_ui(transport_idle,"empty Escape deletion"): return
	if not check(not editor.panel.visible,"empty Escape must exit"): return
	await native("paint_counts_absent",{"id":id})
	if stopped: return
	step = "controller repaint Accept with pending corner"
	editor.open_panel()
	if not await wait_ui(func(): return editor.available and settled(),"reopen for repaint"): return
	editor.choose_zone_type(92); complete_rectangle(first,last)
	if not await wait_ui(zone_ready,"new zone before Accept"): return
	id = int(editor.zone_paint.area.id)
	await native("paint_counts_track",{"id":id,"tiles":9})
	if stopped: return
	editor.paint_view.accept_button.pressed.emit()
	if not check(editor.mode == "inspect" and int(editor.selected.id) == id,"Accept must open existing zone panel"): return
	editor.begin_paint(); editor.paint_view.buttons.erase.pressed.emit()
	complete_rectangle(first,first+Vector3i(1,0,0))
	if not await wait_ui(zone_ready,"existing repaint receipt"): return
	await native("paint_counts_track",{"id":id,"tiles":7})
	if stopped: return
	editor.paint_pointer(first,true); editor.paint_pointer(first,false)
	editor.paint_view.accept_button.pressed.emit()
	if not check(editor.mode == "inspect" and int(editor.selected.id) == id,"repaint Accept must ignore partial corner and retain edits"): return
	var area: Dictionary = editor.selected.duplicate(true)
	editor.close_panel()
	if not await wait_ui(transport_idle,"repaint close drains reads"): return
	await request({"action":12,"kind":1,"id":id,"expected_revision":area.revision})
	if not stopped: await native("paint_counts_absent",{"id":id})

func exercise_location_selector_views() -> void:
	step = "actual location selector views"
	var page := await request({"action":10,"kind":1,"zone_type":92,"operation":5,"paint_mode":1,"paint_z":164,"spans":spans([[57,170,3],[58,170,3],[59,170,3]])})
	if stopped: return
	var area: Dictionary = page.areas[0]
	await native("paint_counts_track",{"id":int(area.id),"tiles":9})
	if stopped: return
	editor.set_area_kind(1)
	if not editor.panel.visible: editor.open_panel()
	if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"selector zone catalog"): return
	editor.use_area(area)
	var reference: Array = JSON.parse_string(FileAccess.get_file_as_string(directory+"/native-location-metadata.json"))
	var observations: Array = []
	for kind in [2,4]:
		editor.zone_menu.controls.location.pressed.emit()
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"location chooser"): return
		editor.locations_view.create_buttons[kind-1].pressed.emit()
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy() and editor.locations_state.catalog_kind == kind,"location subselector"): return
		var selector = editor.locations_view.catalog_view
		var rows: Array = editor.locations_state.catalog_rows
		if not check(selector.visible and selector.choices.size() == rows.size(),"selector missing native catalog rows"): return
		for index in rows.size():
			selector.choices[index].mouse_entered.emit()
			var expected_lines: Array[String] = []
			var found := false
			for capture in reference:
				if capture.kind == ("temple" if kind == 2 else "guild") and int(capture.index) == index:
					found = true
					for line in str(capture.screen).split("\n"):
						var text := str(line).substr(43).strip_edges()
						if not text.is_empty(): expected_lines.append(text)
					break
			if not check(found and selector.detail.text == "\n".join(expected_lines),"native hover differs kind=%d index=%d actual=%s expected=%s" % [kind,index,selector.detail.text,"\n".join(expected_lines)]): return
			observations.append({"kind":kind,"index":index,"text":selector.detail.text})
			selector.choices[index].mouse_exited.emit()
			if not check(selector.detail.text == "","hover text persisted after exit"): return
		editor.handle_back()
		if not check(editor.locations_view.visible and editor.locations_state.catalog_kind == 0,"Back did not return to chooser"): return
		editor.handle_back()
	editor.close_panel()
	await request({"action":12,"kind":1,"id":int(area.id),"expected_revision":area.revision})
	if stopped: return
	await native("paint_counts_absent",{"id":int(area.id)})
	var output := FileAccess.open(directory+"/location-selector-view-comparison.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(observations,"  ")); output.close()

func exercise_location_creation() -> void:
	var references: Array = JSON.parse_string(FileAccess.get_file_as_string(directory+"/native-location-creation.json"))
	for reference in references:
		if reference.get("no_mutation",false): continue
		step = "actual location creation "+str(reference.scenario)
		var page := await request({"action":10,"kind":1,"zone_type":92,"operation":5,"paint_mode":1,"paint_z":164,"spans":spans([[57,170,3],[58,170,3],[59,170,3]])})
		if stopped: return
		var area: Dictionary = page.areas[0]
		await native("paint_counts_track",{"id":int(area.id),"tiles":9})
		if stopped: return
		if not editor.panel.visible: editor.open_panel()
		if not await wait_ui(func(): return editor.panel.visible and editor.available and settled(),"creation zone catalog"): return
		editor.use_area(area); editor.zone_menu.controls.location.pressed.emit()
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"creation locations"): return
		var kind := int(reference.kind)
		editor.locations_view.create_buttons[kind-1].pressed.emit()
		if kind in [2,4]:
			if not await wait_ui(func(): return settled() and not editor.locations_state.busy() and editor.locations_state.catalog_kind == kind,"creation choices"): return
			var chosen := -1
			for index in editor.locations_state.catalog_rows.size():
				var row: Dictionary = editor.locations_state.catalog_rows[index]
				if (kind == 4 and int(row.profession) == int(reference.profession)) or (kind == 2 and int(row.kind) == int(reference.practice_kind)+2 and int(row.id) == int(reference.practice_id)):
					chosen = index; break
			if not check(chosen >= 0,"native creation identity missing"): return
			editor.locations_view.catalog_view.choices[chosen].pressed.emit()
		if not await wait_ui(func(): return settled() and editor.stockpile_page == "types" and int(editor.selected.get("location_id",-1)) >= 0,"creation applied"): return
		await native("paint_counts_location_compare",{"id":int(area.id),"scenario":reference.scenario})
		if stopped: return
		var created_location_id := int(editor.selected.location_id)
		editor.zone_menu.controls.location.pressed.emit()
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"locations before removal"): return
		editor.locations_view.remove.pressed.emit()
		if not await wait_ui(func(): return settled() and editor.stockpile_page == "types" and int(editor.selected.get("location_id",-1)) == -1,"location removed"): return
		await native("paint_counts_location_removed",{"id":int(area.id),"scenario":reference.scenario})
		if stopped: return
		editor.zone_menu.controls.location.pressed.emit()
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"locations for reassignment"): return
		var existing_index := -1
		for index in editor.locations_state.rows.size():
			if int(editor.locations_state.rows[index].id) == created_location_id: existing_index = index; break
		if not check(existing_index >= 0,"created location absent from existing choices"): return
		editor.locations_view.choices[existing_index].pressed.emit()
		if not await wait_ui(func(): return settled() and editor.stockpile_page == "types" and int(editor.selected.get("location_id",-1)) == created_location_id,"location reassigned"): return
		await native("paint_counts_location_reassigned",{"id":int(area.id),"scenario":reference.scenario})
		if stopped: return
		editor.zone_menu.controls.location.pressed.emit()
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"locations before replacement"): return
		editor.locations_view.create_buttons[0].pressed.emit()
		if not await wait_ui(func(): return settled() and editor.stockpile_page == "types" and int(editor.selected.get("location_id",-1)) >= 0 and int(editor.selected.location_id) != created_location_id,"replacement created"): return
		await native("paint_counts_location_replaced",{"id":int(area.id),"previous":created_location_id,"scenario":reference.scenario})
		if stopped: return
		var replacement_id := int(editor.selected.location_id)
		editor.zone_menu.controls.location.pressed.emit()
		if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"locations before transfer"): return
		existing_index = -1
		for index in editor.locations_state.rows.size():
			if int(editor.locations_state.rows[index].id) == created_location_id: existing_index = index; break
		if not check(existing_index >= 0,"existing transfer destination absent"): return
		editor.locations_view.choices[existing_index].pressed.emit()
		if not await wait_ui(func(): return settled() and editor.stockpile_page == "types" and int(editor.selected.get("location_id",-1)) == created_location_id,"existing location transfer"): return
		await native("paint_counts_location_transferred",{"id":int(area.id),"previous":replacement_id,"scenario":reference.scenario})
		if stopped: return
		area = editor.selected.duplicate(true); editor.close_panel()
		if not await wait_ui(transport_idle,"creation close drains reads"): return
		for second_z in [165,164]:
			await exercise_second_location_zone(area,created_location_id,str(reference.scenario),second_z)
			if stopped: return
		page = await request({"action":9,"kind":1,"id":int(area.id)})
		if stopped: return
		area = page.areas[0]
		await request({"action":12,"kind":1,"id":int(area.id),"expected_revision":area.revision})
		if stopped: return
		await native("paint_counts_absent",{"id":int(area.id)})
		if stopped: return

func exercise_second_location_zone(first: Dictionary, location_id: int, scenario: String, second_z: int) -> void:
	step = "two-zone location "+scenario+" z="+str(second_z)
	var page := await request({"action":10,"kind":1,"zone_type":92,"operation":5,"paint_mode":1,"paint_z":second_z,"spans":spans([[57,170,1]])})
	if stopped: return
	var second: Dictionary = page.areas[0]
	await native("paint_counts_track",{"id":int(second.id),"tiles":1,"width":1,"height":1,"z":second_z})
	if stopped: return
	world.set_top_z(second_z); editor.open_panel()
	if not await wait_ui(func(): return editor.available and settled(),"second-zone catalog"): return
	editor.use_area(second); editor.zone_menu.controls.location.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"second-zone locations"): return
	var chosen := -1
	for index in editor.locations_state.rows.size():
		if int(editor.locations_state.rows[index].id) == location_id: chosen = index; break
	if not check(chosen >= 0,"multi-zone destination missing"): return
	editor.locations_view.choices[chosen].pressed.emit()
	if not await wait_ui(func(): return settled() and editor.stockpile_page == "types" and int(editor.selected.get("location_id",-1)) == location_id,"second-zone assigned"): return
	var probe := {"first":int(first.id),"second":int(second.id),"location":location_id,"scenario":scenario,"z":second_z}
	await native("paint_counts_location_multi",probe)
	if stopped: return
	editor.zone_menu.controls.location.pressed.emit()
	if not await wait_ui(func(): return settled() and not editor.locations_state.busy(),"second-zone removal list"): return
	editor.locations_view.remove.pressed.emit()
	if not await wait_ui(func(): return settled() and editor.stockpile_page == "types" and int(editor.selected.get("location_id",-1)) == -1,"second-zone removed"): return
	probe.remaining = true; await native("paint_counts_location_multi",probe)
	if stopped: return
	second = editor.selected.duplicate(true); editor.close_panel()
	if not await wait_ui(transport_idle,"second-zone close"): return
	await request({"action":12,"kind":1,"id":int(second.id),"expected_revision":second.revision})
	if stopped: return
	await native("paint_counts_absent",{"id":int(second.id)})
	world.set_top_z(164)

func exercise_empty_zone() -> void:
	step = "bridge zone erase-to-empty"
	var footprint := spans([[57,170,3],[58,170,3],[59,170,3]])
	var page := await request({"action":10,"kind":1,"zone_type":92,"operation":5,"paint_mode":1,"paint_z":164,"spans":footprint})
	if stopped: return
	var area: Dictionary = page.areas[0]
	var id := int(area.id)
	await native("paint_counts_track",{"id":id,"tiles":9})
	if stopped: return
	page = await request({"action":11,"kind":1,"id":id,"expected_revision":area.revision,"operation":5,"paint_mode":2,"paint_z":164,"spans":footprint})
	if stopped: return
	area = page.areas[0]
	if not check(int(area.id) == id and int(area.tile_count) == 0,"empty zone lost authoritative identity/count"): return
	await native("paint_counts_track",{"id":id,"tiles":0})
	if stopped: return
	await native("paint_counts_track",{"id":id,"tiles":0,"hidden":true})
	if stopped: return
	await request({"action":11,"kind":1,"id":id,"expected_revision":area.revision,"operation":5,"paint_mode":1,"paint_z":164,"spans":spans([[57,170,1]])},"Area is not visible")
	if stopped: return
	await native("paint_counts_track",{"id":id,"tiles":0,"hidden":false})
	if stopped: return
	page = await request({"action":11,"kind":1,"id":id,"expected_revision":area.revision,"operation":5,"paint_mode":1,"paint_z":164,"spans":spans([[57,170,1]])})
	if stopped: return
	area = page.areas[0]
	if not check(int(area.id) == id and int(area.tile_count) == 1,"repainting empty zone changed identity/count"): return
	await native("paint_counts_track",{"id":id,"tiles":1})
	if stopped: return
	await request({"action":12,"kind":1,"id":id,"expected_revision":area.revision})

func caption(expected: String) -> bool:
	var accepted := await wait_ui(func(): return editor.paint_view.zone_caption.text == expected,expected)
	count_observations.append({"step":step,"expected":expected,"actual":editor.paint_view.zone_caption.text,
		"generation":editor.paint_counts._generation,"view_z":int(world.get_top_z()),"accepted":accepted})
	return accepted

func exercise_counts() -> void:
	var tile := Vector3i(170,57,164)
	step = "implicit hover"; editor.paint_motion(tile)
	if not await caption("Bedroom: 0 + 1"): return
	step = "rectangle preview"; editor.paint_pointer(tile,true); editor.paint_pointer(tile,false)
	if not check(editor.dragging and editor.paint_state.cells.is_empty(),"first click must retain a corner without painting"): return
	editor.paint_motion(tile+Vector3i(2,2,0))
	if not await caption("Bedroom: 0 + 9"): return
	step = "local draft"; editor.paint_pointer(tile+Vector3i(2,2,0),true); editor.paint_pointer(tile+Vector3i(2,2,0),false)
	if not await caption("Bedroom: 9 + 0"): return
	if not await wait_ui(func(): return editor.zone_paint.ticket == 0,"immediate native creation"): return
	await native("paint_counts_track",{"id":int(editor.zone_paint.area.id),"tiles":9})
	if stopped: return
	step = "overlap add preview"
	editor.paint_pointer(tile+Vector3i(1,0,0),true); editor.paint_pointer(tile+Vector3i(1,0,0),false)
	editor.paint_motion(tile+Vector3i(3,2,0))
	if not await caption("Bedroom: 9 + 3"): return
	editor.paint_pointer(tile+Vector3i(3,2,0),true); editor.paint_pointer(tile+Vector3i(3,2,0),false)
	if not await caption("Bedroom: 12 + 0"): return
	await native("paint_counts_track",{"id":int(editor.zone_paint.area.id),"tiles":12,"width":4})
	if stopped: return
	step = "rectangle erase preview"
	editor.paint_pointer(tile,true); editor.paint_pointer(tile,false)
	editor.paint_view.buttons.erase.pressed.emit()
	if not check(editor.paint_tool == "rectangle" and editor.paint_erasing and editor.dragging and editor.paint_state.cells.size() == 12,"erase must preserve rectangle and first corner"): return
	editor.paint_motion(tile+Vector3i(1,1,0))
	if not await caption("Bedroom: 12 + 0"): return
	editor.paint_pointer(tile+Vector3i(1,1,0),true); editor.paint_pointer(tile+Vector3i(1,1,0),false)
	if not await caption("Bedroom: 8 + 1"): return
	step = "mixed rectangle erase"
	editor.paint_pointer(tile,true); editor.paint_pointer(tile,false); editor.paint_motion(tile+Vector3i(2,1,0))
	if not await caption("Bedroom: 8 + 4"): return
	editor.paint_pointer(tile+Vector3i(2,1,0),true); editor.paint_pointer(tile+Vector3i(2,1,0),false)
	if not await caption("Bedroom: 6 + 1"): return
	await native("paint_counts_track",{"id":int(editor.zone_paint.area.id),"tiles":6,"width":4})
	if stopped: return
	editor.paint_motion(tile+Vector3i(3,2,0))
	if not await caption("Bedroom: 6 + 0"): return
	step = "independent tool toggles"
	editor.paint_view.buttons.brush.pressed.emit()
	if not check(editor.paint_tool == "brush" and editor.paint_erasing,"brush lost erase state"): return
	editor.paint_view.buttons.rectangle.pressed.emit()
	if not check(editor.paint_tool == "rectangle" and editor.paint_erasing,"rectangle lost erase state"): return
	editor.paint_view.buttons.erase.pressed.emit()
	if not check(not editor.paint_erasing,"erase did not toggle off"): return
	editor.paint_motion(tile)
	if not await caption("Bedroom: 6 + 1"): return
	# Keep local geometry unchanged while native terrain changes at frame0.
	# Refresh must not depend only on local edits or advancing simulation ticks.
	step = "paused external wall"; await native("paint_counts_wall")
	if stopped or not await caption("Bedroom: 6 + 0"): return
	step = "paused external floor"; await native("paint_counts_floor")
	if stopped or not await caption("Bedroom: 6 + 1"): return
	step = "elevation"; world.set_top_z(165)
	if not await caption("Bedroom: 6 + 0"): return
	world.set_top_z(164)
	if not await caption("Bedroom: 6 + 0"): return
	editor.paint_motion(tile)
	if not await caption("Bedroom: 6 + 1"): return
