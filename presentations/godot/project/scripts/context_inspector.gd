extends Node
signal history_requested(unit_id:int)
signal object_requested(kind:int,id:int)
signal focus_requested(tile:Vector3i)
# Local entity identity and presentation only. Queries never navigate DF screens.
const Preferences = preload("res://scripts/presentation_settings.gd")
const OriginalUI = preload("res://scripts/original_ui.gd")
const PAGE_SIZE = 12
var definition = preload("res://scripts/panel_definition.gd").new()
var world
var action_service
var building_removal = preload("res://scripts/building_removal.gd").new()
var building_remove_button: BaseButton
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
var customize=preload("res://scripts/creature_customize_editor.gd").new()
var customize_view
var customize_color: Dictionary={}
var customize_presented:=false
var customize_requested:=false
var hover_help
var hover_position:=Vector2(-1,-1)
var customize_button: BaseButton
var follow
var follow_button: TextureButton
var history_button: TextureButton
var expel=preload("res://scripts/creature_expel_state.gd").new()
var expel_button: TextureButton
var expel_view
var expel_scroll:=0
var knowledge=preload("res://scripts/creature_knowledge_state.gd").new()
var labor=preload("res://scripts/creature_labor_state.gd").new()

func _ready():
	labor.configure(action_service)
	labor.changed.connect(_expel_changed)
	labor.workshop_changed.connect(func(id):
		if not selected.is_empty() and int(selected.kind)==1 and int(selected.id)==id:
			world.demand_creature_info(-1);world.demand_creature_info(id))
	knowledge.configure(action_service)
	knowledge.changed.connect(_expel_changed)
	expel.configure(action_service)
	expel.changed.connect(_expel_changed)
	expel.applied.connect(func(id):
		expel.close()
		if not selected.is_empty() and int(selected.kind)==1 and int(selected.id)==id:
			world.demand_creature_info(-1);world.demand_creature_info(id))
	if follow!=null:follow.changed.connect(_update_follow)
	add_child(customize);customize.configure(action_service)
	customize.changed.connect(func():
		if not is_open() or selected.is_empty():return
		if customize.opened!=customize_presented or customize.requested!=customize_requested:redraw()
		else:_update_customize())
	customize.applied.connect(func():
		if not selected.is_empty() and int(selected.kind)==1:
			world.demand_creature_info(-1);world.demand_creature_info(int(selected.id)))
	building_removal.service = action_service
	building_removal.changed.connect(func():
		if is_open(): redraw())
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
	labor.close()
	if selected.get("kind")!=row.kind or selected.get("id")!=row.id:knowledge.close()
	expel.close()
	customize.close();customize.fallback_generation=-1;customize.fallback_valid=false
	selected = row
	building_removal.select(int(row.id) if int(row.kind) == 3 else -1)
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
	labor.close()
	knowledge.close()
	cancel_gesture()
	creature_sheet.reset(-1)
	expel.close()
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())
	customize.close()
	building_removal.select(-1)
	if ui_host != null: ui_host.release(self)
	if panel != null and panel.visible:
		panel.hide()
		world.demand_resident_info(0)
		world.demand_creature_info(-1)
	selected = {}
	choices = []
	right_down = false

func _exit_tree() -> void:
	if labor.changed.is_connected(_expel_changed):labor.changed.disconnect(_expel_changed)
	labor.dispose()
	if knowledge.changed.is_connected(_expel_changed):knowledge.changed.disconnect(_expel_changed)
	knowledge.dispose()
	if expel.changed.is_connected(_expel_changed):expel.changed.disconnect(_expel_changed)
	expel.dispose()
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())
	building_removal.select(-1)

func set_play_enabled(value: bool):
	play_enabled = value
	if not value: close_panel()

func is_open() -> bool: return panel != null and panel.visible

func _expel_changed() -> void:
	if is_open() and not selected.is_empty():redraw()

func handle_escape() -> void:
	if customize.opened or customize.requested:customize.close()
	elif expel.phase!=expel.Phase.Closed:expel.close()
	elif knowledge.phase in [knowledge.Phase.Reading,knowledge.Phase.Ready]:knowledge.close()
	else:close_panel()

