extends SceneTree
const Construction = preload("res://scripts/construction.gd")
class FakeWorld:
	extends Node
	var assets
	var calls: Array = []
	var result: Dictionary = {}
	var live := true
	var z := 1
	func poll_session(): return {"fortress_valid":true,"fortress_epoch":5,"paused":true}
	func session_generation():return 1
	func is_live(): return live
	func reconnect_management(): pass
	func poll_management(): return result.duplicate(true)
	func management_request(_domain, request):
		calls.append(request.duplicate(true)); return calls.size()
	func last_error(): return "test rejection"
	func get_top_z(): return z
	func floor_height(): return 0.1
	func ui_texture(token, index = -1): return assets.ui_texture(token,index)
	func ui_font_path(): return assets.ui_font_path()
	func ui_palette_color(index): return assets.ui_palette_color(index)
class FakeInteraction:
	extends Node
	signal command_results_received(results:Array)
	signal pause_requested(paused:bool)
	var shell_blocked := false
	var shell_enabled := false
	var construction_active := false
	var panel := PanelContainer.new()
	func _init(): add_child(panel)
	func set_play_enabled(value): panel.visible = value
	func cancel_selection(): pass

var failures := 0
var w
var service
var c
var host
var revision := 1
func check(value: bool, label: String):
	if not value: failures += 1; push_error(label)
func definition(key: String = "Chair", area: int = 1) -> Dictionary:
	return {"key":key,"name":key,"family":key,"supported":true,"reason":"","width":1,"height":1,"orientations":1,"area_mode":area,"max_width":31,"max_height":31,"max_depth":1,
		"footprints":[{"direction":0,"width":1,"height":1,"center_x":0,"center_y":0}]}
func reply(action: int, data: Dictionary = {}, status: int = 2) -> void:
	revision += 1
	w.result = {"world_epoch":5,"revision":revision,"request_seq":w.calls.size(),"status":status,"action":action}
	w.result.merge(data,true); service.poll()
func catalog_reply() -> void:
	reply(0,{"catalog":[definition(),definition("Construction:Wall",3)],"construction":{"list_revision":10},"next_cursor":0})
func preview_reply() -> void:
	reply(1,{"placement_valid":true,"construction":{"filters":[{"index":0,"quantity":1}],"valid_mask":[1],"pieces":[0]}})
func materials_reply(phase: int = 0) -> void:
	reply(63,{"construction":{"filter":0,"build_phase":phase,"list_revision":17,"total":1,"materials":[{"item_type":4,"item_subtype":-1,"mat_type":0,"mat_index":7,"count":2,"name":"granite","last_name":"granite","caption":""}]},"next_cursor":0})
func choose_site() -> void:
	c.choose_definition("Chair"); c.target_tile(Vector3i(2,3,1),true); service.poll(); preview_reply(); materials_reply()
func reopen() -> void:
	c.close_panel(); c.open_panel(); service.poll(); catalog_reply()
func pressure_press(kind: String, value: int) -> void:
	for control in c.pressure_view.find_children("*","BaseButton",true,false):
		if control.get_meta("pressure_kind","") == kind and control.get_meta("pressure_value",-999) == value:
			check(not control.disabled and control.tooltip_text.is_empty(),"native pressure control enabled without substitute tooltip")
			control.pressed.emit(); return
	check(false,"pressure control missing: " + kind)
