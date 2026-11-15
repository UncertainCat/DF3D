extends "res://scripts/workshop_sheet_view.gd"
# Staged lever shell: native Tasks/Workers/Work orders above links/items.
func _create_tasks_view():return preload("res://scripts/lever_tasks_view.gd").new()
func _layout_body() -> void:
	super._layout_body()
	if contents!=null:_layout_contents()
var links_model
var links_view
var showing_links:=false

func configure_links(source,model,help=null) -> void:
	links_model=model
	links_view=preload("res://scripts/building_links_view.gd").new();add_child(links_view)
	links_view.configure(source,model,help);links_view.input_allowed=contents_allowed
	model.changed.connect(_links_changed);_links_changed()
func _links_changed() -> void:
	if links_model.snapshot.is_empty() or not links_model.snapshot.get("tabs",false):showing_links=false
	_layout_contents();queue_redraw()
func contents_extra_height() -> int:
	return 36 if links_model!=null and links_model.snapshot.get("tabs",false) else 0
func _layout_contents() -> void:
	super._layout_contents()
	if links_view==null:return
	links_view.position=contents.position;links_view.set_capacity(contents.page)
	# Removal displays items without discarding the tab restored on cancellation.
	var display_links: bool=showing_links and not state.snapshot.get("removing",false)
	links_view.visible=contents.page>0 and display_links
	contents.visible=contents.page>0 and not display_links
func refresh() -> void:
	if state.building_id!=target:showing_links=false
	super.refresh();_layout_contents()
func link_tab_rect(index: int) -> Rect2:return Rect2(8 if index==0 else 248,456,240 if index==0 else 120,24)
func _exit_tree() -> void:
	if links_model!=null and links_model.changed.is_connected(_links_changed):links_model.changed.disconnect(_links_changed)
	super._exit_tree()
func _gui_input(event: InputEvent) -> void:
	if not state.snapshot.get("removing",false) and contents_extra_height()>0 and contents_allowed() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for index in 2:
			if link_tab_rect(index).has_point(event.position):showing_links=index==0;_layout_contents();queue_redraw();accept_event();return
	super._gui_input(event)
func _draw() -> void:
	super._draw()
	if state.snapshot.get("removing",false) or contents_extra_height()==0 or int(size.y/12)<45:return
	for index in 2:
		var selected: bool=showing_links==(index==0)
		var rect:=link_tab_rect(index);var columns:=int(rect.size.x/8)
		var texture: Texture2D=art.texture("SHORT_TAB_SELECTED" if selected else "SHORT_TAB")
		if texture!=null:
			for y in 2:
				for x in columns:
					var sx:=x if x<2 else 4-(columns-1-x) if x>=columns-2 else 2
					draw_texture_rect_region(texture,Rect2(rect.position+Vector2(x*8,y*12),Vector2(8,12)),Rect2(sx*8,y*12,8,12))
		if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),rect.position+Vector2(16,18),"Show linked buildings" if index==0 else "Show items",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color8(70,44,0) if selected else Color.WHITE)