func cancel_gesture() -> void:
	if is_instance_valid(creature_sheet.labor_view):
		creature_sheet.labor_view.scrollbar.dragging=false
		creature_sheet.labor_view.scrollbar.hover_cell=-1
		creature_sheet.labor_view.scrollbar.queue_redraw()
	right_down = false
	right_travel = 0.0
	if is_instance_valid(creature_sheet.items_view):
		creature_sheet.items_view.scrollbar.dragging=false
		creature_sheet.items_view.scrollbar.hover_cell=-1
		creature_sheet.items_view.scrollbar.queue_redraw()
	if is_instance_valid(creature_sheet.skills_view):
		creature_sheet.skills_view.scrollbar.dragging=false
		creature_sheet.skills_view.scrollbar.hover_cell=-1
		creature_sheet.skills_view.scrollbar.queue_redraw()
	if is_instance_valid(creature_sheet.knowledge_view):
		creature_sheet.knowledge_view.scrollbar.dragging=false
		creature_sheet.knowledge_view.scrollbar.hover_cell=-1
		creature_sheet.knowledge_view.scrollbar.queue_redraw()
	if is_instance_valid(creature_sheet.rooms_view):
		creature_sheet.rooms_view.scrollbar.dragging=false
		creature_sheet.rooms_view.scrollbar.hover_cell=-1
		creature_sheet.rooms_view.scrollbar.queue_redraw()
	if is_instance_valid(creature_sheet.health_view):
		creature_sheet.health_view.scrollbar.dragging=false
		creature_sheet.health_view.scrollbar.hover_cell=-1
		creature_sheet.health_view.scrollbar.queue_redraw()
	if is_instance_valid(expel_view):
		expel_view.scrollbar.dragging=false
		expel_view.scrollbar.hover_cell=-1
		expel_view.scrollbar.queue_redraw()

func _process(delta: float):
	if not is_open(): return
	_update_customize()
	_update_customize_help()
	var size := get_viewport().get_visible_rect().size / Preferences.effective_scale_vector(get_viewport().get_visible_rect().size)
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
	if event is InputEventMouseMotion:hover_position=event.position
	if ui_host != null and not ui_host.allows_panel_input(self): return
	if not is_open(): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		handle_escape()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and customize.feed_key(event):
		get_viewport().set_input_as_handled()
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

func _update_customize() -> void:
	if not is_instance_valid(customize_view):return
	var ticks:=Time.get_ticks_msec()
	var color:=preload("res://scripts/native_name_color.gd").choose(customize_color,ticks,randi_range(0,1))
	if color.is_empty():return
	customize_view.present(customize.caption(0,ticks),customize.caption(1,ticks),preload("res://scripts/native_creature_text.gd").colors[color[0]+color[2]*8])

func _update_follow() -> void:
	if not is_instance_valid(follow_button) or selected.is_empty():return
	follow_button.texture_normal=world.ui_texture("UNIT_SHEET_CAMERA_ACTIVE" if follow.unit_id==int(selected.id) else "UNIT_SHEET_CAMERA_INACTIVE")

