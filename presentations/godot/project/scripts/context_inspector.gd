extends Node
# Local entity identity and presentation only. Queries never navigate DF screens.
const Preferences = preload("res://scripts/presentation_settings.gd")
const OriginalUI = preload("res://scripts/original_ui.gd")
const PAGE_SIZE = 12
var definition = preload("res://scripts/panel_definition.gd").new()
var world
var interaction
var ui_host
var modal_input := false
var panel: Panel
var body: Control
var alternatives: VBoxContainer
var selected: Dictionary = {}
var choices: Array = []
var page := 0
var epoch := 0
var play_enabled := true
var elapsed := 0.0
var right_down := false
var right_travel := 0.0
var last_size := Vector2.ZERO
var creature_sheet = preload("res://scripts/creature_sheet.gd").new()
var creature_generation := -1
var creature_display := {}
var creature_status := {}
var creature_texture: Texture2D

func _ready():
	if not definition.load_file("res://panels/native_selection.json"):
		push_error("Inspector layout: "+"; ".join(definition.errors))
		return
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	panel = Panel.new()
	canvas.add_child(panel)
	var art := OriginalUI.new()
	art.configure(world)
	panel.theme = art.theme
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var style := StyleBoxTexture.new()
	style.texture = world.ui_texture("HOVER_RECTANGLE")
	for side in [SIDE_LEFT,SIDE_RIGHT]: style.set_texture_margin(side,8)
	for side in [SIDE_TOP,SIDE_BOTTOM]: style.set_texture_margin(side,12)
	panel.add_theme_stylebox_override("panel",style)
	body = Control.new()
	body.clip_contents = true
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)
	alternatives = VBoxContainer.new()
	alternatives.add_theme_constant_override("separation",0)
	panel.add_child(alternatives)
	panel.hide()

func open_tile(tile: Vector3i):
	open_target(tile,0,-1)

func open_target(tile: Vector3i, kind: int, id: int):
	if not play_enabled or panel == null: return
	var rows: Array = world.inspect_tile(tile)
	var target: Dictionary = world.inspect_entity(kind,id) if kind > 0 else {}
	if rows.is_empty() and target.is_empty():
		close_panel()
		return
	if ui_host != null and not ui_host.activate(self): return
	choices = rows
	if not target.is_empty() and not choices.any(func(row): return row.kind == kind and row.id == id): choices.push_front(target)
	epoch = int(world.resident_info_state().get("world_epoch",0))
	page = 0
	panel.show()
	interaction.cancel_selection()
	choose(target if not target.is_empty() else choices[0])

func choose(row: Dictionary):
	selected = row
	world.demand_resident_info(0)
	world.demand_creature_info(int(row.id) if int(row.kind) == 1 else -1)
	if int(row.kind) == 1: creature_sheet.reset(int(row.id))
	creature_generation = -1
	creature_display = {}
	creature_status = {}
	creature_texture = null
	for i in choices.size():
		if choices[i].kind == row.kind and choices[i].id == row.id: page = i / PAGE_SIZE; break
	redraw()

func close_panel():
	if ui_host != null: ui_host.release(self)
	if panel != null and panel.visible:
		panel.hide()
		world.demand_resident_info(0)
		world.demand_creature_info(-1)
	selected = {}
	choices = []
	right_down = false

func set_play_enabled(value: bool):
	play_enabled = value
	if not value: close_panel()

func is_open() -> bool: return panel != null and panel.visible

func cancel_gesture() -> void:
	right_down = false
	right_travel = 0.0

func _process(delta: float):
	if not is_open(): return
	var size := get_viewport().get_visible_rect().size / Preferences.effective_scale(get_viewport().get_visible_rect().size)
	if size != last_size:
		last_size = size
		redraw()
	elapsed += delta
	if elapsed < 0.25: return
	elapsed = 0
	var current_epoch := int(world.resident_info_state().get("world_epoch",0))
	if epoch != 0 and epoch != current_epoch: close_panel(); return
	epoch = current_epoch
	var row: Dictionary = world.inspect_entity(int(selected.kind),int(selected.id))
	if row.is_empty(): close_panel(); return
	# Ignore transport revisions and movement when comparing displayed facts.
	var previous := selected.duplicate()
	var next := row.duplicate()
	for key in ["version","tick","origin","tile","summary_generation","summary_capture_completed_ms"]:
		previous.erase(key); next.erase(key)
	selected = row
	var changed := false
	if int(row.kind) == 1:
		var detail_state: Dictionary = world.creature_info_state(int(row.id))
		var revision := int(detail_state.get("generation",0))
		var status := {"stale":detail_state.get("stale",false) and not detail_state.get("loading",false),"error":detail_state.get("error","")}
		if detail_state.get("detail",{}).is_empty(): status["loading"] = detail_state.get("loading",false)
		if revision != creature_generation or status != creature_status:
			var facts: Dictionary = detail_state.get("detail",{}).duplicate()
			facts.erase("captured_tick")
			var display := {"detail":facts,"stale":status.stale,"error":status.error}
			if facts.is_empty(): display["loading"] = detail_state.get("loading",false)
			changed = display != creature_display
			if world.has_method("creature_portrait"):
				var texture: Texture2D = world.creature_portrait(int(row.id))
				changed = changed or texture != creature_texture
				creature_texture = texture
			creature_display = display
			creature_generation = revision
			creature_status = status
	if previous != next or changed: redraw()

