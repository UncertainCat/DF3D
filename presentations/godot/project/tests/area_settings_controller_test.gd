extends SceneTree
const Base = preload("res://tests/areas_test.gd")
var failures := 0
var world
var service
var controller
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func reply(action: int, fields: Dictionary = {}) -> void:
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,
		"request_seq":world.seq,"action":action,"status":2}
	world.state.merge(fields,true)
	service.poll()
func settings_reply(rows: Array) -> void:
	service.poll()
	var sent: Dictionary = world.calls[-1]
	reply(9,{"area":{"list_key":sent.list_key,"query":sent.query,"settings":rows,
		"list_revision":91,"build_phase":3,"build_done":4,"build_total":4,"next_cursor":0}})
func _initialize() -> void: call_deferred("run")
func run() -> void:
	world = Base.FakeWorld.new()
	var interaction := Base.FakeInteraction.new(); root.add_child(interaction)
	service = preload("res://scripts/semantic_action_service.gd").new()
	service.configure(world); root.add_child(service); service.set_process(false)
	var host = preload("res://scripts/ui_host.gd").new(); host.interaction = interaction; root.add_child(host)
	controller = preload("res://scripts/areas.gd").new()
	controller.world = world; controller.action_service = service; controller.ui_host = host; controller.interaction = interaction
	root.add_child(controller); host.register(controller); controller.set_process(false)
	controller.open_panel(); service.poll(); reply(0); reply(7)
	var pile := {"id":39,"revision":11,"kind":0,"name":"Wood Stockpile #39",
		"origin":Vector3i(3,4,2),"width":2,"height":2,"extents":PackedByteArray([1,1,1,1]),
		"categories":8256,"barrels":0,"bins":0,"wheelbarrows":0,"links_only":false,
		"active":true,"owner_id":-1,"owner_name":"","owner_allowed":false,"gives":[],"takes":[]}
	controller.use_area(pile); controller.choose_preset(0)
	settings_reply([{"key":"armor","label":"Armor","kind":1,"state":1}])
	settings_reply([{"key":"armor/usable","label":"Usable armor","kind":3,"state":1}])
	var boolean_row: Button = controller.settings_view.rendered_rows[1][0]
	check(boolean_row.get_parent().get_child_count() == 1,"native boolean row has no separate right toggle")
	boolean_row.pressed.emit(); service.poll()
	check(world.calls[-1].operation == 2 and world.calls[-1].row_key == "armor/usable" and world.calls[-1].scope == 1 and world.calls[-1].value == 2 and world.calls[-1].expected_revision == 11,"boolean row click sends one revision-checked enable")
	reply(11,{"areas":[pile]})
	settings_reply([{"key":"armor","label":"Armor","kind":1,"state":1}])
	settings_reply([{"key":"armor/usable","label":"Usable armor","kind":3,"state":2}])
	check(not controller.settings_state.busy(),"boolean mutation refresh settles before changing categories")
	var before_probe: int = world.calls.size()
	controller._process(1.0); service.poll()
	check(world.calls.size() == before_probe+1 and world.calls[-1].action == 9 and world.calls[-1].operation == 0 and not world.calls[-1].has("expected_revision"),"idle settings inspect current revision without a stale precondition")
	reply(9,{"areas":[pile]})
	check(not controller.settings_state.busy() and controller.stockpile_page == "settings" and controller.settings_state.rows[1][0].state == 2,"unchanged inspection preserves completed rows and page")
	controller._process(1.0); service.poll()
	var changed_pile: Dictionary = pile.duplicate(true); changed_pile.revision = 12
	reply(9,{"areas":[changed_pile]})
	check(controller.settings_state.category == "armor" and controller.settings_state.pending.expected_revision == 12,"external revision refresh retains navigation and uses fresh revision")
	settings_reply([{"key":"armor","label":"Armor","kind":1,"state":1}])
	settings_reply([{"key":"armor/usable","label":"Usable armor","kind":3,"state":1}])
	check(not controller.settings_state.busy() and controller.settings_state.rows[1][0].state == 1,"external settings change becomes visible without reopening")
	controller.settings_state.read(1,"armor"); service.poll()
	reply(9,{"status":3,"message":"Area changed; inspect again"})
	check(not controller.settings_state.failed and not controller.request_problem and controller.settings_state.pending.operation == 0,"stale page read schedules a current inspection instead of freezing")
	var before_recovery: int = world.calls.size()
	controller._process(0.249); service.poll()
	check(world.calls.size() == before_recovery,"stale-read recovery backs off under external churn")
	controller._process(0.001); service.poll()
	check(world.calls.size() == before_recovery+1 and world.calls[-1].action == 9 and world.calls[-1].operation == 0,"recovery sends only a fresh read")
	# A vanished list receipt can require rebuilding even at the same area revision.
	reply(9,{"areas":[changed_pile]})
	check(controller.settings_state.pending.operation == 1,"same-revision recovery rebuilds the invalidated page")
	settings_reply([{"key":"armor","label":"Armor","kind":1,"state":1}])
	settings_reply([{"key":"armor/usable","label":"Usable armor","kind":3,"state":2}])
	check(not controller.settings_state.busy() and controller.settings_state.rows[1][0].state == 2,"page recovery finishes without reopening")
	controller.settings_view.rendered_rows[1][0].pressed.emit(); service.poll()
	reply(11,{"status":3,"message":"Area changed; inspect again"})
	before_recovery = world.calls.size(); controller._process(2.0); service.poll()
	check(controller.settings_state.failed and world.calls.size() == before_recovery,"stale mutation is terminal and never enters read recovery or replay")
	controller._detach_draft()
	controller.use_area(pile); controller.choose_preset(0)
	settings_reply([{"key":"wood","label":"Wood","kind":1,"state":1}])
	settings_reply([{"key":"wood/0","label":"Oak","kind":4,"state":1}])
	var count: int = world.calls.size()
	controller.settings_view.search.text = "pine"
	controller.settings_view.search.caret_column = 2
	controller.settings_view.search.select(1,3)
	controller.settings_view.search.text_changed.emit("pine")
	check(controller.settings_view.search.text == "PINE" and controller.settings_view.search.caret_column == 2 and controller.settings_view.search.get_selection_from_column() == 1 and controller.settings_view.search.get_selection_to_column() == 3,"native uppercase normalization retains caret and selection")
	controller._process(0.249); service.poll()
	check(world.calls.size() == count,"connected search waits before sending")
	controller._process(0.001); service.poll()
	check(world.calls[-1].query == "PINE" and controller.settings_view.search.editable,"search remains editable during its read")
	controller.settings_view.search.text = "oak"
	controller.settings_view.search.text_changed.emit("oak")
	settings_reply([{"key":"wood/9","label":"Pine","kind":4,"state":2}])
	check(controller.settings_state.rows[2].is_empty(),"connected stale search reply cannot overwrite draft")
	controller._process(0.25); service.poll()
	check(world.calls[-1].query == "OAK","connected newest query follows old terminal read")
	settings_reply([{"key":"wood/0","label":"Oak","kind":4,"state":1}])
	controller.settings_view.rendered_rows[2][0].pressed.emit()
	var ticket: int = controller.request_ticket
	count = world.calls.size(); controller.close_panel(); service.poll()
	check(world.calls.size() == count and service.result(ticket).get("outcome","") == "not_sent","close cancels queued settings mutation before dispatch")
	check(controller.settings_state.rows == [[],[],[]] and not controller.panel.visible,"close clears settings pages")
	controller.open_panel(); service.poll(); reply(0); reply(7)
	controller.use_area(pile); controller.choose_preset(0)
	settings_reply([{"key":"armor","label":"Armor","kind":1,"state":1}])
	settings_reply([{"key":"armor/usable","label":"Usable armor","kind":3,"state":1}])
	controller.settings_view.rendered_rows[0][0].pressed.emit(); service.poll()
	check(world.calls[-1].action == 11 and world.calls[-1].operation == 0 and world.calls[-1].changed_categories == 32768 and world.calls[-1].categories == 32768 and world.calls[-1].expected_revision == 11,"category click dispatches only its guarded activation flag")
	var activated_pile: Dictionary = pile.duplicate(true)
	activated_pile.categories = 41024; activated_pile.revision = 13
	reply(11,{"areas":[activated_pile]})
	check(controller.stockpile_page == "settings" and controller.settings_state.category == "armor" and controller.settings_state.pending.expected_revision == 13,"activation response retains category and rebuilds with returned revision")
	settings_reply([{"key":"armor","label":"Armor","kind":1,"state":1}])
	settings_reply([{"key":"armor/usable","label":"Usable armor","kind":3,"state":1}])
	check(not controller.settings_state.busy() and controller.settings_state.area.categories == 41024,"activation settles without filling off filters")
	for header_value in [1,2]:
		controller.settings_state.read(1,"armor")
		var armor_lists := [{"key":"armor/body","label":"Body","kind":2,"state":1},{"key":"armor/quality_core","label":"Core quality","kind":2,"state":1}]
		settings_reply(armor_lists)
		settings_reply([{"key":"armor/body/0","label":"Armor","kind":4,"state":1}])
		controller.settings_view.rendered_rows[1][1].pressed.emit()
		settings_reply([{"key":"armor/quality_core/0","label":"Standard","kind":4,"state":1}])
		controller.settings_view.headers[1 if header_value == 1 else 0].pressed.emit(); service.poll()
		check(world.calls[-1].operation == 2 and world.calls[-1].scope == 4 and world.calls[-1].value == header_value,"global All/None dispatches its semantic edit")
		activated_pile.revision += 1
		reply(11,{"areas":[activated_pile]})
		check(controller.settings_state.category == "armor" and controller.settings_state.subcategory.is_empty() and controller.settings_state.restore_counts[2] == 0,"accepted global header resets sublist and old leaf page depth")
		settings_reply([{"key":"armor","label":"Armor","kind":1,"state":1}])
		settings_reply(armor_lists)
		check(controller.settings_state.pending.list_key == "armor/body","accepted global header requests first native sublist")
		settings_reply([{"key":"armor/body/0","label":"Armor","kind":4,"state":1}])
	controller.close_panel()
	controller.open_panel(); service.poll(); reply(0); reply(7)
	controller.use_area(pile); controller.choose_preset(0); service.poll()
	controller.close_panel()
	reply(9,{"area":{"list_revision":99,"build_done":1,"build_total":1,"settings":[{"key":"wood","label":"Wood","kind":1,"state":2}]}})
	check(controller.settings_state.rows == [[],[],[]] and not controller.panel.visible,"late closed read cannot repopulate or reopen settings")
	controller.open_panel(); service.poll(); reply(0); reply(7)
	var empty_pile: Dictionary = pile.duplicate(true); empty_pile.categories = 0
	controller.use_area(empty_pile); controller.choose_preset(0); service.poll()
	check(world.calls[-1].action == 11 and world.calls[-1].changed_categories == 64 and world.calls[-1].expected_revision == 11,"Custom initially activates Ammo with inspected revision")
	empty_pile.categories = 64; empty_pile.revision = 15
	reply(11,{"areas":[empty_pile]})
	check(controller.settings_state.pending.expected_revision == 15,"initial activation reads only after its returned revision")
	settings_reply([{"key":"ammo","label":"Ammo","kind":1,"state":1}])
	settings_reply([{"key":"ammo/type","label":"Type","kind":2,"state":1}])
	settings_reply([])
	check(not controller.settings_state.busy() and controller.settings_state.leaf == "ammo/type","initial activation settles into Ammo/Type")
	controller.close_panel()
	controller.open_panel(); service.poll(); reply(0); reply(7)
	controller.use_area(pile); controller.choose_preset(0); service.poll()
	world.state = {"world_epoch":99,"revision":100,"status":0}; service.poll()
	check(controller.settings_state.area.is_empty() and controller.selected.is_empty() and not controller.available,"epoch clears both settings and selected area identity")
	controller.free(); host.free(); service.free(); interaction.free()
	await process_frame
	print("AREA_SETTINGS_CONTROLLER PASS" if failures == 0 else "AREA_SETTINGS_CONTROLLER FAIL")
	quit(failures)