func _update_customize_help() -> void:
	if not is_instance_valid(hover_help):return
	if is_instance_valid(expel_button) and expel_button.is_visible_in_tree() and not expel_button.disabled and (ui_host==null or ui_host.allows_panel_input(self)):
		var local: Vector2=expel_button.get_global_transform_with_canvas().affine_inverse()*hover_position
		if Rect2(Vector2.ZERO,expel_button.size).has_point(local):hover_help.enter_unit(get_instance_id(),"expel");return
	if is_instance_valid(history_button) and history_button.is_visible_in_tree() and (ui_host==null or ui_host.allows_panel_input(self)):
		var local: Vector2=history_button.get_global_transform_with_canvas().affine_inverse()*hover_position
		if Rect2(Vector2.ZERO,history_button.size).has_point(local):hover_help.enter_unit(get_instance_id(),"reports");return
	if is_instance_valid(follow_button) and follow_button.is_visible_in_tree() and (ui_host==null or ui_host.allows_panel_input(self)):
		var local: Vector2=follow_button.get_global_transform_with_canvas().affine_inverse()*hover_position
		if Rect2(Vector2.ZERO,follow_button.size).has_point(local):hover_help.enter_unit(get_instance_id(),"camera");return
	if is_instance_valid(customize_button) and customize_button.is_visible_in_tree() and not customize_button.disabled and (ui_host==null or ui_host.allows_panel_input(self)):
		var local: Vector2=customize_button.get_global_transform_with_canvas().affine_inverse()*hover_position
		if Rect2(Vector2.ZERO,customize_button.size).has_point(local):hover_help.enter_unit(get_instance_id(),"customize");return
	if creature_sheet.tab=="Items" and is_instance_valid(creature_sheet.items_view):
		var view=creature_sheet.items_view
		var kind: String=view.hover_kind(view.get_global_transform_with_canvas().affine_inverse()*hover_position)
		if not kind.is_empty():hover_help.enter_unit(get_instance_id(),kind);return
	hover_help.leave(get_instance_id())

