extends "res://scripts/standing_orders_view.gd"
# Staged read-only case view. Native captures190710 at1200x800 establish
# this layout; action controls and the remaining categories are unfinished.
const C=preload("res://scripts/management_contract.gd")
const CASE_TABS=["Open cases","Closed cases","Cold cases","Fortress guard","Convicts","Intelligence"]
var witness_scroll
func configure_justice(source,model) -> void:
	configure_standing_orders(source,model)
	scrollbar.input_allowed=allowed;scrollbar.wheel_enabled=false
	scrollbar.row_changed.connect(func(value):state.seek(value,capacity()))
	witness_scroll=preload("res://scripts/area_location_scrollbar.gd").new();add_child(witness_scroll);witness_scroll.configure(source)
	witness_scroll.input_allowed=allowed;witness_scroll.wheel_enabled=false
	witness_scroll.row_changed.connect(func(value):state.seek_witness(value,witness_capacity()))
	state.changed.connect(refresh);refresh()
func information_rows() -> Array:
	var groups:=InfoTabs.rows(wide_tabs)
	if not wide_tabs:groups.reverse()
	return groups
func list_top() -> int:return 72 if wide_tabs else 96
func detail_x() -> int:return int(size.x/16)*8+8
func capacity() -> int:return maxi(0,int((size.y-list_top()-24)/36))
func witness_capacity() -> int:return maxi(0,int((size.y-list_top()-96)/60))
func visible_first() -> int:return mini(state.first,maxi(0,state.rows.size()-capacity()))
func witness_first() -> int:return mini(state.witness_first,maxi(0,state.detail.get("witnesses",[]).size()-witness_capacity()))
func tab_rect(index: int) -> Rect2:
	var x:=8
	for previous in index:x+=(CASE_TABS[previous].length()+4)*8
	return Rect2(x,36 if wide_tabs else 60,(CASE_TABS[index].length()+4)*8,24)
func case_rect(index: int) -> Rect2:
	return Rect2(16,list_top()+index*36,detail_x()-40-(16 if state.rows.size()>capacity() else 0),36)
func layout(view: Vector2) -> void:
	super.layout(view)
	if state!=null:refresh()
func refresh() -> void:
	scrollbar.position=Vector2(detail_x()-40,list_top());scrollbar.size=Vector2(16,capacity()*36)
	scrollbar.page=capacity();scrollbar.set_rows(state.rows.size(),visible_first())
	witness_scroll.position=Vector2(size.x-32,list_top()+72);witness_scroll.size=Vector2(16,maxi(0,int((size.y-list_top()-96)/12))*12)
	witness_scroll.page=witness_capacity();witness_scroll.set_rows(state.detail.get("witnesses",[]).size(),witness_first());queue_redraw()
func _input(event: InputEvent) -> void:
	if allowed() and state!=null and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var point: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
		if Rect2(Vector2(0,list_top()),size-Vector2(0,list_top())).has_point(point):
			var step: int=-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1
			if point.x<detail_x():state.seek(visible_first()+step,capacity())
			else:state.seek_witness(witness_first()+step,witness_capacity())
			get_viewport().set_input_as_handled();return
	super._input(event)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var groups:=information_rows()
	for row in groups.size():
		var x:=8
		for caption in groups[row]:
			var width: int=(caption.length()+4)*8
			if Rect2(x,12+row*24,width,24).has_point(event.position):
				if caption!="Justice":information_requested.emit(caption)
				return
			x+=width
	for index in 3:
		if tab_rect(index).has_point(event.position):state.select_tab(index);return
	if state.phase not in [state.Phase.Ready,state.Phase.DetailReading]:return
	for index in mini(capacity(),state.rows.size()-visible_first()):
		if case_rect(index).has_point(event.position):state.select_case(state.rows[visible_first()+index].crime_id);return
func _draw() -> void:
	if world==null or state==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28));patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=information_rows()
	for index in groups.size():
		var x:=8.0
		for caption in groups[index]:x+=tab(caption,Vector2(x,12+index*24),"SHORT_TAB",caption=="Justice")
	for index in 6:tab(CASE_TABS[index],tab_rect(index).position,"SHORT_SUBTAB",index==state.tab)
	for index in mini(capacity(),state.rows.size()-visible_first()):
		var row: Dictionary=state.rows[visible_first()+index];var rect:=case_rect(index)
		patch("BUTTON_CATEGORY_RECTANGLE_SELECTED" if row.crime_id==state.selected_id else "BUTTON_CATEGORY_RECTANGLE",Vector2i(rect.position/Vector2(8,12)),int(rect.size.x/8),3)
		text(row.caption,rect.position+Vector2(16,24))
	if state.detail.is_empty():return
	var d: Dictionary=state.detail;var x:=detail_x();var top:=list_top()
	if d.has("injured_party"):text(d.injured_party,Vector2(x,top+12),7)
	text(d.status,Vector2(x,top+24),11 if d.resolution==C.JusticeCaseResolution.Unsolved else 13)
	var witnesses: Array=d.witnesses
	for index in mini(witness_capacity(),witnesses.size()-witness_first()):
		var row: Dictionary=witnesses[witness_first()+index];var y:=top+72+index*60
		text(row.witness,Vector2(x,y+12));text(row.description,Vector2(x,y+24),14)
		text(row.date,Vector2(x,y+36),7);text(row.reported,Vector2(x,y+48),7)
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
	super._exit_tree()