func _initialize(): call_deferred("run")
func run():
	var lane = preload("res://tests/construction_acceptance_live.gd")
	var ids = lane.building_ids(JSON.parse_string('{"ids":[1491,1492]}'))
	check(ids.has(1491) and not ids.has(1490),"JSON native IDs normalize to integer identities")
	var assets := Df3dWorld.new(); root.add_child(assets)
	if not assets.load_assets(OS.get_environment("DF3D_DF_PATH")): quit(1); return
	w = FakeWorld.new(); w.assets = assets; root.add_child(w)
	var interaction := FakeInteraction.new(); root.add_child(interaction)
	service = preload("res://scripts/semantic_action_service.gd").new(); service.configure(w); root.add_child(service); service.set_process(false)
	host = preload("res://scripts/ui_host.gd").new(); host.interaction = interaction; root.add_child(host)
	c = Construction.new(); c.world = w; c.action_service = service; c.ui_host = host; c.interaction = interaction
	c.camera = Camera3D.new(); root.add_child(c.camera); root.add_child(c); host.register(c); c.set_process(false)
	c.open_panel(); service.poll()
	check(interaction.construction_active and w.calls.back().action == 0,"open claims channel and map input")
	var examples: Array = []
	for i in 200: examples.append({"size":(i+1)*1000,"race_id":-1,"name":""})
	examples[5] = {"size":6000,"race_id":42,"name":"synthetic dwarf"}
	reply(0,{"catalog":[definition()],"next_cursor":1,"construction":{"list_revision":10,"pressure_creatures":examples}})
	check(c.pressure_creatures == examples,"catalog retains exact pressure examples including unnamed bands")
	check(w.calls.back().cursor == 1 and w.calls.back().expected_list_revision == 10 and c.menu.catalog.is_empty(),"catalog pages stay pinned and leaves unavailable until complete")
	reply(0,{"catalog":[definition("Construction:Wall",3)],"next_cursor":0,"construction":{"list_revision":10}})
	check(c.catalog.size() == 2 and c.menu.catalog.has("Chair"),"catalog complete")
	check(c.pressure_creatures == examples,"later catalog page does not erase first-page examples")
	c.menu.activate(0,0); c.menu.activate(1,0)
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	host._input(escape)
	check(c.panel.visible and c.menu.path == [0],"host delegates Escape to menu ancestry")
	c.choose_definition("Chair")
	check(c.mode == "place" and not c.menu.visible,"leaf enters placement")
	c.target_tile(Vector3i(2,3,1),true); service.poll()
	check(w.calls.back().action == 1 and not w.calls.back().has("items"),"Preview carries site without retired input IDs")
	preview_reply()
	check(w.calls.back().action == 63 and w.calls.back().filter == 0,"Preview recipe requests grouped materials")
	materials_reply(1)
	check(not c.pending_read.is_empty() and c.material_view.locked,"pending builder locks choices")
	check(c.material_view.busy_indicator.visible,"pending lookup has visible activity")
	var animation_before:float=c.material_view.busy_indicator.elapsed
	c.material_view.busy_indicator._process(0.13)
	check(c.material_view.busy_indicator.elapsed!=animation_before,"busy activity advances independently of simulation")
	var call_count: int = w.calls.size()
	c._process(0.02); service.poll()
	check(w.calls.size() == call_count,"builder reads wait between polls")
	c._process(0.04); service.poll(); materials_reply()
	check(c.material_view.visible and not c.material_view.locked,"material result enables choices")
	check(not c.material_view.busy_indicator.visible,"ready picker stops busy activity")
	c.keep_building.button_pressed = true
	c.select_material(0,0,1); service.poll()
	check(w.calls.back().action == 2 and w.calls.back().selections[0].mat_index == 7 and w.calls.back().selections[0].expected_list_revision == 17 and not w.calls.back().has("items"),"Place sends stable grouped identity and revision once")
	call_count = w.calls.size(); c.place(); service.poll()
	check(w.calls.size() == call_count,"pending mutation never resubmits")
	reply(2,{"construction":{"first_building":42,"placed":1,"skipped":0},"message":"Native job queued"})
	check(c.placed_sites.has(42) and c.mode == "place" and not c.draft.preview_valid,"success records native identity and returns to fresh placement")
	# Cancel before dispatch while another owner holds the serialized channel.
	c.target_tile(Vector3i(3,3,1),true); service.poll(); preview_reply(); materials_reply()
	service.submit("construction",{"action":0},Callable()); service.poll()
	c.select_material(0,0,1)
	var cancelled: int = c.request_ticket; call_count = w.calls.size()
	c.handle_back(); service.poll()
	check(service.result(cancelled).outcome == "not_sent" and w.calls.size() == call_count and c.placed_sites.size() == 1,"queued Place cancellation never reaches DF or creates a confirmed site")
	reply(0)
	# Late sent preview cannot populate a cancelled draft.
	c.target_tile(Vector3i(4,3,1),true); service.poll(); c.handle_back(); preview_reply()
	check(not c.draft.preview_valid and not c.material_view.visible,"late preview cannot rearm cancelled view")
	# Rejected mutation clears readiness, with exact bridge text.
	c.target_tile(Vector3i(4,3,1),true); service.poll(); preview_reply(); materials_reply()
	c.select_material(0,0,1); service.poll()
	reply(2,{"message":"Materials moved"},3)
	check(not c.draft.preview_valid and c.message.text == "Materials moved" and not c.message.visible and c.placed_sites.size() == 1,"stale Place refusal remains diagnostic and does not rearm")
	c.target_tile(Vector3i(4,3,1),true); service.poll(); preview_reply(); materials_reply()
	c.select_material(0,0,1); service.poll()
	reply(2,{"message":"Painted 1 of 2; native construction rejected","construction":{"first_building":47,"placed":1,"skipped":1}},3)
	check(c.placed_sites.has(47) and not c.draft.preview_valid and c.message.text.contains("Placed 1; skipped 1") and not c.message.visible,"partial rejected batch preserves confirmed work without invented visible status or rearming")
	# Sent mutation survives the view; its receipt remains owned by the service.
	c.target_tile(Vector3i(5,3,1),true); service.poll(); preview_reply(); materials_reply()
	c.select_material(0,0,1); service.poll(); c.close_panel()
	reply(2,{"message":"Late placement confirmed","construction":{"first_building":99,"placed":1}})
	check(not c.placed_sites.has(99),"closed view ignores late mutation geometry")
	c.open_panel(); service.poll(); catalog_reply()
	check(service.last_detached_mutation("construction").result.message=="Late placement confirmed","reopen retains detached mutation receipt in service")
	check(not c.panel.find_children("*","Label",true,false).any(func(label):return label.text.contains("Previous request")),"receipt bookkeeping adds no invented visible copy")
	# Inspect includes the stable native building key when removing.
	c.begin_inspect(); c.send({"action":5,"origin":Vector3i(2,3,1)}); service.poll()
	reply(5,{"building_id":42,"construction":{"building_key":"Chair"},"build_stage":0,"max_stage":3,"jobs":1})
	c.remove_building(); service.poll()
	check(w.calls.back().action == 4 and w.calls.back().definition == "Chair" and w.calls.back().building_id == 42,"Remove pairs exact building id and key")
	reply(4,{"message":"Removed"})
	check(not c.placed_sites.has(42),"remove clears tracked site")
	c.send({"action":5,"origin":Vector3i(3,3,1)}); service.poll()
	reply(5,{"terrain_construction":true,"construction":{"building_key":"Construction:Wall"}})
	c.remove_building(); service.poll()
	check(w.calls.back().action == 6 and w.calls.back().origin == Vector3i(3,3,1),"terrain removal uses semantic tile")
	reply(6)
	c.choose_definition("Chair"); c.target_tile(Vector3i(6,3,1),true); service.poll(); preview_reply(); materials_reply()
	c.keep_building.button_pressed = false; c.select_material(0,0,1); service.poll()
	reply(2,{"construction":{"first_building":55,"placed":1,"skipped":0}})
	check(not c.panel.visible and not interaction.construction_active and c.placed_sites.has(55),"unchecked Keep building returns map ownership after confirmed placement")
	c.open_panel(); service.poll(); catalog_reply(); c.keep_building.button_pressed = true
	# Reversed rectangles and Z changes retain the right local ownership.
	c.choose_definition("Construction:Wall"); c.target_tile(Vector3i(8,8,1),true)
	check(c.corner == Vector3i(8,8,1) and c.mode == "place","first area corner stays local")
	c.target_tile(Vector3i(6,7,1),true); service.poll()
	check(w.calls.back().width == 3 and w.calls.back().height == 2 and w.calls.back().origin == Vector3i(6,7,1),"area second corner sends normalized rectangle")
	c.handle_back(); preview_reply()
	# Farm anchoring waits for native suitability before starting a rectangle.
	c.catalog.append(definition("FarmPlot",2))
	c.choose_definition("FarmPlot"); c.target_tile(Vector3i(8,8,1),true); service.poll()
	check(c.mode=="anchor" and c.corner.z<0 and w.calls.back().width==1,"farm first click checks its single tile")
	reply(1,{},3)
	check(c.mode=="place" and c.corner.z<0,"unsuitable farm first tile never anchors")
	c.target_tile(Vector3i(8,8,1),true); service.poll()
	reply(1,{"placement_valid":false})
	check(c.mode=="place" and c.corner.z<0,"invalid farm preview releases anchor wait")
	c.target_tile(Vector3i(8,8,1),true); service.poll(); c.handle_back(); preview_reply()
	check(c.corner.z<0 and not c.draft.preview_valid,"late farm anchor cannot restore cancelled gesture")
	c.target_tile(Vector3i(8,8,1),true); service.poll()
	call_count=w.calls.size()
	reply(1,{"placement_valid":true,"construction":{"filters":[],"valid_mask":[1],"pieces":[0]}})
	check(c.mode=="place" and c.corner==Vector3i(8,8,1) and w.calls.size()==call_count,"valid farm anchor sends no Place")
	c.target_tile(Vector3i(6,7,1),true); service.poll()
	check(w.calls.back().origin==Vector3i(6,7,1) and w.calls.back().width==3 and w.calls.back().height==2,"farm second click normalizes reverse rectangle")
	reply(1,{"placement_valid":true,"construction":{"filters":[],"valid_mask":[0,0,0,0,0,1],"pieces":[0,0,0,0,0,0]}})
	check(w.calls.back().action==2,"accepted irregular farm sends one Place")
	reply(2,{"construction":{"first_building":159,"placed":1,"skipped":0}})
	# Manual selection sees the same full list as native, with paging hidden.
	c.choose_definition("Chair"); c.target_tile(Vector3i(6,3,1),true); service.poll(); preview_reply()
	reply(63,{"construction":{"filter":0,"build_phase":0,"list_revision":32,"total":2,"materials":[{"item_type":4,"item_subtype":-1,"mat_type":0,"mat_index":8,"count":2,"name":"chert","last_name":"chert"}]},"next_cursor":1})
	check(w.calls.back().action == 63 and w.calls.back().cursor == 1 and w.calls.back().expected_list_revision == 32,"manual picker automatically collects pinned next page")
	check(c.material_view.locked,"partial snapshot stays locked while page is pending")
	reply(63,{"construction":{"filter":0,"build_phase":0,"list_revision":32,"total":2,"materials":[{"item_type":4,"item_subtype":-1,"mat_type":0,"mat_index":7,"count":2,"name":"granite","last_name":"granite"}]},"next_cursor":0})
	check(c.material_view.row_controls.size()==2 and c.draft.selections.is_empty() and not c.material_view.locked,"complete manual list unlocks without selecting or placing")
	c.handle_back()
	# A successful construction remembers identity only; reuse obtains a new,
	# paged snapshot for the new origin before issuing its single Place.
	# Native single-item Escape now closes the picker to the map.
	c.open_panel();service.poll();catalog_reply()
	c.choose_definition("Construction:Wall")
	c.target_tile(Vector3i(8,8,1),true); c.target_tile(Vector3i(8,8,1),true)
	service.poll(); preview_reply(); materials_reply(); c.select_material(0,0,1); service.poll()
	reply(2,{"construction":{"first_building":58,"placed":1,"skipped":0}})
	check(c.last_material.mat_index == 7 and not c.last_material.has("expected_list_revision"),"last material remembers identity without stale counts or revision")
	c.set_material_strategy("last")
	check(c.use_last.button_pressed and c.use_last.text=="Use last material\n Granite","native last-material option exposes remembered name")
	c.target_tile(Vector3i(9,8,1),true); c.target_tile(Vector3i(9,8,1),true); service.poll(); preview_reply()
	reply(63,{"construction":{"filter":0,"build_phase":0,"list_revision":33,"total":2,"materials":[{"item_type":4,"item_subtype":-1,"mat_type":0,"mat_index":8,"count":2,"name":"chert","last_name":"chert"}]},"next_cursor":1})
	check(w.calls.back().action == 63 and w.calls.back().cursor == 1 and w.calls.back().expected_list_revision == 33,"last-material lookup pages current origin with fresh revision")
	reply(63,{"construction":{"filter":0,"build_phase":0,"list_revision":33,"total":2,"materials":[{"item_type":4,"item_subtype":-1,"mat_type":0,"mat_index":7,"count":2,"name":"granite","last_name":"granite"}]},"next_cursor":0})
	check(w.calls.back().action == 2 and w.calls.back().selections[0].expected_list_revision == 33 and w.calls.back().selections[0].mat_index == 7,"reuse places only matching identity from new snapshot")
	reply(2,{"message":"Materials moved"},3)
	check(not c.draft.preview_valid and c.last_material.mat_index == 7,"refused reuse retains preference but never rearms placement")
	c.target_tile(Vector3i(10,8,1),true); c.target_tile(Vector3i(10,8,1),true); service.poll(); preview_reply()
	call_count = w.calls.size()
	reply(63,{"construction":{"filter":0,"build_phase":0,"list_revision":34,"total":1,"materials":[{"item_type":4,"item_subtype":-1,"mat_type":0,"mat_index":8,"count":2,"name":"chert","last_name":"chert"}]},"next_cursor":0})
	check(w.calls.size() == call_count and c.material_strategy == "last" and c.material_view.status.text.is_empty() and not c.material_view.status.visible,"missing last material preserves preference and requires explicit replacement without authored diagnostic prose")
	# Native zero-required overlap waits for a row click even with Last selected.
	c.material_strategy = "last"; c.draft.filters[0].quantity = 0
	var old_rows: Array = c.draft.snapshots[0].rows
	var remembered: Dictionary = c.last_material.duplicate(true); remembered.count = 2
	c.draft.snapshots[0].rows = [remembered]
	c.apply_last_material(0)
	check(w.calls.size()==call_count and c.mode=="materials" and c.material_strategy=="last" and c.draft.selections.is_empty(),"zero-material Last does not auto-place, select an item or replace preference")
	c.draft.snapshots[0].rows = old_rows; c.draft.filters[0].quantity = 1; c.material_strategy = "after"
	c.handle_back(); reopen()
	c.choose_definition("Chair"); c.target_tile(Vector3i(2,2,1)); w.z = 2; c._process(0.01)
	check(c.draft.origin.z < 0,"ordinary elevation change cancels site")
	var stairs := definition("Construction:Stairs",4); stairs.max_depth = 31
	c.catalog.append(stairs); c.choose_definition("Construction:Stairs")
	check(host.allows_elevation_input(),"placement grants elevation navigation")
	call_count=w.calls.size()
	c.target_tile(Vector3i(3,4,2),true); c._process(1.0); service.poll()
	check(w.calls.size()==call_count and c.request_ticket==0,"delayed first stair anchor does not submit invalid one-level Preview")
	w.z = 4; c._process(0.01)
	check(c.corner == Vector3i(3,4,2),"stairs retain the first corner across elevations")
	c.target_tile(Vector3i(3,4,4),true); service.poll()
	check(w.calls.back().depth == 3 and w.calls.back().origin == Vector3i(3,4,2),"stairs Preview spans selected elevations")
	check(not host.allows_elevation_input(),"checking locks elevation before material lookup")
	c.handle_back(); preview_reply()
	# Track preserves endpoint order and draws semantic path cells, never a rectangle.
	var track := definition("Construction:Track",3);track.family="Construction";track.subtype_key="Track"
	c.catalog.append(track);c.choose_definition("Construction:Track");c.placed_sites.clear()
	call_count=w.calls.size()
	var start:=Vector3i(9,8,4)
	c.target_tile(start);c._process(1.0);service.poll()
	check(w.calls.size()==call_count and c.corner.z<0,"Track hover before first endpoint sends no one-tile Preview")
	c.target_tile(start,true);c._process(1.0);service.poll()
	check(c.corner==start and w.calls.size()==call_count,"first Track endpoint retained without invalid Preview")
	w.z=5;c._process(0.01)
	check(c.corner==start and host.allows_elevation_input(),"Track endpoint survives elevation navigation")
	var destination:=Vector3i(8,7,5)
	c.target_tile(destination);c._process(0.2);service.poll()
	check(w.calls.back().origin==start and w.calls.back().connected_track_destination==destination and w.calls.back().width==1 and w.calls.back().depth==1,"controller sends ordered Track endpoints")
	var path: Array=[start,Vector3i(9,7,4),Vector3i(8,7,4),destination]
	reply(1,{"placement_valid":true,"construction":{"filters":[{"index":0,"quantity":4}],"connected_track":{"status":0,"path":path}}})
	var outline_sites: Array=c.visible_outline_sites()
	check(outline_sites.size()==1 and outline_sites[0].origin==destination,"upper-elevation outline contains only actual path cells")
	w.z=4;c._process(0.01);outline_sites=c.visible_outline_sites()
	check(outline_sites.size()==3 and outline_sites[1].origin==Vector3i(9,7,4) and outline_sites[2].origin==Vector3i(8,7,4),"bent Track preview follows path at current elevation")
	check(outline_sites[0].width==1 and outline_sites[0].height==1,"Track preview does not fill bounding rectangle")
	c._receive_result({"status":Construction.Status.Rejected},{"action":1})
	check(c.draft.track_path.is_empty() and c.visible_outline_sites().size()==1,"rejected Track preview removes obsolete path geometry")
	check(c.outline.mesh.get_surface_count()==1 and c.outline.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==8,"rejection redraws only the retained endpoint")
	c.handle_back()
	check(c.corner.z<0 and c.draft.track_path.is_empty(),"Track cancellation clears path and anchor")
	# Overlay input is rejected before camera picking.
	host.set_overlay_blocked(true); call_count = w.calls.size()
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	c._unhandled_input(click)
	check(w.calls.size() == call_count,"overlay blocks map picking")
	host.set_overlay_blocked(false)
	# An unknown sent mutation is never retried; a later receipt remains retained.
	c.choose_definition("Chair"); c.target_tile(Vector3i(7,3,2),true); service.poll(); preview_reply(); materials_reply()
	c.select_material(0,0,1); service.poll(); call_count = w.calls.size()
	service.poll(service.timeout_seconds + 1)
	check(c.request_ticket == 0 and not c.draft.preview_valid and c.message.text.contains("unknown") and not c.message.visible, "sent timeout retains diagnostic outcome without rearming or authored visible copy")
	c.place(); service.poll()
	check(w.calls.size() == call_count,"unknown mutation is not replayed")
	c.close_panel(); reply(2,{"message":"Late timeout resolution","construction":{"first_building":101,"placed":1}})
	c.open_panel(); service.poll(); catalog_reply()
	check(service.last_detached_mutation("construction").result.message=="Late timeout resolution" and not c.placed_sites.has(101),"late timeout resolution is retained without mutating cancelled geometry")
	check(not c.panel.find_children("*","Label",true,false).any(func(label):return label.text.contains("Previous request")),"late timeout resolution adds no authored receipt line")
	# An epoch replacement removes confirmed sites as well as draft data.
	c.placed_sites[202] = {"origin":Vector3i(1,1,2),"width":1,"height":1}
	c.pressure_creatures = examples.duplicate(true)
	w.result = {"world_epoch":6,"revision":revision+1}; service.poll()
	check(c.catalog.is_empty() and c.pressure_creatures.is_empty() and c.placed_sites.is_empty() and c.last_material.is_empty() and not c.draft.preview_valid,"epoch replacement invalidates local identities, creature examples and remembered material")
	# Transport loss clears local identity; no mutation can survive as a new draft.
	w.result = {"transport_alive":false}; service.poll()
	check(c.catalog.is_empty() and c.placed_sites.is_empty() and c.request_ticket == 0,"disconnect clears drafts and catalog")
	c.set_play_enabled(false)
	check(not c.panel.visible and not interaction.construction_active,"save/menu state releases local input")
	call_count = w.calls.size(); c.open_panel(); service.poll()
	check(w.calls.size() == call_count and not c.panel.visible,"disabled gameplay refuses reopen")
	# Actual native speed buttons drive the draft; a changed choice invalidates
	# pending geometry/material decisions and stays in the next semantic intent.
	c.set_play_enabled(true); c.mode = "place"; c.request_ticket = 0
	var rollers := definition("Rollers"); rollers.orientations = 15; rollers.footprints = []
	for direction in 4:
		rollers.footprints.append({"direction":direction,"width":1,"height":1,"center_x":0,"center_y":0})
	c.draft.choose(rollers); c.rebuild_orientation()
	var speed_buttons: Array = []
	for child in c.orientation.get_children():
		if child.has_meta("roller_speed"): speed_buttons.append(child)
	check(speed_buttons.size() == 5 and speed_buttons[4].button_pressed,"Rollers defaults to native fastest speed")
	for index in speed_buttons.size():
		check(speed_buttons[index].position == Vector2(136+index*40,24),"native Roller buttons retain one character-column gap")
	for speed in [10000,20000,30000,40000,50000]:
		for child in c.orientation.get_children():
			if child.get_meta("roller_speed",0) == speed:
				check(not child.disabled and child.tooltip_text.is_empty(),"speed button enabled without invented tooltip")
				child.pressed.emit(); break
		check(c.draft.request(2).roller_speed == speed and not c.draft.preview_valid,"speed choice reaches Place intent and invalidates preview")
	c.draft.choose(definition("Chair"))
	check(not c.draft.request(2).has("roller_speed"),"Roller speed cannot leak into other building requests")
	var track_stop := definition("Trap:TrackStop"); track_stop.family = "Trap"; track_stop.subtype_key = "TrackStop"
	c.draft.choose(track_stop); c.rebuild_orientation()
	check(c.orientation_panel.visible and c.orientation.get_child_count() == 10,"TrackStop shows ten native option buttons without fake orientation bits")
	check(c.draft.request(2).track_stop == {"friction":50000,"dump_direction":0},"TrackStop native defaults")
	for direction in 5:
		for friction in [10,50,500,10000,50000]:
			for choice in [["dump_direction",direction],["friction",friction]]:
				for child in c.orientation.get_children():
					if child.get_meta("track_option","") == choice[0] and child.get_meta("track_value",-1) == choice[1]:
						child.pressed.emit(); break
			check(c.draft.request(2).track_stop == {"friction":friction,"dump_direction":direction},"independent TrackStop choices survive in Place request")
	c.draft.choose(track_stop)
	check(c.draft.request(2).track_stop == {"friction":50000,"dump_direction":0},"reopen resets TrackStop options")
	c.draft.choose(definition("Chair"))
	check(not c.draft.request(2).has("track_stop"),"TrackStop options cannot leak into another building")
	c.pressure_creatures = examples.duplicate(true)
	var plate := definition("Trap:PressurePlate"); plate.family = "Trap"; plate.subtype_key = "PressurePlate"
	c.draft.choose(plate); c.rebuild_orientation()
	check(c.orientation_panel.visible and c.pressure_view != null,"native pressure controls are present")
	pressure_press("resets",0); check(not c.draft.pressure_plate.resets,"One use only selects native reset flag")
	pressure_press("water",1); pressure_press("water_depth",3)
	check(c.draft.pressure_plate.water_min == 3 and c.draft.pressure_plate.water_max == 3,"native depth button selects range")
	pressure_press("track",1); pressure_press("track_min",1)
	check(c.draft.pressure_plate.track_min == 50,"native cart add button updates minimum")
	pressure_press("units",1); pressure_press("citizens",1); pressure_press("creature",6000)
	check(c.pressure_view.rows.get_children().all(func(control): return control.size.y == 12),"creature rows preserve native twelve-pixel hit areas")
	check(c.draft.pressure_plate.unit_min == 6000 and c.draft.pressure_plate.unit_max == 6999,"native creature button selects size band")
	pressure_press("units",0); pressure_press("units",1)
	check(c.draft.pressure_plate.citizens and c.draft.pressure_plate.unit_min == 6000,"trigger controls preserve hidden settings")
	c.request_ticket = 123; c.update_buttons()
	check(c.pressure_view.find_children("*","BaseButton",true,false).all(func(control): return control.disabled),"pressure controls lock while request is outstanding")
	c.request_ticket = 0; c.update_buttons()
	c.pressure_creatures = examples.duplicate(true); c.close_panel()
	check(c.pressure_creatures.is_empty(),"close retires pressure examples")
	# Native keep_options_reference: checked Keep building restarts Pressure Plate
	# with default options.
	# Restore the fake connection after the earlier disconnect test, including
	# the service's automatic read-only recovery claim.
	w.result = {"world_epoch":5,"revision":revision+1}; service.poll(); catalog_reply()
	for complete in [false,true]:
		c.open_panel(); service.poll()
		reply(0,{"catalog":[plate],"construction":{"list_revision":10,"pressure_creatures":examples},"next_cursor":0})
		c.keep_building.button_pressed = true
		c.choose_definition("Trap:PressurePlate")
		check(c.footer.visible,"native hover correction restores pressure placement footer")
		check(c.draft.pressure_plate == c.draft.PRESSURE_DEFAULT,"reopened pressure options match native defaults")
		pressure_press("water",1); pressure_press("water_depth",3)
		c.target_tile(Vector3i(2,3,1),true); service.poll(); preview_reply(); materials_reply()
		check(c.mode == "materials","pressure placement reaches material selection")
		if complete:
			c.select_material(0,0,1); service.poll()
			reply(2,{"construction":{"first_building":99,"placed":1,"skipped":0}})
		else: c.handle_back()
		if complete:
			check(c.panel.visible and interaction.construction_active and c.mode=="place","checked Pressure Plate placement retains construction ownership")
			check(c.draft.pressure_plate==c.draft.PRESSURE_DEFAULT,"checked Pressure Plate placement resets native options")
			c.close_panel()
		else:
			check(not c.panel.visible and not interaction.construction_active,"pressure cancellation returns map ownership")
		check(c.draft.definition.is_empty() and c.pressure_creatures.is_empty(),"pressure exit retires draft and example metadata")
	var bridge_keep:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bridge_placement.json")).keep_direction_reference
	for native in bridge_keep.cases:
		var keep_bridge:=definition("Bridge");keep_bridge.orientations=31;keep_bridge.footprints=[]
		for facing in 5:keep_bridge.footprints.append({"direction":facing,"width":1,"height":1,"center_x":0,"center_y":0})
		c.open_panel();service.poll();reply(0,{"catalog":[keep_bridge],"construction":{"list_revision":10},"next_cursor":0})
		c.choose_definition("Bridge");c.keep_building.button_pressed=true
		check(c.draft.orient(maxi(0,int(native.before_direction)),int(native.before_direction)<0),"native initial bridge direction is selectable")
		c.mode="placing"
		c._receive_result({"status":2,"construction":{"placed":1,"first_building":999}}, {"action":2,"definition":"Bridge","origin":Vector3i(2,3,1),"width":1,"height":1})
		check(c.panel.visible and c.mode=="place" and c.draft.direction==int(native.after.direction) and not c.draft.retracting,"Keep building resets Bridge direction and retracting option to native defaults")
		c.close_panel()
	var shortage_evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/material_candidates.json")).closest_shortage_capture
	for shortage_case in [[0,5],[3,5],[0,1]]:
		var supply: int = shortage_case[0]
		var required: int = shortage_case[1]
		c.panel.show(); c.mode = "materials"; c.material_strategy = "closest"; c.filter_position = 0
		c.draft.definition = {"key":"Construction:Track"}; c.draft.filters = [{"index":0,"quantity":required}]
		c.draft.snapshots[0] = {"revision":1,"next_cursor":0,"rows":[] if supply==0 else shortage_evidence.rows}
		c.update_material_shortage()
		check(c.shortage_panel.visible and not c.material_view.visible and not c.footer.visible,"native shortage replaces picker with compact message")
		var expected := "No access to 5 building material non-economic items"
		if required==1: expected = "No access to building material non-economic item"
		if supply==0: expected = "Needs building material non-economic item\n - mine rock or chop trees\n" + expected
		check(c.shortage_text.text==expected,"shortage uses captured native copy")
		check(c.shortage_text.get_theme_color("font_color")==w.ui_palette_color(12),"native shortage text uses installed LRED")
		check(c.shortage_text.get_theme_constant("line_spacing")==0,"native shortage uses contiguous twelve-pixel lines")
		check(c.shortage_panel.custom_minimum_size.x==448,"native singular shortage retains the full message width")
		var shortage_style := c.shortage_panel.get_theme_stylebox("panel") as StyleBoxTexture
		check(shortage_style != null and shortage_style.texture==c.art.texture("HOVER_RECTANGLE"),"native shortage uses original hover frame")
		var shortage_calls: int = w.calls.size()
		for frame in 12: c._process(0.02)
		check(w.calls.size()==shortage_calls and c.shortage_panel.visible,"native shortage does not automatically refresh candidates or replay placement")
		c.handle_back()
		check(not c.panel.visible and not c.shortage_panel.visible and c.material_strategy=="closest","shortage cancel clears visible state and retains preference")
	var furniture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/furniture_material_copy.json"))
	for native in furniture.native_closest_shortage.cases + furniture.common_closest_shortage.cases:
		c.panel.show(); c.mode = "materials"; c.material_strategy = "closest"; c.filter_position = 0
		c.draft.definition = {"key":str(native.kind).capitalize()}; c.draft.filters = [{"index":0,"quantity":1}]
		c.draft.snapshots[0] = {"revision":1,"next_cursor":0,"rows":[]}
		c.update_material_shortage()
		var expected: Array[String] = []
		for line in native.empty_click.lines:
			if str(line.text).contains("Needs ") or str(line.text).contains("make at a workshop") or str(line.text).contains("No access to "):
				expected.append(str(line.text).substr(6))
		check(expected.size()==3 and c.shortage_text.text=="\n".join(expected),"Furniture shortage matches captured native lines, including throne")
		check(c.shortage_panel.visible and not c.material_view.visible,"Furniture shortage replaces the picker")
		var shortage_calls: int = w.calls.size()
		for frame in 12: c._process(0.02)
		check(w.calls.size()==shortage_calls,"Furniture shortage sends no automatic retry")
		c.handle_back()
		check(not c.panel.visible and not c.shortage_panel.visible and c.material_strategy=="closest","Furniture shortage cancellation returns to map retaining Closest")
	var terrain:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/stairs_placement.json"))
	var native_options:Array=furniture.single_item_options_reference.cases.duplicate(true)
	for captured in furniture.remaining_single_item_reference.cases:
		native_options.append({"definition":captured.definition,"before_closest":captured.placement,"empty_closest":captured.shortage,"strategies":["closest"]})
	for native in native_options:
		c.panel.show();c.mode="place";c.material_strategy="after"
		c.draft.definition={"key":native.definition};c.selected_label="fixture menu label"
		c.footer.show();c.update_prompt()
		var native_heading:=""
		for line in native.before_closest.lines:
			if str(line.text).contains("Click a tile to place"):native_heading=str(line.text).split(".")[0].strip_edges()+"."
		check(not native_heading.is_empty() and c.heading.text==native_heading,"single-item placement uses native full heading rather than menu label")
		check(c.footer.visible and not c.use_closest.disabled,"single-item native Closest control is available")
		c.mode="materials";c.material_view.show()
		var before:int=w.calls.size()
		c.handle_back()
		check(not c.panel.visible and not c.material_view.visible and w.calls.size()==before,"all22 manual picker cancellations return to map without submission")
		for strategy in native.get("strategies",["after","closest"]):
			c.panel.show();c.mode="materials";c.material_strategy=strategy;c.filter_position=0
			c.draft.definition={"key":native.definition};c.draft.filters=[{"index":0,"quantity":1}]
			c.draft.snapshots[0]={"revision":1,"next_cursor":0,"rows":[]}
			c.update_material_shortage()
			var expected:Array[String]=[]
			var column:=-1
			var captured:Dictionary=native.empty_manual if strategy=="after" else native.empty_closest
			for line in captured.lines:
				var text:=str(line.text)
				if text.contains("Needs "):column=text.find("Needs ")
				if text.contains("Needs ") or text.contains("No access to ") or text.contains(" - make"):
					expected.append(text.substr(column))
			check(not expected.is_empty() and c.shortage_panel.visible and c.shortage_text.text=="\n".join(expected),"all22 manual/Closest shortages reproduce native text including Instrument exception")
			before=w.calls.size()
			for frame in 12:c._process(0.02)
			check(w.calls.size()==before,"single-item shortage does not retry or submit")
			c.handle_back()
			check(not c.panel.visible and not c.shortage_panel.visible and c.material_strategy==strategy,"single-item shortage returns to map and preserves preference")
	for native in terrain.terrain_cancel_reference.cases:
		var kind:String={"WALL":"Wall","FLOOR":"Floor","RAMP":"Ramp","FORTIFICATION":"Fortification","STAIR_UPDOWN":"Stairs"}[native.definition.kind]
		check(native.cancel_focus==["dwarfmode/Default"],"native normal material cancellation reference returns to map")
		c.panel.show();c.mode="materials";c.material_strategy="after";c.shortage_panel.hide();c.material_view.show()
		c.draft.definition={"key":"Construction:"+kind}
		var before:int=w.calls.size()
		c.handle_back()
		check(not c.panel.visible and not c.material_view.visible and c.draft.definition.is_empty(),"normal terrain picker Escape clears draft and returns to map")
		check(w.calls.size()==before,"normal terrain picker cancellation never submits construction")
	for strategy in ["after","closest"]:
		for native in terrain.terrain_shortage_reference[strategy].cases:
			var v:Dictionary=native.definition
			var kind:String={"WALL":"Wall","FLOOR":"Floor","RAMP":"Ramp","FORTIFICATION":"Fortification","STAIR_UPDOWN":"Stairs"}[v.kind]
			c.panel.show();c.mode="materials";c.material_strategy=strategy;c.filter_position=0
			c.draft.definition={"key":"Construction:"+kind};c.draft.filters=[{"index":0,"quantity":int(v.width)*int(v.height)*int(v.depth)}]
			c.draft.snapshots[0]={"revision":1,"next_cursor":0,"rows":[{"count":int(v.available)}]}
			c.update_material_shortage()
			var expected:Array[String]=[]
			for line in native.lines:
				if str(line.text).contains("Needs ") or str(line.text).contains("No access to ") or str(line.text).contains("mine rock"):expected.append(str(line.text).substr(6))
			check(not expected.is_empty() and c.shortage_panel.visible and c.shortage_text.text=="\n".join(expected),"terrain shortage uses exact native recipe/mode copy")
			var before:int=w.calls.size()
			for frame in 12:c._process(0.02)
			check(w.calls.size()==before,"terrain shortage never places or retries")
			c.handle_back()
			check(not c.panel.visible and not c.shortage_panel.visible and c.material_strategy==strategy,"native terrain shortage Escape returns map and preserves strategy")
	var bridge_options:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/bridge_placement.json"))
	for native in bridge_options.native_material_options.cases:
		for shortage in native.shortages:
			c.panel.show();c.mode="materials";c.material_strategy=shortage.strategy;c.filter_position=0
			c.draft.definition={"key":"Bridge"};c.draft.filters=[{"index":0,"quantity":int(native.required)}]
			c.draft.snapshots[0]={"revision":1,"next_cursor":0,"rows":[{"count":int(shortage.available)}]}
			c.update_material_shortage()
			var expected:Array[String]=[]
			for line in shortage.lines:
				if str(line.text).contains("Needs ") or str(line.text).contains("No access to ") or str(line.text).contains("mine rock"):expected.append(str(line.text).substr(6))
			check(not expected.is_empty() and c.shortage_panel.visible and c.shortage_text.text=="\n".join(expected),"Bridge manual/inherited Closest shortage matches native copy")
			c.handle_back();check(not c.panel.visible and c.material_strategy==shortage.strategy,"Bridge shortage Escape returns to map preserving preference")
	var windmill: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/windmill.json"))
	for available in [0,2]:
		c.panel.show(); c.mode="materials"; c.material_strategy="closest"; c.filter_position=0
		c.draft.definition={"key":"Windmill"}; c.draft.filters=[{"index":0,"quantity":4}]
		c.draft.snapshots[0]={"revision":1,"next_cursor":0,"rows":[{"count":available}]}
		c.update_material_shortage()
		var native: Dictionary = windmill.native_closest.capture.shortage if available==0 else windmill.native_closest.capture.partial
		var expected: Array[String]=[]
		for line in native.lines:
			if int(line.y) in [5,6,7]: expected.append(str(line.text).substr(6))
		check(expected.size()==3 and c.shortage_text.text=="\n".join(expected),"Windmill zero/partial shortage reproduces native copy")
		c.handle_back()
		check(not c.panel.visible and c.material_strategy=="closest","Windmill shortage cancellation retains Closest")
	var magma:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/construction/magma_placement.json"))
	for native in magma.native_closest.cases:
		for shortage in native.shortages:
			c.panel.show();c.mode="materials";c.material_strategy="closest";c.filter_position=0
			c.draft.definition={"key":native.definition};c.draft.filters=[];c.draft.snapshots.clear()
			for filter in native.filters:
				var index:=int(filter.filter);var anvil:bool=native.definition=="Workshop:MagmaForge" and index==0
				var missing:bool=shortage.variant=="none" or (shortage.variant=="no_anvil" and anvil) or (shortage.variant=="no_material" and not anvil)
				c.draft.filters.append({"index":index,"quantity":1})
				c.draft.snapshots[index]={"revision":1,"next_cursor":0,"rows":[] if missing else [{"count":1}]}
			c.update_material_shortage()
			var expected:Array[String]=[]
			for line in shortage.lines:
				var text:=str(line.text)
				if text.contains("Needs ") or text.contains("No access to ") or text.contains(" - "):expected.append(text.substr(6))
			check(c.shortage_panel.visible and c.shortage_text.text=="\n".join(expected),"Magma shortage reproduces all native requirements in order")
			c.handle_back()
			check(not c.panel.visible and c.material_strategy=="closest","Magma shortage cancels to map retaining Closest")
	print("CONSTRUCTION_TEST ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