func label_at(id: String, text: String, native_color: int = -1):
	if text.is_empty(): return
	var label := Label.new()
	var rect: Rect2 = definition.rect(id,body.size)
	label.position = rect.position
	label.size = rect.size
	label.text = text
	if id!="unit.status": label.tooltip_text = text
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if id.begins_with("unit."):
		label.size.x = maxf(32,body.size.x-label.position.x-28)
		if id == "unit.title":
			label.position.y = 12
			label.size.y = 12
		elif id == "unit.subtitle":
			label.position.y = 24
			label.size.y = 12
		elif id == "unit.job":
			label.position.y = 48
			label.add_theme_color_override("font_color",Color.YELLOW)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_size_override("font_size",12)
	if native_color>=0 and native_color<16:
		preload("res://scripts/native_creature_text.gd").load_text(world)
		label.add_theme_color_override("font_color",preload("res://scripts/native_creature_text.gd").colors[native_color])
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
	creature_sheet.remember_scroll()
	if is_instance_valid(expel_view):expel_scroll=expel_view.first
	customize_presented=customize.opened;customize_requested=customize.requested
	var view := get_viewport().get_visible_rect().size
	var scale_factor: Vector2 = Preferences.effective_scale_vector(view)
	view /= scale_factor
	panel.scale = scale_factor
	panel.position = Vector2(maxf(8,view.x-784),48) * scale_factor
	panel.size = Vector2(minf(488,view.x-56),maxf(120,view.y-84))
	if int(selected.kind)==1:
		panel.position=Vector2((floori(view.x/8)-98)*8,48+fposmod(view.y,12)*0.5)*scale_factor
		panel.size=Vector2(488,floori(view.y/12)*12-84)
	body.position = Vector2(8,12)
	body.size = panel.size-Vector2(16,24)
	alternatives.position = Vector2(panel.size.x,0)
	# Header receipts may arrive during an Expel drag. Keep that view attached
	# so rebuilding unrelated header controls does not retire pointer capture.
	var retained_expel=expel_view if expel.phase!=expel.Phase.Closed and is_instance_valid(expel_view) else null
	var retained_items=creature_sheet.items_view if int(selected.kind)==1 and creature_sheet.tab=="Items" and expel.phase==expel.Phase.Closed and is_instance_valid(creature_sheet.items_view) else null
	var retained_health=creature_sheet.health_view if int(selected.kind)==1 and creature_sheet.tab=="Health" and expel.phase==expel.Phase.Closed and is_instance_valid(creature_sheet.health_view) else null
	var retained_skills=creature_sheet.skills_view if int(selected.kind)==1 and creature_sheet.tab=="Skills" and expel.phase==expel.Phase.Closed and is_instance_valid(creature_sheet.skills_view) else null
	var retained_knowledge=creature_sheet.knowledge_view if retained_skills!=null and is_instance_valid(creature_sheet.knowledge_view) else null
	var retained_rooms=creature_sheet.rooms_view if int(selected.kind)==1 and creature_sheet.tab=="Rooms" and expel.phase==expel.Phase.Closed and is_instance_valid(creature_sheet.rooms_view) else null
	var retained_labor=creature_sheet.labor_view if int(selected.kind)==1 and creature_sheet.tab=="Labor" and expel.phase==expel.Phase.Closed and is_instance_valid(creature_sheet.labor_view) else null
	for child in body.get_children():
		if child!=retained_expel and child!=retained_items and child!=retained_health and child!=retained_skills and child!=retained_knowledge and child!=retained_rooms and child!=retained_labor:body.remove_child(child);child.queue_free()
	creature_sheet.items_view=retained_items
	creature_sheet.health_view=retained_health
	creature_sheet.skills_view=retained_skills
	creature_sheet.knowledge_view=retained_knowledge
	creature_sheet.rooms_view=retained_rooms
	creature_sheet.labor_view=retained_labor
	customize_view=null
	customize_button=null
	history_button=null
	expel_button=null
	expel_view=retained_expel
	follow_button=null
	building_remove_button = null
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
			var header_status := ""
			var header_color := 15
			var header_name: Dictionary = {}
			var header_activity := ""
			var activity_color := 15
			var customize_captions: Dictionary={}
			var expel_eligible:=false
			for section in detail.get("sections",[]):
				if section.key!="identity": continue
				for record in section.records:
					var facts: Dictionary={}
					for fact in record.facts: facts[fact.key]=fact.number if fact.get("has_number",false) else fact.get("text","")
					if facts.get("record_type","")=="header_status":
						header_status=facts.get("text","");header_color=int(facts.get("color","15"))
					if facts.get("record_type","")=="header_name": header_name=facts
					if facts.get("record_type","")=="customize_captions":customize_captions=facts
					if facts.get("record_type","")=="expel_eligibility":expel_eligible=int(facts.get("eligible",0))==1
					if facts.get("record_type","")=="header_activity":
						header_activity=str(facts.get("text",""));activity_color=int(facts.get("color",15))
					for fact in record.facts:
						if fact.key=="translated_name": translated=str(fact.text)
			if not header_name.is_empty():
				preload("res://scripts/native_creature_text.gd").load_text(world)
				var name_view:=preload("res://scripts/creature_header_name.gd").new()
				name_view.name="NativeHeaderName";name_view.position=Vector2(104,0)
				name_view.mouse_filter=Control.MOUSE_FILTER_IGNORE
				body.add_child(name_view)
				# Native fixed 60-cell sheet: right-3-6 minus name-left14 minus2.
				name_view.configure(header_name,35)
				customize_color=name_view.description
				name_view.visible=not customize.opened
			label_at("unit.subtitle",'"'+translated+'"' if not translated.is_empty() else "",15)
			label_at("unit.status",header_status,header_color)
			label_at("unit.job",header_activity,activity_color)
			customize.observe_captions(int(detail_state.get("generation",-1)),customize_captions)
			if customize.opened:
				# Customize replaces all ordinary header text, retaining portrait/tabs.
				for child in body.get_children():
					if child!=retained_expel:child.hide()
				customize_view=preload("res://scripts/creature_customize_view.gd").new()
				body.add_child(customize_view);customize_view.configure(world);customize_view.position=Vector2(104,0)
				customize_view.input_allowed=func():return ui_host==null or ui_host.allows_panel_input(self)
				customize_view.field_requested.connect(customize.focus)
				_update_customize()
			elif action_service!=null and not customize_captions.is_empty():
				var button:=TextureButton.new();button.name="Customize"
				customize_button=button
				button.texture_normal=world.ui_texture("UNIT_SHEET_CUSTOMIZE")
				button.position=Vector2(400,0);button.size=Vector2(32,36)
				button.disabled=customize.requested
				button.pressed.connect(func():
					if ui_host==null or ui_host.allows_panel_input(self):customize.open(int(selected.id)))
				body.add_child(button)
			if action_service!=null and not customize.opened:
				history_button=TextureButton.new();history_button.name="CreatureHistory"
				history_button.texture_normal=world.ui_texture("UNIT_SHEET_VIEW_REPORTS")
				history_button.position=Vector2(368,0);history_button.size=Vector2(32,36)
				history_button.pressed.connect(func():
					if ui_host==null or ui_host.allows_panel_input(self):history_requested.emit(int(selected.id)))
				body.add_child(history_button)
			if follow!=null and not customize.opened:
				follow_button=TextureButton.new();follow_button.name="FollowCreature"
				follow_button.position=Vector2(432,0);follow_button.size=Vector2(32,36)
				follow_button.pressed.connect(func():
					if ui_host==null or ui_host.allows_panel_input(self):follow.toggle(int(selected.id)))
				body.add_child(follow_button);_update_follow()
			if action_service!=null and expel_eligible and not customize.opened:
				expel_button=TextureButton.new();expel_button.name="ExpelCreature"
				expel_button.texture_normal=world.ui_texture("UNIT_SHEET_EXPEL")
				expel_button.position=Vector2(432,36);expel_button.size=Vector2(32,36)
				expel_button.disabled=expel.phase==expel.Phase.Applying
				expel_button.pressed.connect(func():
					if ui_host==null or ui_host.allows_panel_input(self):expel_scroll=0;expel.open(int(selected.id)))
				body.add_child(expel_button)
			if world.has_method("creature_portrait"):
				var portrait := TextureRect.new()
				portrait.texture = world.creature_portrait(int(selected.id))
				portrait.position = Vector2.ZERO
				portrait.size = Vector2(96,96)
				portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
				body.add_child(portrait)
			if expel.phase!=expel.Phase.Closed:
				if not is_instance_valid(expel_view):
					expel_view=preload("res://scripts/creature_expel_view.gd").new()
					expel_view.first=expel_scroll
					expel_view.position=Vector2(0,96);expel_view.size=body.size-Vector2(0,96)
					body.add_child(expel_view);expel_view.input_allowed=func():return ui_host==null or ui_host.allows_panel_input(self)
					expel_view.configure(world,expel)
				else:expel_view.size=body.size-Vector2(0,96)
			else:creature_sheet.render(self,detail_state)
		2:
			icon_at("item.icon")
			label_at("item.title",name_text)
			label_at("item.description","Quantity: %d" % int(selected.get("stack",1)))
		3:
			icon_at("building.icon")
			label_at("building.title",name_text)
			label_at("building.door_status","" if selected.get("complete",false) else "Under construction")
			if action_service != null:
				# DF53.16 building sheet: top-row remove icon; queued removal
				# replaces it with the native Cancel removal action (removal.json).
				if building_removal.removing():
					var slated := Label.new()
					slated.text = "Slated for removal"
					slated.position = Vector2(8,76)
					body.add_child(slated)
					var cancel := Button.new()
					cancel.text = "Cancel removal"
					cancel.position = Vector2(8,128)
					cancel.size = Vector2(152,24)
					building_remove_button = cancel
				else:
					var remove := TextureButton.new()
					remove.texture_normal = world.ui_texture("BUILDING_SHEET_REMOVE")
					remove.position = Vector2(body.size.x-80,4)
					remove.size = Vector2(32,36)
					remove.tooltip_text = "Remove this building."
					building_remove_button = remove
				building_remove_button.disabled = not building_removal.available()
				var target := int(selected.id)
				var cancellation := building_removal.removing()
				building_remove_button.pressed.connect(func():
					if building_removal.building_id == target and building_removal.removing() == cancellation:
						building_removal.act())
				body.add_child(building_remove_button)
	var flags: PackedStringArray = []
	for key in ["forbidden","dump","melt","on_fire","rotten","artifact"]:
		if selected.get(key,false): flags.append(str(key).capitalize())
	if not flags.is_empty():
		var status := Label.new()
		status.text = ", ".join(flags)
		status.position = Vector2(8,body.size.y-28)
		status.add_theme_font_size_override("font_size",12)
		body.add_child(status)
	# Native building sheets close through the existing right-click/Escape path;
	# a local Close button here overlaps the native removal action.
	if int(selected.kind) not in [1,3]:
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
