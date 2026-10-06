extends SceneTree
const Controller = preload("res://scripts/areas.gd")
var failures := 0


class FakeWorld:
	extends RefCounted
	func _init() -> void:
		# This fixture intentionally has no installed art; asset parity is covered
		# by area_menus_capture with a real Df3dWorld asset source.
		preload("res://scripts/original_ui.gd")._warned_assets_unavailable = true
	var calls: Array = []
	var seq := 0
	var live := true
	var zone_overlays := false
	var unit_tiles: Dictionary = {}
	func unit_tile(id: int) -> Vector3i: return unit_tiles.get(id,Vector3i(-1,-1,-1))

	func set_zone_overlays_visible(value: bool):
		zone_overlays = value
	var state: Dictionary = {"world_epoch": 42, "revision": 1, "status": 0}

	func is_live():
		return live

	func reconnect_management():
		pass

	func poll_management():
		return state

	var top_z := 2
	func get_top_z():
		return top_z

	func map_size():
		return Vector3(48, 12, 48)

	func last_error():
		return "test unavailable"

	func management_request(_domain, data):
		return area_request(data)

	func area_request(data):
		calls.append(data.duplicate(true))
		seq += 1
		return seq


class FakeInteraction:
	extends Node3D
	var panel := PanelContainer.new()
	var shell_blocked := false
	var shell_enabled := false
	var construction_active := false
	var audio: Node

	func _ready():
		add_child(panel)
		panel.add_child(VBoxContainer.new())

	func set_play_enabled(value: bool):
		panel.visible = value

	func cancel_selection():
		pass


func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)


func _initialize():
	call_deferred("run")


