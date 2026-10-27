extends Control
# Native155506 frame and verified Details components. Areas owns both entry
# routes; the overall editor stays hidden while remaining controls are unfinished.
var art=preload("res://scripts/original_ui.gd").new()
var state
var heading
var body
var recognition_workflow=preload("res://scripts/location_recognition_workflow.gd").new()
var recognition_view
var value_view
var access_view
var quantity_view
var staff_view
var religious_staff_workflow=preload("res://scripts/location_religious_staff_workflow.gd").new()
var religious_assignment_workflow=preload("res://scripts/location_religious_assignment_workflow.gd").new()
var staff_workflow=preload("res://scripts/location_staff_workflow.gd").new()
var staff_candidates_view
var _candidate_revision:=0
var _candidate_identity: Dictionary={}
var name_workflow=preload("res://scripts/location_name_workflow.gd").new()
var name_view
var rename_button: TextureButton
var type_icon: TextureRect
var input_allowed: Callable

func configure(source, model, help=null) -> void:
	state=model;art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	heading=preload("res://scripts/location_details_heading.gd").new();add_child(heading);heading.configure(source)
	type_icon=TextureRect.new();add_child(type_icon)
	# Native header graphic starts two pixels into its40x36 picture region.
	type_icon.position=Vector2(18,12);type_icon.size=Vector2(32,36)
	type_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;type_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	type_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	body=preload("res://scripts/location_details_body.gd").new();add_child(body);body.configure(source)
	value_view=preload("res://scripts/location_value_view.gd").new();add_child(value_view);value_view.configure(source)
	staff_view=preload("res://scripts/location_staff_view.gd").new();add_child(staff_view);staff_view.configure(source)
	access_view=preload("res://scripts/location_access_view.gd").new();add_child(access_view);access_view.configure(source,model,help)
	quantity_view=preload("res://scripts/location_quantity_view.gd").new();add_child(quantity_view);quantity_view.configure(source,model)
	staff_candidates_view=preload("res://scripts/location_staff_candidates_view.gd").new();add_child(staff_candidates_view);staff_candidates_view.configure(source)
	religious_staff_workflow.configure(model)
	religious_staff_workflow.changed.connect(refresh)
	staff_view.religious_removal_requested.connect(remove_religious_staff)
	religious_assignment_workflow.configure(model)
	religious_assignment_workflow.changed.connect(refresh)
	staff_view.religious_assignment_requested.connect(assign_religious_staff)
	staff_workflow.configure(model)
	staff_workflow.changed.connect(refresh)
	staff_workflow.applied.connect(func():staff_view.display(state.snapshot,0))
	staff_view.assignment_requested.connect(func(id):staff_workflow.open(id))
	staff_view.removal_requested.connect(func(id):staff_workflow.open(id,true))
	staff_candidates_view.unit_chosen.connect(_choose_staff)
	staff_candidates_view.cancelled.connect(_cancel_staff)
	name_workflow.configure(model)
	name_view=preload("res://scripts/location_name_view.gd").new();add_child(name_view);name_view.configure(source,name_workflow.names)
	name_view.input_allowed=func():return not input_allowed.is_valid() or input_allowed.call()
	name_view.cancelled.connect(name_workflow.close)
	name_workflow.changed.connect(refresh)
	rename_button=TextureButton.new();add_child(rename_button)
	rename_button.texture_normal=art.texture("UNIT_SHEET_CUSTOMIZE")
	rename_button.position=Vector2(560,12);rename_button.size=Vector2(32,36)
	rename_button.focus_mode=Control.FOCUS_NONE
	rename_button.pressed.connect(open_name)
	recognition_workflow.configure(model)
	recognition_workflow.changed.connect(refresh)
	recognition_view=preload("res://scripts/location_recognition_view.gd").new();add_child(recognition_view);recognition_view.configure(source,recognition_workflow)
	recognition_view.input_allowed=func():return not input_allowed.is_valid() or input_allowed.call()
	recognition_view.action_requested=recognize
	state.changed.connect(refresh);refresh()

func religious_assignment_active() -> bool:
	return religious_assignment_workflow.mode in [religious_assignment_workflow.Mode.Choosing,religious_assignment_workflow.Mode.Reading,religious_assignment_workflow.Mode.Applying]

func assign_religious_staff(row: Dictionary) -> void:
	if (input_allowed.is_valid() and not input_allowed.call()) or name_workflow.active or religious_assignment_active() or staff_workflow.mode!=staff_workflow.Mode.Closed or state.phase!=state.Phase.Ready:return
	if quantity_view.workflow.pending or not quantity_view.workflow.queue.is_empty():return
	quantity_view.workflow.finish();religious_assignment_workflow.open(row)

func _choose_staff(unit_id: int) -> void:
	if religious_assignment_workflow.mode==religious_assignment_workflow.Mode.Choosing:religious_assignment_workflow.choose(unit_id)
	else:staff_workflow.choose(unit_id)

func _cancel_staff() -> void:
	if religious_assignment_active():religious_assignment_workflow.close()
	else:staff_workflow.close()

func remove_religious_staff(row: Dictionary) -> void:
	if (input_allowed.is_valid() and not input_allowed.call()) or name_workflow.active or religious_assignment_active() or staff_workflow.mode!=staff_workflow.Mode.Closed or state.phase!=state.Phase.Ready:return
	if quantity_view.workflow.pending or not quantity_view.workflow.queue.is_empty():return
	quantity_view.workflow.finish();religious_staff_workflow.remove(row)

