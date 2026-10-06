extends Control
# Native155506 frame and verified Details components. Areas owns both entry
# routes; the overall editor stays hidden while remaining controls are unfinished.
var art=preload("res://scripts/original_ui.gd").new()
var state
var heading
var body
var value_view
var access_view
var staff_view
var staff_workflow=preload("res://scripts/location_staff_workflow.gd").new()
var staff_candidates_view
var _candidate_revision:=0

func configure(source, model, help=null) -> void:
	state=model;art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_STOP
	heading=preload("res://scripts/location_details_heading.gd").new();add_child(heading);heading.configure(source)
	body=preload("res://scripts/location_details_body.gd").new();add_child(body);body.configure(source)
	value_view=preload("res://scripts/location_value_view.gd").new();add_child(value_view);value_view.configure(source)
	staff_view=preload("res://scripts/location_staff_view.gd").new();add_child(staff_view);staff_view.configure(source)
	access_view=preload("res://scripts/location_access_view.gd").new();add_child(access_view);access_view.configure(source,model,help)
	staff_candidates_view=preload("res://scripts/location_staff_candidates_view.gd").new();add_child(staff_candidates_view);staff_candidates_view.configure(source)
	staff_workflow.configure(model)
	staff_workflow.changed.connect(refresh)
	staff_workflow.applied.connect(func():staff_view.display(state.snapshot,0))
	staff_view.assignment_requested.connect(func(id):staff_workflow.open(id))
	staff_view.removal_requested.connect(func(id):staff_workflow.open(id,true))
	staff_candidates_view.unit_chosen.connect(staff_workflow.choose)
	staff_candidates_view.cancelled.connect(staff_workflow.close)
	state.changed.connect(refresh);refresh()

func layout(view: Vector2) -> void:
	position=Vector2(368,48+fposmod(view.y,12)*0.5);size=Vector2(608,660)
	for child in [heading,body,value_view,staff_view]:
		child.layout(view);child.position-=position
	access_view.position=Vector2(16,60);access_view.size=Vector2(576,36)
	staff_candidates_view.layout(view);staff_candidates_view.position-=position

func refresh() -> void:
	visible=state.snapshot.get("kind") in [1,2,3,4,5]
	heading.display(state.snapshot);body.display(state.snapshot);value_view.display(state.snapshot)
	staff_view.display(state.snapshot)
	var selecting: bool=staff_workflow.mode==staff_workflow.Mode.Choosing
	for child in [heading,body,value_view,staff_view,access_view]:child.visible=not selecting
	staff_view.actions_enabled=state.phase==state.Phase.Ready and staff_workflow.mode==staff_workflow.Mode.Closed
	staff_candidates_view.visible=selecting
	var candidates=staff_workflow.candidates
	staff_candidates_view.actions_enabled=selecting and candidates.phase==candidates.Phase.Ready
	var revision: int=candidates.revision if staff_candidates_view.actions_enabled else 0
	if revision!=_candidate_revision:
		_candidate_revision=revision
		staff_candidates_view.display_rows(candidates.rows if revision>0 else [])
	queue_redraw()

func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
	if staff_workflow.changed.is_connected(refresh):staff_workflow.changed.disconnect(refresh)
	staff_workflow.dispose()

func _draw() -> void:
	if staff_candidates_view!=null and staff_candidates_view.visible:return
	var frame: Texture2D=art.texture("HOVER_RECTANGLE")
	if frame==null:return
	for y in 55:
		for x in 76:
			draw_texture_rect_region(frame,Rect2(x*8,y*12,8,12),Rect2((0 if x==0 else 16 if x==75 else 8),(0 if y==0 else 24 if y==54 else 12),8,12))