func _input(event):
	if ui_host != null and not ui_host.allows_panel_input(self): return
	if not is_open(): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_panel(); get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and right_down:
		right_travel += event.relative.length()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed: right_down = true; right_travel = 0
		else:
			var click := right_down and right_travel < 4
			right_down = false
			if click: close_panel(); get_viewport().set_input_as_handled()

func clear_children(node: Node):
	for child in node.get_children(): node.remove_child(child); child.queue_free()

func label_at(id: String, text: String):
	if text.is_empty(): return
	var label := Label.new()
	var rect: Rect2 = definition.rect(id,body.size)
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.tooltip_text = text
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if id.begins_with("unit."):
		label.size.x = maxf(32,body.size.x-label.position.x-28)
		if id == "unit.title":
			label.position.y = 8
			label.size.y = 12
		elif id == "unit.subtitle":
			label.position.y = 20
			label.size.y = 12
		elif id == "unit.job":
			label.position.y = 44
			label.add_theme_color_override("font_color",Color.YELLOW)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_size_override("font_size",12)
	body.add_child(label)

func icon_at(id: String):
	var icon := TextureRect.new()
	var rect: Rect2 = definition.rect(id,body.size)
	icon.position = rect.position
	icon.size = rect.size
	icon.texture = world.selection_icon(int(selected.kind),int(selected.id))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(icon)

func redraw():
	if selected.is_empty(): return
	var view := get_viewport().get_visible_rect().size
	var scale_factor: float = Preferences.effective_scale(view)
	view /= scale_factor
	panel.scale = Vector2.ONE * scale_factor
	panel.position = Vector2(maxf(8,view.x-784),48) * scale_factor
	panel.size = Vector2(minf(488,view.x-56),maxf(120,view.y-84))
	body.position = Vector2(8,12)
	body.size = panel.size-Vector2(16,24)
	alternatives.position = Vector2(panel.size.x,0)
	clear_children(body)
	clear_children(alternatives)
	var name_text := str(selected.get("name",""))
	var material := str(selected.get("material",""))
	# These are material tokens, not native item descriptions. Keep them readable.
	if not material.is_empty(): name_text = material.get_slice(":",material.get_slice_count(":")-1).capitalize()+" "+name_text
	match int(selected.kind):
		1:
			var detail_state: Dictionary = world.creature_info_state(int(selected.id))
			var detail: Dictionary = detail_state.get("detail",{})
			name_text = str(detail.get("name",name_text))
			var translated := ""
			for section in detail.get("sections",[]):
				if section.key!="identity": continue
				for record in section.records:
					for fact in record.facts:
						if fact.key=="translated_name": translated=str(fact.text)
			var quote := name_text.find('"')
			if quote>=0:
				var end_quote := name_text.find('"',quote+1)
				if end_quote>quote: name_text=(name_text.substr(0,quote).strip_edges()+name_text.substr(end_quote+1)).strip_edges()
			label_at("unit.title",name_text)
			label_at("unit.subtitle",'"'+translated+'"' if not translated.is_empty() else "")
			label_at("unit.job",str(detail.get("job",selected.get("job",""))))
			if world.has_method("creature_portrait"):
				var portrait := TextureRect.new()
				portrait.texture = world.creature_portrait(int(selected.id))
				portrait.position = Vector2.ZERO
				portrait.size = Vector2(96,96)
				portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
				body.add_child(portrait)
			creature_sheet.render(self,detail_state)
		2:
			icon_at("item.icon")
			label_at("item.title",name_text)
			label_at("item.description","Quantity: %d" % int(selected.get("stack",1)))
		3:
			icon_at("building.icon")
			label_at("building.title",name_text)
			label_at("building.door_status","" if selected.get("complete",false) else "Under construction")
	var flags: PackedStringArray = []
	for key in ["forbidden","dump","melt","on_fire","rotten","artifact"]:
		if selected.get(key,false): flags.append(str(key).capitalize())
	if not flags.is_empty():
		var status := Label.new()
		status.text = ", ".join(flags)
		status.position = Vector2(8,body.size.y-28)
		status.add_theme_font_size_override("font_size",12)
		body.add_child(status)
	var close := Button.new()
	close.text = "Close"
	close.size = Vector2(60,24)
	close.position = Vector2(body.size.x-close.size.x,0)
	close.pressed.connect(close_panel)
	body.add_child(close)
	# Bounded pages avoid creating thousands of Controls for a stockpile stack.
	for i in range(page*PAGE_SIZE,mini(choices.size(),(page+1)*PAGE_SIZE)):
		var row: Dictionary = choices[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(32,36)
		button.icon = world.selection_icon(int(row.kind),int(row.id))
		button.expand_icon = true
		button.toggle_mode = true
		button.button_pressed = row.kind == selected.kind and row.id == selected.id
		button.tooltip_text = str(row.name)
		button.pressed.connect(func():
			var fresh: Dictionary = world.inspect_entity(int(row.kind),int(row.id))
			if not fresh.is_empty(): choose(fresh)
		)
		alternatives.add_child(button)
	if choices.size() > PAGE_SIZE:
		var more := Button.new()
		more.text = "%d/%d" % [page+1,ceili(float(choices.size())/PAGE_SIZE)]
		more.tooltip_text = "Next page of objects on this tile"
		more.pressed.connect(func(): page = (page+1) % ceili(float(choices.size())/PAGE_SIZE); redraw())
		alternatives.add_child(more)