func recognize() -> void:
	if (input_allowed.is_valid() and not input_allowed.call()) or name_workflow.active or religious_assignment_active() or staff_workflow.mode!=staff_workflow.Mode.Closed or state.phase!=state.Phase.Ready:return
	if quantity_view.workflow.pending or not quantity_view.workflow.queue.is_empty():return
	quantity_view.workflow.finish();recognition_workflow.recognize()

func open_name() -> void:
	if (input_allowed.is_valid() and not input_allowed.call()) or name_workflow.active or religious_assignment_active() or staff_workflow.mode!=staff_workflow.Mode.Closed or state.phase!=state.Phase.Ready:return
	if quantity_view.workflow.pending or not quantity_view.workflow.queue.is_empty():return
	quantity_view.workflow.finish()
	name_view.reset_input();name_workflow.open()

func layout(view: Vector2) -> void:
	position=Vector2(368,48+fposmod(view.y,12)*0.5)
	size=Vector2(floori(view.x/8)*8-592,floori(view.y/12)*12-132)
	rename_button.position=Vector2(size.x-48,12)
	for child in [heading,body,value_view,staff_view,quantity_view,recognition_view]:
		child.layout(view);child.position-=position
	access_view.position=Vector2(16,60);access_view.size=Vector2(576,36)
	staff_candidates_view.layout(view);staff_candidates_view.position-=position
	name_view.layout(view);name_view.position-=position

func refresh() -> void:
	visible=state.snapshot.get("kind") in [1,2,3,4,5]
	heading.display(state.snapshot);body.display(state.snapshot,quantity_view.FIELDS.get(int(state.snapshot.get("kind",0)),{}).keys());value_view.display(state.snapshot)
	staff_view.display(state.snapshot)
	var religious_selecting: bool=religious_assignment_workflow.mode==religious_assignment_workflow.Mode.Choosing
	var selecting: bool=staff_workflow.mode==staff_workflow.Mode.Choosing or religious_selecting
	var naming: bool=name_workflow.active
	var kind: int=int(state.snapshot.get("kind",0))
	type_icon.texture=art.texture(["","ZONE_TAVERN","ZONE_TEMPLE","ZONE_LIBRARY","ZONE_GUILDHALL","ZONE_HOSPITAL"][kind]) if kind in range(1,6) else null
	type_icon.visible=not selecting and not naming
	for child in [heading,body,value_view,staff_view,access_view,quantity_view]:child.visible=not selecting and not naming
	quantity_view.actions_enabled=staff_workflow.mode==staff_workflow.Mode.Closed and not religious_assignment_active() and not naming
	staff_view.actions_enabled=state.phase==state.Phase.Ready and staff_workflow.mode==staff_workflow.Mode.Closed and not religious_assignment_active() and not naming
	name_view.visible=naming
	rename_button.visible=not selecting and not naming
	rename_button.disabled=state.phase!=state.Phase.Ready or staff_workflow.mode!=staff_workflow.Mode.Closed or religious_assignment_active()
	staff_candidates_view.row_background_token="BUTTON_RECTANGLE" if religious_selecting else "BUTTON_RECTANGLE_DARK"
	staff_candidates_view.scrollbar.use_classic_art=religious_selecting
	staff_candidates_view.visible=selecting
	var candidates=religious_assignment_workflow.candidates if religious_selecting else staff_workflow.candidates
	staff_candidates_view.actions_enabled=selecting and candidates.phase==candidates.Phase.Ready
	var revision: int=candidates.revision if staff_candidates_view.actions_enabled else 0
	if revision!=_candidate_revision or candidates.identity!=_candidate_identity:
		_candidate_revision=revision;_candidate_identity=candidates.identity.duplicate(true)
		staff_candidates_view.display_rows(candidates.rows if revision>0 else [])
	recognition_view.refresh()
	recognition_view.visible=not selecting and not naming and not recognition_view.current.is_empty()
	recognition_view.actions_enabled=state.phase==state.Phase.Ready and staff_workflow.mode==staff_workflow.Mode.Closed and not religious_assignment_active() and not naming and not quantity_view.workflow.pending and quantity_view.workflow.queue.is_empty()
	queue_redraw()

func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
	if staff_workflow.changed.is_connected(refresh):staff_workflow.changed.disconnect(refresh)
	staff_workflow.dispose()
	if religious_staff_workflow.changed.is_connected(refresh):religious_staff_workflow.changed.disconnect(refresh)
	religious_staff_workflow.dispose()
	if religious_assignment_workflow.changed.is_connected(refresh):religious_assignment_workflow.changed.disconnect(refresh)
	religious_assignment_workflow.dispose()
	if name_workflow.changed.is_connected(refresh):name_workflow.changed.disconnect(refresh)
	name_workflow.dispose()
	if recognition_workflow.changed.is_connected(refresh):recognition_workflow.changed.disconnect(refresh)
	recognition_workflow.dispose()

func _draw() -> void:
	if staff_candidates_view!=null and staff_candidates_view.visible:return
	if name_view!=null and name_view.visible:return
	var frame: Texture2D=art.texture("HOVER_RECTANGLE")
	if frame==null:return
	var columns:=int(size.x/8);var lines:=int(size.y/12)
	for y in lines:
		for x in columns:
			draw_texture_rect_region(frame,Rect2(x*8,y*12,8,12),Rect2((0 if x==0 else 16 if x==columns-1 else 8),(0 if y==0 else 24 if y==lines-1 else 12),8,12))
