extends SceneTree
const Base = preload("res://tests/areas_test.gd")
var failures := 0
var world
var service
var controller
var pile := {"id":39,"revision":11,"kind":0,"name":"Stockpile #2","custom_name":"",
	"origin":Vector3i(3,4,2),"width":1,"height":1,"extents":PackedByteArray([1]),
	"tile_count":1,"storage_limit":1,"categories":64,"barrels":0,"bins":0,"wheelbarrows":0,"links_only":false,
	"active":true,"owner_id":-1,"owner_name":"","owner_allowed":false,"gives":[],"takes":[]}

func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)

func reply(action: int, fields: Dictionary = {}) -> void:
	world.state = {"world_epoch":42,"revision":int(world.state.revision)+1,"request_seq":world.seq,"action":action,"status":2}
	world.state.merge(fields,true); service.poll()

func accepted(value: String) -> void:
	pile = pile.duplicate(true); pile.revision += 1; pile.custom_name = value
	pile.name = value if not value.is_empty() else "Stockpile #2"
	reply(11,{"areas":[pile]})

func key(code: int, unicode := 0) -> void:
	var event := InputEventKey.new(); event.pressed = true; event.keycode = code; event.unicode = unicode
	root.push_input(event,true)

func open_name() -> void:
	controller.use_area(pile)
	if int(pile.kind) == 0: controller.stockpile_control("rename")
	else: controller.zone_control("rename")

func _initialize() -> void: call_deferred("run")
func run() -> void:
	var baseline := pile.duplicate(true)
	for kind in [0,1]:
		pile = baseline.duplicate(true); pile.kind = kind
		if kind == 1:
			pile.zone_type = 2; pile.zone_label = "Bedroom"
		await run_kind()
	print("AREA_RENAME_CONTROLLER PASS" if failures == 0 else "AREA_RENAME_CONTROLLER FAIL")
	quit(failures)

func run_kind() -> void:
	world = Base.FakeWorld.new()
	var interaction := Base.FakeInteraction.new(); root.add_child(interaction)
	service = preload("res://scripts/semantic_action_service.gd").new()
	service.configure(world); root.add_child(service); service.set_process(false)
	var host = preload("res://scripts/ui_host.gd").new(); host.interaction = interaction; root.add_child(host)
	controller = preload("res://scripts/areas.gd").new()
	controller.world = world; controller.action_service = service; controller.ui_host = host; controller.interaction = interaction
	root.add_child(controller); host.register(controller); controller.set_process(false)
	controller.open_panel(); service.poll(); reply(0); reply(7)
	controller.zone_types = [{"id":2,"name":"Bedroom","label":"Bedroom","icon":"ZONE_BEDROOM"}]
	open_name(); await process_frame
	check(controller.rename_field.value == "" and controller.rename_field.get_parent() == (controller.stockpile_view if int(pile.kind) == 0 else controller.zone_menu.selected_panel),"empty custom name edits inline, not default label")
	if int(pile.kind) == 0: controller.stockpile_control("rename")
	else: controller.zone_control("rename")
	check(controller.stockpile_page == "rename" and controller.rename_field.visible and controller.rename_field.editing,"repeated quill keeps inline entry active")
	key(0,65); service.poll(); key(0,66); key(0,67)
	check(world.calls[-1].name == "A" and controller.rename_field.value == "ABC","typing remains responsive during an outstanding write")
	accepted("A")
	check(world.calls[-1].name == "ABC" and world.calls[-1].expected_revision == pile.revision,"newest explicit text uses confirmed revision")
	check((controller.stockpile_view if int(pile.kind) == 0 else controller.zone_menu).controls.remove.disabled,"following write keeps other mutations disabled")
	check(not controller.message.visible,"pending rename does not add an unsourced status strip")
	key(KEY_ESCAPE)
	check(not controller.panel.visible and controller.rename_session == null,"Escape closes palette immediately")
	accepted("ABC"); await process_frame
	check(not controller.panel.visible,"late confirmation does not reopen palette")
	controller.open_panel(); service.poll(); reply(0); reply(7); open_name()
	check(controller.rename_field.value == "ABC","reopen uses stored custom name")
	key(KEY_BACKSPACE); service.poll(); key(0,88); key(KEY_ENTER)
	check(controller.panel.visible and not controller.rename_field.visible,"Enter ends editing without closing palette")
	accepted("AB"); check(world.calls[-1].name == "ABX","Enter retains buffered last character")
	accepted("ABX"); await process_frame
	check(controller.selected.custom_name == "ABX" and controller.rename_session == null,"finished sequence publishes final receipt")
	open_name(); key(0,89); service.poll(); key(0,90)
	var before: int = world.calls.size()
	reply(11,{"status":3,"message":"Area changed; inspect again"})
	service.poll(); check(world.calls.size() == before and controller.rename_session == null and not controller.rename_field.editing,"stale mutation drops buffered input")
	check(controller.selected.revision == 0 and (controller.stockpile_view if int(pile.kind) == 0 else controller.zone_menu).controls.rename.disabled,"failed write needs fresh inspection before another edit")
	check((int(pile.kind) == 1 or not controller.message.visible) and not controller.message.text.is_empty(),"rejection retains diagnostics without showing unsourced gameplay copy")
	open_name(); key(0,89); service.poll(); key(0,90)
	before = world.calls.size(); service.poll(16)
	check(controller.rename_session == null and not controller.rename_field.editing,"unknown outcome stops editing")
	accepted("ABXY"); check(world.calls.size() == before and controller.selected.custom_name == "ABX","late unknown receipt cannot replay or update selection")
	for reason in ["epoch","disconnect"]:
		open_name(); key(0,65); service.poll(); key(0,66)
		before = world.calls.size()
		world.state = {"world_epoch":99 if reason == "epoch" else 42,"revision":100,"status":0,"transport_alive":reason != "disconnect"}
		service.poll(); await process_frame
		check(controller.rename_session == null and controller.selected.is_empty() and not controller.rename_field.editing,reason+" retires entry")
		check(world.calls.size() == before,reason+" does not replay edits")
		world.state = {"world_epoch":42,"revision":101,"status":0}; service.poll()
		controller.available = true
	# Switching selection leaves explicit old edits with the service but detaches
	# their UI callbacks, so replies cannot replace the newly selected area.
	controller.panel.show(); open_name(); key(0,81); service.poll(); key(0,82)
	var old_name: String = pile.custom_name
	var other: Dictionary = pile.duplicate(true); other.id += 1000
	controller.use_area(other)
	accepted(old_name+"Q"); accepted(old_name+"QR"); await process_frame
	check(int(controller.selected.id) == int(other.id) and controller.rename_session == null,"old rename receipt replaced a new selection")
	controller.close_panel(); controller.queue_free(); host.queue_free(); service.queue_free(); interaction.queue_free()
	await process_frame
	var samples = JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/areas/native_stockpile_rename.json")).window_text.cases
	var entry = preload("res://scripts/area_name_entry.gd").new(); root.add_child(entry)
	for sample in samples:
		entry.begin("")
		for character in str(sample.typed):
			var event := InputEventKey.new(); event.pressed = true; event.unicode = character.unicode_at(0)
			entry.feed_key(event)
		check(entry.value == str(sample.native.stored),"name input differs from recorded Windows/SDL native bytes")
		check(entry.editing == bool(sample.native.editing),"text-only input changed native editing state")
		entry.finish()
	entry.queue_free(); await process_frame
