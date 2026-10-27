extends Control
signal assignment_requested(occupation_id: int)
signal removal_requested(occupation_id: int)
signal religious_removal_requested(row: Dictionary)
signal religious_assignment_requested(row: Dictionary)
signal specialization_requested(row: Dictionary, displayed: Dictionary)
# Native staff rows and assignment/removal hit regions. Religious assignment,
# specialization and remaining input details keep the parent entry routes hidden.
const Format=preload("res://scripts/location_details_format.gd")
const ICONS={0:"TAVERN_KEEPER",1:"PERFORMER",2:"SCHOLAR",5:"SCRIBE",7:"DOCTOR",8:"DOCTOR",9:"DOCTOR",10:"DOCTOR"}
var art=preload("res://scripts/original_ui.gd").new()
var rows: Array=[]
var geometry: Dictionary={}
var first:=0
var actions_enabled:=false
var identity: Array=[]
var native_scroll
var world
var unit_icons: Dictionary={}
var icon_elapsed:=0.0
var picture_frame=preload("res://scripts/native_unit_picture_frame.gd").new()
var specialization_reader
var hover_help
var pointer_known:=false
var pointer_position:=Vector2.ZERO

func visible_rows() -> Array:
	return rows.slice(first,first+int(geometry.get("visible_count",0)))

func specialization_rect(index: int) -> Rect2:
	# Native3b154b/3b857e: rightmost row cell minus23, four by three cells.
	return Rect2((row_columns()-24)*8,(int(geometry.first_y)-6+index*3)*12,32,36)

func configure(source, help=null) -> void:
	hover_help=help
	world=source;art.configure(source);theme=art.theme
	picture_frame.configure(source)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_PASS
	mouse_exited.connect(_leave_specialization_hover)
	visibility_changed.connect(func():
		if not is_visible_in_tree():_leave_specialization_hover())
	native_scroll=preload("res://scripts/area_location_scrollbar.gd").new();add_child(native_scroll);native_scroll.configure(source)
	native_scroll.row_changed.connect(func(value):first=value;queue_redraw())

func layout(view: Vector2) -> void:
	position=Vector2(384,60+fposmod(view.y,12)*0.5)
	size=Vector2(floori(view.x/8)*8-624,636)
	update_geometry()
	queue_redraw()

func row_columns() -> int:
	return int(size.x/8)-(2 if int(geometry.get("max_scroll",0))>0 else 0)

func update_geometry() -> void:
	if geometry.is_empty():return
	geometry.width=row_columns()-58
	if native_scroll!=null:native_scroll.position.x=size.x-16

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		pointer_known=true;pointer_position=event.position;update_specialization_hover()
	if not actions_enabled or geometry.is_empty() or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	for index in int(geometry.visible_count):
		var row: Dictionary=rows[first+index]
		if int(row.get("source",-1)) not in [0,1]:continue
		var top: float=(int(geometry.first_y)-6+index*3)*12
		if specialization_reader!=null and specialization_rect(index).has_point(event.position):
			var facts: Dictionary=specialization_reader.receipt(row)
			if facts.get("eligible",false):
				specialization_requested.emit(row.duplicate(true),facts);accept_event();return
		var occupied:=int(row.get("unit_id",-1))>=0 or int(row.get("histfig_id",-1))>=0
		var left: float=(row_columns()-4)*8 if occupied else 192
		if Rect2(left,top,32,36).has_point(event.position):
			if int(row.get("source",-1))==1:
				if occupied:religious_removal_requested.emit(row.duplicate(true))
				else:religious_assignment_requested.emit(row.duplicate(true))
			elif occupied:removal_requested.emit(int(row.occupation_id))
			else:assignment_requested.emit(int(row.occupation_id))
			accept_event();return

func display(details: Dictionary, offset:=-1) -> void:
	var next_identity: Array=[details.get("site_id"),details.get("id"),details.get("kind")]
	if offset>=0:first=offset
	elif next_identity!=identity:first=0
	identity=next_identity;rows=[];geometry={}
	var staff=details.get("staff")
	if staff is Dictionary and staff.get("rows") is Array:
		rows=staff.rows.duplicate(true)
		geometry=Format.staff_layout(int(details.get("kind",0)),rows.size())
		if not geometry.is_empty():first=clampi(first,0,int(geometry.max_scroll))
	if native_scroll!=null:
		if geometry.is_empty():
			first=0;native_scroll.set_rows(0)
		else:
			native_scroll.position=Vector2(560,(int(geometry.first_y)-6)*12)
			native_scroll.page=int(geometry.capacity);native_scroll.size=Vector2(16,native_scroll.page*36)
			native_scroll.set_rows(rows.size(),first)
	update_geometry()
	queue_redraw()
	update_icons()

func _process(delta: float) -> void:
	update_specialization_hover()
	if not is_visible_in_tree() or geometry.is_empty():return
	icon_elapsed+=delta
	if icon_elapsed>=0.25:icon_elapsed=0;update_icons()

func update_specialization_hover() -> void:
	if not is_instance_valid(hover_help):return
	if pointer_known and is_visible_in_tree() and specialization_reader!=null and not geometry.is_empty():
		for index in int(geometry.visible_count):
			if specialization_rect(index).has_point(pointer_position):
				var facts: Dictionary=specialization_reader.receipt(rows[first+index])
				if facts.get("eligible",false):
					hover_help.enter_specialization(get_instance_id(),facts.specialized);return
	hover_help.leave(get_instance_id())

