extends SceneTree
const Base = preload("res://tests/areas_test.gd")
var failures := 0
var world
var service
var controller
var pile := {"id":39,"revision":11,"kind":0,"name":"Synthetic pile",
	"origin":Vector3i(3,4,2),"width":2,"height":2,"extents":PackedByteArray([1,1,1,1]),
	"tile_count":4,"storage_limit":4,"categories":64,"barrels":0,"bins":0,"wheelbarrows":0,"links_only":false,
	"active":true,"owner_id":-1,"owner_name":"","owner_allowed":false,"gives":[],"takes":[]}

func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func reply(action: int, fields: Dictionary = {}) -> void:
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":action,"status":2}
	world.state.merge(fields,true); service.poll()

func open_storage() -> void:
	controller.use_area(pile); controller.stockpile_control("containers"); service.poll()
	check(world.calls[-1].action == 9,"opening storage refreshes the mutation receipt")
	reply(9,{"areas":[pile]})

func accepted(key: String, value: int) -> void:
	pile = pile.duplicate(true); pile.revision += 1; pile[key] = value
	reply(11,{"areas":[pile]})

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
	open_storage()
	var view = controller.storage_view
	view.activate("bins",0)
	var before: int = world.calls.size()
	check(view.entry.text.is_empty() and world.calls.size() == before,"opening empty numeric entry does not mutate")
	view.edit_entry("1"); service.poll()
	check(world.calls[-1].bins == 1 and world.calls[-1].expected_revision == 11,"typing sends an immediate revision-checked value")
	view.edit_entry("1234")
	check(view.entry.text == "123" and controller.storage_values.bins == 4,"three digits are retained while the semantic value clamps to native bound")
	check(view.editing == "bins" and view.entry.editable,"pending write preserves entry")
	check(not controller.message.visible,"pending storage write does not add an unsourced status strip")
	accepted("bins",1)
	check(world.calls[-1].bins == 4 and world.calls[-1].expected_revision == 12,"new explicit value continues using the accepted revision")
	check(view.entry.text == "123" and view.editing == "bins","accepted reply preserves newer text and editing identity")
	view.edit_entry(""); controller.handle_back()
	check(controller.stockpile_page == "types" and not view.visible,"Escape closes numeric popup immediately")
	accepted("bins",4)
	check(world.calls[-1].bins == 0 and world.calls[-1].expected_revision == 13,"closing popup preserves the requested backspace-to-empty write")
	accepted("bins",0)
	check(controller.stockpile_page == "types" and controller.selected.bins == 0 and controller.request_ticket == 0,"late accepted write updates identity without reopening popup")
	open_storage(); view.activate("bins",0)
	await process_frame
	var digit := InputEventKey.new(); digit.unicode = 57; digit.pressed = true
	root.push_input(digit,true)
	check(view.entry.text == "9","viewport input reaches the focused numeric field")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	root.push_input(escape,true)
	await process_frame
	service.poll()
	check(controller.stockpile_page == "types" and controller.storage_sending,"same-frame Escape preserves the final numeric input")
	check(world.calls[-1].action == 11 and world.calls[-1].get("bins",-1) == 4,"same-frame close submits the clamped numeric edit")
	accepted("bins",4)
	open_storage(); view.activate("barrels",0); view.edit_entry("-a1"); service.poll()
	check(view.entry.text == "1" and world.calls[-1].barrels == 1,"non-digits are ignored")
	view.edit_entry("2")
	reply(11,{"status":3,"message":"Area changed; inspect again"})
	before = world.calls.size(); service.poll()
	check(controller.storage_failed and controller.storage_values.is_empty() and world.calls.size() == before,"rejected mutation drops buffered values without retrying")
	check(not view.entry.visible and view.controls.barrels[0].disabled,"rejection ends editing until a fresh inspection")
	controller.handle_back(); controller.stockpile_control("containers"); service.poll(); reply(9,{"areas":[pile]})
	view.activate("barrels",0); view.edit_entry("1"); service.poll(); view.edit_entry("2")
	service.poll(16)
	check(controller.storage_failed and controller.storage_values.is_empty(),"unknown outcome drops newer buffered values")
	before = world.calls.size(); accepted("barrels",1)
	check(world.calls.size() == before and controller.selected.barrels == 0,"late unknown resolution cannot replay input or publish into the view")
	controller.close_panel(); controller.open_panel(); service.poll(); reply(0); reply(7)
	open_storage(); view.activate("barrels",0); view.edit_entry("2")
	var queued_ticket: int = controller.request_ticket
	before = world.calls.size(); controller.close_panel(); service.poll()
	check(world.calls.size() == before and service.result(queued_ticket).get("outcome","") == "not_sent","full panel close cancels an unsent numeric write")
	controller.open_panel(); service.poll(); reply(0); reply(7)
	open_storage(); view.activate("barrels",0); view.edit_entry("2"); service.poll(); view.edit_entry("3")
	before = world.calls.size(); controller.close_panel(); accepted("barrels",2)
	check(world.calls.size() == before and controller.storage_values.is_empty() and not controller.storage_sending and not controller.panel.visible,"full panel close drops buffered input and drains a sent write without reopening")
	for invalidation in ["epoch","disconnect"]:
		controller.open_panel(); service.poll(); reply(0); reply(7)
		open_storage(); view.activate("barrels",0); view.edit_entry("3"); service.poll(); view.edit_entry("4")
		before = world.calls.size()
		if invalidation == "epoch": world.state = {"world_epoch":99,"revision":100,"status":0}
		else: world.state = {"world_epoch":42,"revision":100,"status":0,"transport_alive":false}
		service.poll()
		check(controller.selected.is_empty() and controller.storage_values.is_empty() and not controller.storage_sending and not view.entry.visible,invalidation + " clears pending numeric input and identity")
		check(world.calls.size() == before,invalidation + " does not replay buffered numeric input")
		controller.close_panel()
		world.state = {"world_epoch":42,"revision":101,"status":0}; service.poll()
	controller.close_panel(); controller.queue_free(); host.queue_free(); service.queue_free(); interaction.queue_free()
	await process_frame
	print("AREA_STORAGE_CONTROLLER PASS" if failures == 0 else "AREA_STORAGE_CONTROLLER FAIL")
	quit(failures)