func run():
	var w := FakeWorld.new()
	var interaction := FakeInteraction.new()
	root.add_child(interaction)
	var c := Controller.new()
	c.world = w
	c.interaction = interaction
	var service := preload("res://scripts/semantic_action_service.gd").new()
	service.configure(w)
	root.add_child(service)
	service.set_process(false)
	c.action_service = service
	c.ui_host = preload("res://scripts/ui_host.gd").new()
	c.ui_host.interaction = interaction
	root.add_child(c.ui_host)
	root.add_child(c)
	c.ui_host.register(c)
	c.set_process(false)
	c.open_panel()
	service.poll()
	check(not w.zone_overlays, "stockpile panel keeps zone overlays hidden")
	check(w.calls[-1].action == 0, "fresh connection claims read-only catalog")
	w.state = {"revision": 2, "world_epoch": 42, "request_seq": w.seq, "action": 0, "status": 2}
	service.poll()
	check(w.calls[-1].action == 7, "area catalog follows ownership claim")
	w.state = {
		"revision": 3,
		"world_epoch": 42,
		"request_seq": w.seq,
		"action": 7,
		"status": 2,
		"area_choices": [{"id": 2, "name": "Bedroom"}]
	}
	service.poll()
	check(c.available and c.zone_picker.item_count == 1, "native zone choices accepted")
	var pile: Dictionary = {
		"id": 31,
		"revision": 9007199254740993,
		"kind": 0,
		"name": "Custom pile",
		"origin": Vector3i(3, 4, 2),
		"width": 50,
		"tile_count": 2500,
		"height": 50,
		"extents": PackedByteArray(),
		"categories": 8202,
		"barrels": 1500,
		"bins": 1200,
		"wheelbarrows": 4,
		"links_only": true,
		"active": true,
		"owner_id": -1,
		"owner_name": "",
		"owner_allowed": false,
		"gives": [32],
		"takes": [33]
	}
	c.use_area(pile)
	c.stockpile_control("containers")
	check(c.storage_view.visible and c.stockpile_view.visible,"storage popup keeps native type panel visible")
	c.storage_view.controls.bins[1].pressed.emit(); service.poll()
	check(w.calls[-1] == {"action":11,"id":31,"kind":0,"expected_revision":pile.revision,"bins":1201},"storage edit sends only chosen value and exact inspected revision")
	var storage_reply: Dictionary = pile.duplicate(true); storage_reply.bins = 1201; storage_reply.revision += 1
	w.state = {"world_epoch":42,"revision":4,"request_seq":w.seq,"status":2,"action":11,"areas":[storage_reply]}
	service.poll()
	check(c.stockpile_page == "containers" and c.storage_view.labels.bins.text == "1201","authoritative storage reply updates open popup")
	c.handle_back(); c.use_area(pile)
	check(c.stockpile_view.visible and not c.category_grid.visible, "selected stockpile uses native preset panel")
	var preset_count := w.calls.size()
	c.choose_preset(0)
	check(c.stockpile_page == "settings" and w.calls.size() == preset_count, "Custom opens local settings without a preset command")
	c.use_area(pile)
	c.stockpile_view.preset_buttons[17].pressed.emit()
	service.poll()
	check(w.calls[-1] == {"action":11,"id":31,"kind":0,"expected_revision":pile.revision,"operation":3,"preset":15}, "Wood invokes native SET preset with exact revision, no category or container overwrite")
	c.choose_preset(19)
	service.poll()
	check(w.calls.size() == preset_count + 1 and c.selected.categories == pile.categories, "pending preset blocks duplicate input and does not optimistically change flags")
	w.state = {"world_epoch":42,"revision":4,"request_seq":w.seq,"status":2,"action":11,"areas":[pile]}
	service.poll()
	c.stockpile_control("links_only")
	service.poll()
	check(w.calls[-1] == {"action":11,"id":31,"kind":0,"expected_revision":pile.revision,"links_only":0}, "take mode toggles only the observed flag")
	w.state = {"world_epoch":42,"revision":5,"request_seq":w.seq,"status":2,"action":11,"areas":[pile]}
	service.poll()
	c.stockpile_control("rename")
	check(c.rename_field.visible and c.rename_field.text == pile.name, "rename begins with inspected name")
	c.handle_back()
	check(c.stockpile_page == "types" and not c.rename_field.visible and c.panel.visible, "back from rename restores type panel without sending")
	c.stockpile_control("rename")
	c.rename_area("Changed pile")
	service.poll()
	check(w.calls[-1] == {"action":11,"id":31,"kind":0,"expected_revision":pile.revision,"operation":4,"name":"Changed pile"}, "rename uses semantic operation without unrelated fields")
	w.state = {"world_epoch":42,"revision":6,"request_seq":w.seq,"status":2,"action":11,"areas":[pile]}
	service.poll()
	check(
		(
			(
				c
				. footprint_edges(
					{
						"width": 3,
						"height": 3,
						"extents": PackedByteArray([1, 1, 1, 1, 0, 1, 1, 1, 1])
					}
				)
				. size()
			)
			== 16
		),
		"observed footprint outlines include holes and exclude internal edges"
	)
	var unchanged: Dictionary = c.edit_request()
	check(unchanged.expected_revision == 9007199254740993, "area edit preserves exact native revision")
	check(c.selected_request(12).expected_revision == pile.revision, "delete echoes inspected revision")
	check(
		(
			unchanged.changed_categories == 0
			and not unchanged.has("barrels")
			and not unchanged.has("bins")
		),
		"large existing limits are not clamped into unrelated edits"
	)
	c.storage.bins.value = 1201
	var edit: Dictionary = c.edit_request()
	check(
		(
			edit.bins == 1201
			and edit.changed_categories == 0
			and not edit.has("barrels")
			and not edit.has("wheelbarrows")
		),
		"bins-only edit preserves unrelated values"
	)
	c.categories[13].button_pressed = false
	edit = c.edit_request()
	check(
		edit.changed_categories == 8192, "only toggled category is changed; fine filters never sent"
	)
	c.apply_edits()
	service.poll()
	var count := w.calls.size()
	c.remove_area()
	check(w.calls.size() == count, "one pending operation prevents duplicate mutation")
	w.state = {"world_epoch":42,"revision":4,"request_seq":w.seq,"status":2,"action":99}
	service.poll()
	c.choices = [{"id": 32, "name": "Target"}]
	c.candidate_picker.add_item("Target")
	c.link(true, false)
	service.poll()
	check(
		w.calls[-1].id == 31 and w.calls[-1].link_id == 32 and w.calls[-1].give and w.calls[-1].expected_revision == pile.revision,
		"link keeps both selected identities"
	)
	w.state = {"world_epoch":42,"revision":4,"request_seq":w.seq,"status":2,"action":99}
	service.poll()
	c.search.text = "Later citizen"
	c.search_candidates(1500)
	service.poll()
	check(
		w.calls[-1].cursor == 1500 and w.calls[-1].query == "Later citizen",
		"search and paging retain native cursor"
	)
	w.state = {"world_epoch":42,"revision":5,"request_seq":w.seq,"status":2,"action":14,
		"area":{"build_phase":1,"build_done":0,"build_total":200}}
	service.poll()
	check(c.request_ticket == 0 and c.choices.is_empty() and not c._candidate_poll_request.is_empty(), "pending candidate page schedules a read-only poll")
	count = w.calls.size()
	c._process(0.249)
	service.poll()
	check(w.calls.size() == count, "candidate poll waits 250 ms")
	c._process(0.001)
	service.poll()
	check(w.calls.size() == count + 1 and w.calls[-1].action == 14 and w.calls[-1].cursor == 1500 and w.calls[-1].query == "Later citizen", "candidate poll preserves exact selector and cursor")
	w.state = {"world_epoch":42,"revision":6,"request_seq":w.seq,"status":2,"action":14,
		"area":{"build_phase":3,"build_done":200,"build_total":200,"list_revision":9007199254740993,"choices":[{"id":1500,"name":"Later citizen"}],"next_cursor":1600}}
	service.poll()
	count = w.calls.size()
	c._process(1.0)
	service.poll()
	check(c.choices.size() == 1 and c.next_cursor == 1600 and w.calls.size() == count, "completed candidates stop polling and populate the picker")
	var candidate_request := {"action":14,"kind":0,"query":"Later citizen","cursor":0}
	c._receive_result({"status":2,"action":14,"area":{"build_phase":3,"build_done":0,"build_total":0,"list_revision":7,"choices":[],"next_cursor":0}}, candidate_request)
	c._process(1.0)
	service.poll()
	check(c.choices.is_empty() and c._candidate_poll_request.is_empty() and w.calls.size() == count, "completed empty native list does not repoll")
	c._receive_result({"status":2,"action":14,"area":{"build_phase":2}}, candidate_request)
	c.search.text = "Changed search"
	c._process(1.0)
	service.poll()
	check(w.calls.size() == count and c._candidate_poll_request.is_empty(), "changing search cancels scheduled candidate polling")
	c._receive_result({"status":2,"action":14,"area_choices":[{"id":99,"name":"Stale"}]}, candidate_request)
	check(c.choices.is_empty(), "late old-search candidates cannot replace the current picker")
	candidate_request.query = "Changed search"
	c._receive_result({"status":2,"action":14,"area":{"build_phase":3}}, candidate_request)
	c.use_area(pile)
	c._process(1.0)
	service.poll()
	check(w.calls.size() == count and c._candidate_poll_request.is_empty(), "changing selected area cancels candidate polling")
	c._receive_result({"status":2,"action":14,"area":{"build_phase":1}}, candidate_request)
	c._receive_result({"status":3,"action":14,"outcome":"unknown"}, candidate_request)
	c._process(1.0)
	service.poll()
	check(w.calls.size() == count and c._candidate_poll_request.is_empty(), "unknown read outcome is not automatically replayed")
	var overlap := pile.duplicate(true)
	overlap.revision = 0
	c.use_area(overlap)
	service.poll()
	check(w.calls[-1].action == 9 and c.apply_button.disabled, "revision-free overlap selection triggers inspection before edits")
	count = w.calls.size()
	c.apply_edits()
	service.poll()
	check(w.calls.size() == count, "zero-revision edits are never submitted")
	w.state = {"world_epoch":42,"revision":7,"request_seq":w.seq,"status":2,"action":9,"areas":[pile]}
	service.poll()
	check(c.selected.revision == pile.revision and not c.apply_button.disabled, "fresh inspection enables revision-checked edits")
	c._receive_result({"status":2,"action":9,"areas":[overlap]}, {"action":9})
	c._process(1.0)
	service.poll()
	check(w.calls.size() == count and c.apply_button.disabled, "zero-revision inspection does not create an automatic refresh loop")
	c.use_area(pile)
	w.state = {"world_epoch":42,"revision":4,"request_seq":w.seq,"status":2,"action":99}
	service.poll()
	c.new_area()
	c.kind_picker.select(1)
	c.new_area()
	var bedroom: Dictionary = pile.duplicate(true)
	bedroom.kind = 1; bedroom.zone_type = 2; bedroom.zone_label = "Bedroom"
	bedroom.name = "Unnamed bedroom"; bedroom.active = true; bedroom.owner_allowed = true
	bedroom.width = 2; bedroom.height = 1; bedroom.extents = PackedByteArray([1,1]); bedroom.tile_count = 2
	c.use_area(bedroom)
	check(c.zone_menu.visible and c.zone_menu.selected_panel.visible, "existing bedroom retains native grid and shared panel")
	c.zone_menu.controls.suspend.pressed.emit(); service.poll()
	check(w.calls[-1] == {"action":11,"kind":1,"id":bedroom.id,"expected_revision":bedroom.revision,"active":0}, "suspend sends isolated revision-checked active flag")
	check(c.selected.active, "suspend waits for authoritative reply")
	bedroom.active = false; bedroom.revision += 1
	w.state = {"world_epoch":42,"revision":8,"request_seq":w.seq,"status":2,"action":11,"areas":[bedroom]}
	service.poll()
	check(not c.selected.active, "suspend reply updates selected state")
	c.zone_menu.controls.rename.pressed.emit(); c.zone_menu.name_entry.text = "Local draft"
	c.handle_back()
	check(not c.zone_menu.name_entry.visible and c.selected.name == "Unnamed bedroom", "zone rename Back discards local text")
	c.zone_menu.controls.repaint.pressed.emit()
	check(c.mode == "paint" and c.zone_draft.id == 2 and c.paint_state.area.id == bedroom.id, "existing zone repaint retains observed type and identity")
	c.handle_back()
	check(not c.panel.visible and not w.zone_overlays, "native repaint Escape exits the tool")
	c.ui_host.activate(c); c.panel.show(); c.new_area()
	c.zone_menu.buttons.Bedroom.pressed.emit()
	check(c.selected.is_empty() and c.paint_state.area.is_empty(), "type grid starts a new zone instead of modifying previous selection")
	c.new_area()
	check(w.zone_overlays, "zone editing shows original zone boundaries")
	check(c.zone_menu.visible and c.mode == "zone_select", "Zones opens native type chooser")
	c.zone_menu.buttons.Bedroom.pressed.emit()
	check(c.mode == "paint" and c.zone_draft.id == 2, "observed zone type starts local paint")
	c.handle_back()
	check(not c.panel.visible, "native empty zone Paint Escape exits the tool")
	c.ui_host.activate(c); c.panel.show(); c.new_area()
	c.choose_zone_type(2)
	c.paint_pointer(Vector3i(5,6,2),true)
	c.paint_pointer(Vector3i(7,7,2),false)
	check(c.paint_state.cells.is_empty() and c.dragging,"native rectangle release retains first corner even at another tile")
	c.paint_pointer(Vector3i(7,7,2),true); c.paint_pointer(Vector3i(7,7,2),false)
	c.create_area()
	service.poll()
	check(
		(
			w.calls[-1].action == 10
			and w.calls[-1].zone_type == 2
			and w.calls[-1].kind == 1
			and w.calls[-1].paint_mode == 1
			and w.calls[-1].spans.size() == 2
			and w.calls[-1].spans[0].length == 3
		),
		"new zone sends one typed paint intent"
	)
	w.state = {"world_epoch": 99, "revision": 9, "status": 0}
	service.poll()
	check(
		c.request_ticket == 0 and not c.available and c.selected.is_empty(),
		"world change clears pending edit and selected identities"
	)
	check(c.zone_types.is_empty() and c.zone_draft.is_empty() and c.zone_picker.item_count == 0
		and c.zone_menu.catalog.is_empty(),"world change clears observed zone catalog and picker identities")
	c.ui_host.set_play_enabled(false)
	check(not w.zone_overlays, "save/menu hides zone overlays")
	check(
		not c.panel.visible and not interaction.panel.visible,
		"save/menu closes management and keeps gameplay hidden"
	)
	count = w.calls.size()
	c.send(
		{
			"action": 10,
			"kind": 0,
			"origin": Vector3i(1, 1, 1),
			"width": 1,
			"height": 1,
			"categories": 1
		}
	)
	check(w.calls.size() == count, "session gate blocks stale direct controller callbacks")
	c.ui_host.set_play_enabled(true)
	c.ui_host.activate(c)
	c.panel.show()
	c.send({"action": 10})
	service.poll()
	var closed_ticket: int = c.request_ticket
	c.close_panel()
	w.state = {"world_epoch":99,"revision":10,"request_seq":w.seq,"status":2,"action":10}
	count = w.calls.size()
	service.poll()
	check(c.request_ticket == 0 and not c.panel.visible and w.calls.size() == count and service.result(closed_ticket).status == 2, "service retains closed area mutation result without reopening or follow-up")
	c.open_panel()
	service.poll()
	var retained: Dictionary = service.last_detached_mutation("areas")
	check(retained.ticket == closed_ticket and retained.result.status == 2 and retained.detached,
		"Reopening retains authoritative detached receipt ownership")
	check(not c.message.text.contains("Previous request"),"Receipt bookkeeping adds no invented native UI copy")
	c.dragging=true;c.drag_start=Vector3i(1,1,2)
	c.ui_host.set_overlay_blocked(true)
	check(not c.dragging,"Overlay cancels area drag without discarding request ticket")
	var before_overlay: int = w.calls.size()
	var release := InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
	c._unhandled_input(release)
	check(w.calls.size()==before_overlay,"Overlay release cannot complete a map drag or submit an area")
	c.ui_host.set_overlay_blocked(false)
	# Native capture230002: new footprints and repaints survive elevation changes.
	c._detach_draft(); c.kind_picker.select(0); c.available = true
	c.new_area(); c.current_z = w.top_z
	c.paint_tool = "brush"
	c.paint_pointer(Vector3i(1,1,2),true)
	var retained_cells: Dictionary = c.paint_state.cells.duplicate()
	var before_elevation := w.calls.size()
	w.top_z = 3; c._process(0)
	check(not c.dragging and c.paint_state.cells == retained_cells and c.paint_state.z == 2,"elevation preserves new footprint on its original plane")
	check(not c.outline.visible,"off-plane draft does not render through the current elevation")
	c.paint_pointer(Vector3i(2,2,3),false)
	check(c.paint_state.cells == retained_cells and w.calls.size() == before_elevation,"other-plane release neither paints nor submits")
	w.top_z = 2; c._process(0)
	c.paint_pointer(Vector3i(2,1,2),true); c.paint_pointer(Vector3i(2,1,2),false)
	check(c.outline.visible and c.paint_state.cells.size() == 2,"returning to the original plane resumes the retained draft")
	c.use_area(pile,false); c.stockpile_control("repaint")
	c.paint_pointer(Vector3i(1,1,2),true); c.paint_pointer(Vector3i(1,1,2),false)
	retained_cells = c.paint_state.cells.duplicate()
	w.top_z = 3; c._process(0)
	check(c.mode == "paint" and c.paint_state.cells == retained_cells and c.paint_state.area.id == pile.id,"elevation preserves existing-area repaint identity and geometry")
	c.paint_pointer(Vector3i(2,2,3),true); c.paint_pointer(Vector3i(2,2,3),false)
	check(c.paint_state.cells == retained_cells,"other-plane input cannot modify the repaint footprint")
	w.top_z = 2; c._process(0)
	check(c.outline.visible and w.calls.size() == before_elevation,"elevation round trip does not submit or detach the draft")
	# An empty new rectangle uses its ending elevation, as native224155 does.
	c.new_area(); c.paint_pointer(Vector3i(1,1,2),true)
	w.top_z = 3; c._process(0)
	c.paint_pointer(Vector3i(2,2,3),false)
	check(c.paint_state.z == 3 and c.paint_state.cells.size() == 4,"empty rectangle follows ending elevation without losing its first corner")
	c.accept_paint()
	var pending_paint_ticket: int = c.request_ticket
	var pending_paint: Dictionary = c.paint_state.pending.duplicate(true)
	w.top_z = 2; c._process(0)
	check(pending_paint_ticket != 0 and c.request_ticket == pending_paint_ticket and c.paint_state.pending == pending_paint,"elevation change retains pending semantic paint receipt")
	# Retired native identities must never remain armed after a rejected edit.
	c._detach_draft()
	for reason in ["Area no longer exists","Area is not visible","Area kind changed; inspect again"]:
		c.available = true; c.use_area(pile,false)
		c._receive_result({"status":3,"message":reason},{"action":11})
		check(c.selected.is_empty() and not c.available and c.paint_state.stopped,"stale target clears identity and disarms edits")
		check(c.message.text.get_slice("\n",0) == reason and c.request_problem,"stale target preserves exact rejection")
		var before_stale := w.calls.size()
		c.paint_pointer(Vector3i(1,1,2),true); c.paint_pointer(Vector3i(2,2,2),false)
		c.accept_paint(); service.poll()
		check(w.calls.size() == before_stale,"stale target cannot submit another paint")
	# Multi uses native discovery on release and a scoped token, never Paint/Accept.
	service._invalidate(); w.live = true
	w.state = {"world_epoch":99,"revision":500,"status":0}
	c.panel.show(); c.play_enabled = true; c.available = true; c.kind_picker.select(1)
	c.zone_types = [{"id":2,"name":"Bedroom","label":"Bedroom","icon":""}]
	c.new_area(); c.choose_zone_type(2)
	check(not c.paint_view.multi_button.disabled,"supported new zone offers Multi")
	c.paint_view.multi_button.pressed.emit()
	check(c.mode == "multi" and c.multi_state.ready() and not c.paint_view.accept_button.visible,"initial Multi has no invented Accept step")
	check(c.paint_view.prompt.text.replace("\n"," ").begins_with("Select a rectangle which contains beds"),"native initial prompt mapped")
	c.multi_pointer(Vector3i(5,6,2),true); c.multi_pointer(Vector3i(5,6,2),false)
	var gesture_scope: int = c.multi_state.interaction_id
	c.handle_back()
	check(c.mode == "multi" and not c.dragging and c.multi_state.interaction_id == gesture_scope and c.request_ticket == 0,"native back cancels only partial Multi rectangle")
	c.multi_pointer(Vector3i(5,6,2),true); c.multi_pointer(Vector3i(5,6,2),false)
	check(c.dragging and c.request_ticket == 0,"first corner click does not create a one-tile selection")
	w.top_z = 3; c._process(0)
	check(c.dragging and c.drag_start == Vector3i(5,6,3),"native Multi first corner follows elevation")
	w.top_z = 2; c._process(0)
	c.multi_pointer(Vector3i(3,4,2),true); c.multi_pointer(Vector3i(3,4,2),false)
	service.poll()
	var multi_request: Dictionary = w.calls[-1]
	check(multi_request.operation == 16 and multi_request.origin == Vector3i(3,4,2) and multi_request.width == 3,"rectangle release submits native selection")
	var multi_ticket: int = c.request_ticket
	w.top_z = 3; c._process(0)
	check(c.request_ticket == multi_ticket and not c.multi_state.pending.is_empty(),"camera elevation does not detach sent Multi")
	check(not c.message.visible,"Multi does not display authored generic request status copy")
	var multi_page := {"operation":16,"interaction_id":multi_request.interaction_id,"room_outcome":1,"undo_token":9007199254740993,
		"rooms_created":1,"rooms_dormitories":0,"rooms_in_use":0,"rooms_unenclosed":0,"rooms_removed":0}
	w.state = {"world_epoch":99,"revision":501,"request_seq":w.seq,"action":10,"status":2,"area":multi_page}
	service.poll()
	check(c.mode == "multi" and c.selected.is_empty() and c.multi_state.undo_token == 9007199254740993,"scalar room result stays in Multi without area-record fallback")
	check(c.paint_view.accept_button.text == "Undo" and c.paint_view.cancel_button.text == "Done" and c.paint_view.multi_result.text == "Bedroom created.","native result controls and singular copy mapped")
	c.paint_view.accept_button.pressed.emit(); service.poll()
	check(w.calls[-1].operation == 17 and w.calls[-1].undo_token == 9007199254740993 and not w.calls[-1].has("expected_revision"),"Undo bypasses single-area revision requirement")
	var undone := {"operation":17,"interaction_id":multi_request.interaction_id,"room_outcome":1,"undo_token":0,
		"rooms_created":0,"rooms_dormitories":0,"rooms_in_use":0,"rooms_unenclosed":0,"rooms_removed":1}
	w.state = {"world_epoch":99,"revision":502,"request_seq":w.seq,"action":11,"status":2,"area":undone}
	service.poll()
	check(not c.paint_view.accept_button.visible and c.multi_state.undo_token == 0,"successful Undo returns initial selection panel")
	c.multi_pointer(Vector3i(1,1,3),true); c.multi_pointer(Vector3i(2,2,3),false); service.poll()
	var closing_request: Dictionary = w.calls[-1]
	c.close_panel()
	check(c.multi_state.interaction_id == 0 and not c.panel.visible,"close immediately retires local Multi authority")
	multi_page.interaction_id = closing_request.interaction_id
	w.state = {"world_epoch":99,"revision":503,"request_seq":w.seq,"action":10,"status":2,"area":multi_page}
	service.poll()
	check(c.multi_state.undo_token == 0 and w.calls[-1].operation == 18 and w.calls[-1].interaction_id == closing_request.interaction_id,"late creation stays detached and Finish follows the sent selection")
	# Count reads have separate tickets and use local geometry, never native widgets.
	service._invalidate(); c._detach_draft(); c.multi_state.clear()
	var count_service := preload("res://tests/area_paint_test.gd").CountService.new()
	c.paint_counts.service = count_service
	c.panel.show(); c.play_enabled = true; c.available = true; c.kind_picker.select(1)
	c.ui_host.activate(c)
	c.mode = "paint"; c.paint_tool = "rectangle"; w.top_z = 2; c.current_z = 2
	c.zone_draft = {"id":92,"name":"Bedroom","label":"Bedroom","icon":""}
	c.paint_state.open({},Vector2i(48,48),2)
	c.paint_motion(Vector3i(4,5,2)); c.paint_counts.poll(0)
	check(count_service.requests[0].paint_preview == {"x":4,"y":5,"width":1,"height":1},"idle map hover is a one-cell count preview")
	check(c.request_ticket == 0,"count read does not own the mutation ticket")
	count_service.reply(1,0,1)
	check(c.paint_view.zone_caption.text == "Bedroom: 0 + 1","caption uses native count format")
	c.update_controls()
	check(c.paint_view.zone_caption.text == "Bedroom: 0 + 1","control refresh preserves current observed counts")
	c.paint_pointer(Vector3i(4,5,2),true); c.paint_pointer(Vector3i(4,5,2),false)
	check(c.dragging and c.paint_state.cells.is_empty(),"first corner click remains a local preview")
	c.paint_motion(Vector3i(6,7,2)); c.paint_counts.poll(0.11)
	check(count_service.requests[1].paint_preview == {"x":4,"y":5,"width":3,"height":3} and count_service.requests[1].spans.is_empty(),"rectangle preview is independent of uncommitted local draft")
	c.paint_pointer(Vector3i(6,7,2),true); c.paint_pointer(Vector3i(6,7,2),false)
	count_service.reply(2,0,9)
	check(c.paint_view.zone_caption.text == "Bedroom","pre-commit reply cannot label the changed footprint")
	c.paint_counts.poll(0.11); count_service.reply(3,9,0)
	check(count_service.requests[2].spans.size() == 3 and c.paint_view.zone_caption.text == "Bedroom: 9 + 0","committed local draft supplies coalesced spans")
	c.select_paint_tool("erase")
	check(c.paint_tool == "rectangle" and c.paint_erasing,"erase preserves rectangle mode")
	c.select_paint_tool("brush"); check(c.paint_erasing and c.paint_tool == "brush","brush preserves erase toggle")
	c.select_paint_tool("rectangle"); c.select_paint_tool("erase")
	check(not c.paint_erasing,"second erase click turns erasing off")
	c.paint_pointer(Vector3i(4,5,2),true); c.paint_pointer(Vector3i(4,5,2),false)
	c.select_paint_tool("erase")
	check(c.dragging and c.paint_state.cells.size() == 9,"erase toggle retains first corner and completed footprint")
	c.paint_pointer(Vector3i(4,5,2),true); c.paint_pointer(Vector3i(4,5,2),false)
	c.paint_counts.poll(0.11); count_service.reply(4,8,1)
	check(c.paint_view.zone_caption.text == "Bedroom: 8 + 1","erased hovered cell retains native positive preview term")
	c.paint_counts.poll(0.51); count_service.reply(5,-1,1)
	check(c.paint_view.zone_caption.text == "Bedroom","unknown count never appears as a number or invented disclaimer")
	c.paint_motion(Vector3i(8,8,2)); c.paint_counts.poll(0.11)
	w.top_z = 3; c._process(0)
	count_service.reply(6,8,1)
	check(c.paint_counts.values.is_empty(),"elevation change rejects prior preview reply")
	c._process(0.11)
	check(count_service.requests[6].paint_z == 2 and not count_service.requests[6].has("paint_preview"),"different viewed level retains draft count plane without stale hover")
	count_service.reply(7,8,0)
	c.ui_host.set_overlay_blocked(true); c._process(1)
	check(c.paint_counts.values.is_empty() and count_service.requests.size() == 7,"overlay retires counts and pauses refresh")
	c.ui_host.set_overlay_blocked(false); w.top_z = 2; c._process(0)
	count_service.reply(8,8,0)
	c.paint_motion(Vector3i(9,9,2)); c.paint_counts.poll(0.11)
	var motion := InputEventMouseMotion.new(); motion.position = c.panel.position
	c._input(motion); c._process(0)
	count_service.reply(9,8,1)
	check(c.paint_counts.values.is_empty(),"UI-consumed pointer motion invalidates map hover reply")
	c.close_panel(); c.paint_counts.poll(1)
	check(count_service.requests.size() == 9,"closed controller has no count polling")
	count_service.observers.clear()
	# Staff edits reobserve the zone owner without giving late replies authority
	# over another parent. Synthetic professions here are not product copy.
	c.paint_counts.service = service
	service._invalidate()
	var parent := pile.duplicate(true)
	parent.kind = 1; parent.zone_type = 92; parent.owner_profession = "fixture original"
	c.panel.show(); c.available = true; c.mode = "inspect"; c.selected = parent.duplicate(true)
	c.areas = [parent.duplicate(true)]; c.locations_state.area = parent.duplicate(true)
	var calls_before_parent := w.calls.size()
	c._refresh_details_parent()
	var cancelled_parent: int = c.details_parent_ticket
	c._detach_draft(); service.poll()
	check(service.result(cancelled_parent).get("outcome") == "not_sent" and w.calls.size() == calls_before_parent,"retiring queued parent refresh cancels before transport")
	c.selected = parent.duplicate(true)
	c._refresh_details_parent(); service.poll()
	check(w.calls[-1].action == 9 and w.calls[-1].id == parent.id,"staff parent refresh requests semantic zone inspection")
	c.close_location_details()
	var refreshed_parent := parent.duplicate(true)
	refreshed_parent.owner_profession = "fixture assigned"
	w.state = {"world_epoch":99,"revision":510,"request_seq":w.seq,"action":9,"status":2,"area":{"areas":[refreshed_parent]}}
	service.poll()
	check(c.selected.owner_profession == "fixture assigned" and c.areas[0].owner_profession == "fixture assigned","confirmed parent refresh updates selected zone and cached row")
	check(c.details_parent_ticket == 0 and c.details_origin.is_empty() and not c.details_layer.visible,"closing Details retains parent refresh without reopening Details")
	c._refresh_details_parent(); service.poll()
	var sent_parent_seq: int = w.seq
	c._detach_draft(); c.selected = parent.duplicate(true); c.selected.id = 32
	w.state = {"world_epoch":99,"revision":511,"request_seq":sent_parent_seq,"action":9,"status":2,"area":{"areas":[refreshed_parent]}}
	service.poll()
	check(c.selected.id == 32 and c.selected.owner_profession == "fixture original" and c.details_parent_ticket == 0,"late parent reply cannot replace a different selected zone")
	c.selected = parent.duplicate(true); c.locations_state.area = parent.duplicate(true)
	c._refresh_details_parent(); service.poll()
	var first_parent_ticket: int = c.details_parent_ticket
	var first_parent_seq: int = w.seq
	c._refresh_details_parent(); c._refresh_details_parent()
	check(c.details_parent_ticket == first_parent_ticket and w.seq == first_parent_seq,"additional staff changes share outstanding parent read")
	w.state = {"world_epoch":99,"revision":512,"request_seq":w.seq,"action":9,"status":2,"area":{"areas":[refreshed_parent]}}
	service.poll()
	check(w.seq == first_parent_seq + 1 and c.details_parent_ticket != 0 and c.details_parent_ticket != first_parent_ticket,"changes during parent read trigger exactly one follow-up inspection")
	refreshed_parent.owner_profession = "fixture latest"
	w.state = {"world_epoch":99,"revision":513,"request_seq":w.seq,"action":9,"status":2,"area":{"areas":[refreshed_parent]}}
	service.poll()
	check(c.selected.owner_profession == "fixture latest" and c.locations_state.area.owner_profession == "fixture latest" and c.details_parent_ticket == 0 and w.seq == first_parent_seq + 1,"follow-up parent snapshot refreshes retained chooser without polling loop")
	c._refresh_details_parent(); service.poll()
	c._refresh_details_parent()
	var old_epoch_seq: int = w.seq
	w.state = {"world_epoch":100,"revision":514,"request_seq":old_epoch_seq,"action":9,"status":2,"area":{"areas":[refreshed_parent]}}
	service.poll()
	check(c.selected.is_empty() and c.areas.is_empty() and c.details_parent_ticket == 0 and not c.details_parent_refresh_again,"epoch replacement retires both parent read and deferred refresh")
	check(w.seq == old_epoch_seq and not c.available and c.locations_state.area.is_empty(),"old-epoch parent reply cannot repopulate zone or chooser and is not replayed")
	c.close_panel()
	c.free()
	interaction.free()
	print(
		"area controller tests: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures]
	)
	quit(failures)