func _leave_specialization_hover() -> void:
	pointer_known=false
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())

func _exit_tree() -> void:
	if is_instance_valid(hover_help):hover_help.leave(get_instance_id())

func update_icons() -> void:
	var wanted: Dictionary={}
	if world!=null and world.has_method("selection_icon") and not geometry.is_empty():
		for i in int(geometry.visible_count):
			var names: Dictionary=rows[first+i].get("names",{})
			if int(names.get("holder_kind",0))!=1:continue
			var id:=int(names.get("holder_id",-1))
			if id<0:continue
			wanted[id]=true
			var icon: Texture2D=world.selection_icon(1,id,true)
			if icon!=null:
				unit_icons[id]=icon
	for id in unit_icons.keys():
		if not wanted.has(id):unit_icons.erase(id)
	queue_redraw()

func _draw() -> void:
	if geometry.is_empty() or theme==null:return
	var font: Font=theme.default_font
	var background: Texture2D=art.texture("BUTTON_RECTANGLE")
	var columns:=row_columns()
	for i in int(geometry.visible_count):
		var row: Dictionary=rows[first+i]
		var top:=Vector2(0,(int(geometry.first_y)-6+i*3)*12)
		if background!=null:
			for y in 3:
				for x in columns:
					draw_texture_rect_region(background,Rect2(top+Vector2(x*8,y*12),Vector2(8,12)),Rect2((0 if x==0 else 16 if x==columns-1 else 8),y*12,8,12))
		var names: Dictionary=row.get("names",{})
		# Native224159: full-body icon at +2,+2 in a40x36 picture frame.
		# Historical-figure name fallback has no image/frame.
		if int(names.get("holder_kind",0))==1:
			var picture: Texture2D=picture_frame.texture(false)
			if picture!=null:
				for y in 3:
					for x in 5:
						draw_texture_rect_region(picture,Rect2(top+Vector2(192+x*8,y*12),Vector2(8,12)),Rect2((0 if x==0 else 16 if x==4 else 8),y*12,8,12))
			var unit_icon: Texture2D=unit_icons.get(int(names.get("holder_id",-1)))
			if unit_icon!=null:draw_texture_rect(unit_icon,Rect2(top+Vector2(194,2),Vector2(32,32)),false)
		elif int(row.get("source",-1)) in [0,1] and int(row.get("unit_id",-2))==-1 and int(row.get("histfig_id",-2))==-1:
			# Native232551 ordinary /054344 religious vacant assignment icon.
			var assign: Texture2D=art.texture("LOCATION_ASSIGN_OCCUPATION")
			if assign!=null:draw_texture_rect(assign,Rect2(top+Vector2(192,0),Vector2(32,36)),false)
		var label: Variant=null
		var token: String=""
		if int(row.get("source",-1))==1:
			label=names.get("position_name")
			token="LOCATION_POSITION_TEMPLE"
		elif int(row.get("source",-1))==0:
			label=Format.occupation_label(row.get("role"))
			if ICONS.has(row.get("role")):token="LOCATION_OCCUPATION_"+ICONS[row.role]
		if not token.is_empty():
			var icon: Texture2D=art.texture(token)
			if icon!=null:draw_texture_rect(icon,Rect2(top,Vector2(32,36)),false)
		if font==null:continue
		if label is String:font.draw_string(get_canvas_item(),top+Vector2(48,24),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
		var holder=Format.staff_holder_name(names.get("holder_name"),int(geometry.width))
		if holder is String:font.draw_string(get_canvas_item(),top+Vector2(248,24),holder,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
		if specialization_reader!=null:
			var facts: Dictionary=specialization_reader.receipt(row)
			if facts.get("eligible",false):
				var worker: Texture2D=art.texture("WORKER_ONLY_DO_ASSIGNED_JOBS" if facts.specialized else "WORKER_DO_ANY_AVAILABLE_JOB")
				var region:=specialization_rect(i)
				# Native graphical cells replace name text beneath transparent art.
				if background!=null:
					for y in 3:
						for x in 4:draw_texture_rect_region(background,Rect2(region.position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(8,y*12,8,12))
				if worker!=null:draw_texture_rect(worker,region,false)
		if int(row.get("unit_id",-1))>=0 or int(row.get("histfig_id",-1))>=0:
			# Native232551: four cells at the right edge of the row, before
			# the scrollbar when present. Religious holders use the same art.
			var remove_worker: Texture2D=art.texture("LOCATION_OCCUPATION_REMOVE_WORKER")
			# Native graphical cells replace underlying text, including the
			# transparent margins of the remove icon.
			if background!=null:
				for y in 3:
					for x in range(columns-4,columns):
						draw_texture_rect_region(background,Rect2(top+Vector2(x*8,y*12),Vector2(8,12)),Rect2(16 if x==columns-1 else 8,y*12,8,12))
			if remove_worker!=null:draw_texture_rect(remove_worker,Rect2(top+Vector2((columns-4)*8,0),Vector2(32,36)),false)
