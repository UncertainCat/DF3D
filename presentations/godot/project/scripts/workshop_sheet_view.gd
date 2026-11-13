extends "res://scripts/chest_sheet_view.gd"
# Native workshop shell, workshop-queued / workshop-still-add-task references.
# Staged until worker artwork, Work orders, connections and header edits are complete.
signal tab_requested(index: int)
signal connections_requested
const TABS=["Tasks","Workers","Work orders"]
var tasks
var workers
var orders
var selected_tab:=0

func configure_tasks(source,model,icon: String,help=null) -> void:
	building_icon=icon
	tasks=preload("res://scripts/workshop_tasks_view.gd").new();add_child(tasks)
	tasks.configure(source,model,help);tasks.position=Vector2(16,54)
	# The native tab strip overlaps the top of the Tasks body's rectangle.
	# Let unhandled tab clicks reach the sheet; task actions still consume theirs.
	tasks.mouse_filter=Control.MOUSE_FILTER_PASS
	tasks.input_allowed=tasks_allowed
	tasks.picker_changed.connect(_layout_body)
	refresh()

func configure_workers(source,model) -> void:
	workers=preload("res://scripts/workshop_workers_view.gd").new();add_child(workers)
	workers.configure(source,model);workers.position=Vector2(16,84);workers.size=Vector2(464,360)
	workers.input_allowed=tasks_allowed;_layout_body()

func tasks_allowed() -> bool:
	return allowed() and not removing and state.phase==state.Phase.Ready and state.ticket==0 and (orders==null or orders.state.phase!=orders.state.Phase.Applying) and (workers==null or workers.state.phase!=workers.state.Phase.Applying) and (contents==null or contents.state.phase!=contents.state.Phase.Applying)

func configure_orders(source,model,help=null) -> void:
	orders=preload("res://scripts/workshop_orders_view.gd").new();add_child(orders)
	orders.configure(source,model,help);orders.position=Vector2(16,84);orders.size=Vector2(464,360)
	orders.input_allowed=tasks_allowed;_layout_body()

func contents_allowed() -> bool:
	return super.contents_allowed() and (orders==null or orders.state.phase!=orders.state.Phase.Applying) and (workers==null or workers.state.phase!=workers.state.Phase.Applying) and (tasks==null or tasks.state.phase!=tasks.state.Phase.Applying)

func show_contents_separator() -> bool:return tasks==null or not tasks.picking

func header_art() -> Array:
	var entries:=super.header_art()
	entries.append(["STOCKPILE_SET_CONNECTIONS",Vector2(336,12),Vector2(32,36)])
	return entries

func layout(view: Vector2) -> void:
	super.layout(view);_layout_body()

func refresh() -> void:
	super.refresh();_layout_body()

func _layout_body() -> void:
	if tasks==null:return
	if workers!=null:workers.visible=not removing and selected_tab==1 and not state.snapshot.is_empty()
	if orders!=null:
		orders.visible=not removing and selected_tab==2 and not state.snapshot.is_empty()
		orders.size=Vector2(464,maxf(36,size.y-96) if int(size.y/12)<45 else 360)
	tasks.visible=not removing and selected_tab==0 and not state.snapshot.is_empty()
	var expanded: bool=tasks.picking or int(size.y/12)<45
	tasks.size=Vector2(464,maxf(0,size.y-66 if expanded else 390))
	if contents!=null:contents.visible=contents.page>0 and not tasks.picking
	queue_redraw()

func tab_rect(index: int) -> Rect2:
	return [Rect2(8,48,72,24),Rect2(80,48,88,24),Rect2(168,48,120,24)][index]

func _gui_input(event: InputEvent) -> void:
	if allowed() and not removing and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for index in 3:
			if tab_rect(index).has_point(event.position):tab_requested.emit(index);accept_event();return
		if Rect2(336,12,32,36).has_point(event.position):connections_requested.emit();accept_event();return
	super._gui_input(event)

func _draw() -> void:
	super._draw()
	if removing:return
	for index in 3:
		var rect:=tab_rect(index);var columns:=int(rect.size.x/8)
		var texture: Texture2D=art.texture("SHORT_TAB_SELECTED" if index==selected_tab else "SHORT_TAB")
		if texture!=null:
			for y in 2:
				for x in columns:
					var sx:=x if x<2 else 4-(columns-1-x) if x>=columns-2 else 2
					draw_texture_rect_region(texture,Rect2(rect.position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(sx*8,y*12,8,12))
		if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),rect.position+Vector2(16,18),TABS[index],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color8(70,44,0) if index==selected_tab else Color.WHITE)
