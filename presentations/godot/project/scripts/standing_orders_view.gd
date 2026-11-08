extends "res://scripts/location_staff_candidates_frame.gd"
# Staged Workshops/Hauling/Refuse pages; native references114349/121945. Other Labor workflows remain
# unfinished and this surface must not become a public replacement yet.
signal cancelled
const InfoTabs=preload("res://scripts/work_order_info_tabs.gd")
const CAPTIONS=[["No automatic weaving", "Automatically weave dyed thread", "Automatically weave all thread"], ["Use any cloth", "Use only dyed cloth"], ["No automatic web collection", "Automatically collect webs"], ["No automatic slaughter", "Slaughter any marked animal"], ["No automatic butchery", "Automatically butcher carcasses"], ["No automatic fish cleaning", "Automatically clean fish"], ["Do not automate kitchen", "Automate kitchen"], ["Do not automate tannery", "Automate tannery"]]
const CATEGORY_CAPTIONS={1:[["Workers ignore animals", "Workers gather animals"], ["Workers ignore food", "Workers gather food"], ["Workers ignore furniture", "Workers gather furniture"], ["Workers ignore bodies", "Workers gather bodies"], ["Workers ignore minerals", "Workers gather minerals"], ["Workers ignore wood", "Workers gather wood"]],2:[["Workers ignore refuse", "Workers gather refuse"], ["Workers ignore outdoor refuse", "Workers gather outdoor refuse"], ["Workers ignore outdoor vermin remains", "Workers gather outdoor vermin remains"], ["Workers save corpses", "Workers dump corpses"], ["Workers save skulls", "Workers dump skulls"], ["Workers save bones", "Workers dump bones"], ["Workers save shells", "Workers dump shells"], ["Workers save skins", "Workers dump skins"], ["Workers save hair and wool", "Workers dump hair and wool"], ["Workers save other objects", "Workers dump other objects"]]}
const CATEGORIES=["Workshops","Hauling","Refuse","Forbidding","Petitions","Chores","Other"]
var state
var colors: Array[Color]=[]
var input_allowed: Callable
var wide_tabs:=false
func configure_standing_orders(source,model) -> void:
	configure(source);scrollbar.hide();state=model
	colors=art.installed_palette(source.assets_root());mouse_filter=Control.MOUSE_FILTER_STOP
	state.changed.connect(queue_redraw)
func layout(view: Vector2) -> void:
	wide_tabs=floori(view.x/8)>=155;frame_rows=maxi(13,floori(view.y/12)-7)
	position=Vector2(32,48+fposmod(view.y,12)*0.5);size=Vector2((floori(view.x/8)-32)*8,frame_rows*12)
	queue_redraw()
func list_top() -> int:return 96 if wide_tabs else 120
func captions() -> Array:return CAPTIONS if state.category==0 else CATEGORY_CAPTIONS[state.category]
func category_rect(index: int) -> Rect2:
	var x:=8
	for previous in index:x+=(CATEGORIES[previous].length()+4)*8
	return Rect2(x,list_top()-36,(CATEGORIES[index].length()+4)*8,24)
func visible_ids() -> Array[int]:
	var ids: Array[int]=[]
	if state!=null:
		for row: Dictionary in state.settings:
			if row.visible and int(row.id)<captions().size():ids.append(int(row.id))
	return ids
func setting_rect(index: int) -> Rect2:return Rect2(16,list_top()+index*36,400,36)
func allowed() -> bool:return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func _input(event: InputEvent) -> void:
	if not allowed():return
	if (event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
		cancelled.emit();get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	for category in 3:
		if category_rect(category).has_point(event.position):state.select_category(category);return
	if state.phase!=state.Phase.Ready:return
	var ids:=visible_ids()
	for index in ids.size():
		if setting_rect(index).has_point(event.position):
			var id:=ids[index]
			state.set_value(id,(int(state.settings[id].value)+1)%captions()[id].size());return
func text(value: String,point: Vector2,color: int=15) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])
func tab(value: String,point: Vector2,token: String,selected: bool) -> float:
	var width:=value.length()+4
	var texture: Texture2D=art.texture(token+("_SELECTED" if selected else ""))
	if texture!=null:
		for y in 2:
			for x in width:
				var sx:=x if x<2 else x-width+5 if x>=width-2 else 2
				draw_texture_rect_region(texture,Rect2(point+Vector2(x*8,y*12),Vector2(8,12)),Rect2(sx*8,y*12,8,12))
	# Native selected tab ink differs by hierarchy; captured114349.
	var ink:=Color8(70,0,44) if token=="SHORT_SUBSUBTAB" else Color8(70,44,0)
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point+Vector2(16,18),value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,ink if selected else colors[15])
	return width*8
func _draw() -> void:
	if world==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28));patch("HOVER_RECTANGLE",Vector2i.ZERO,int(size.x/8),frame_rows)
	var groups:=InfoTabs.rows(wide_tabs)
	for index in groups.size():
		var x:=8.0
		for caption in groups[index]:x+=tab(caption,Vector2(x,12+index*24),"SHORT_TAB",caption=="Labor")
	var x:=8.0
	for caption in ["Work Details","Standing orders","Kitchen","Stone use"]:x+=tab(caption,Vector2(x,list_top()-60),"SHORT_SUBTAB",caption=="Standing orders")
	x=8.0
	for caption in CATEGORIES:x+=tab(caption,Vector2(x,list_top()-36),"SHORT_SUBSUBTAB",caption==CATEGORIES[state.category])
	var ids:=visible_ids()
	for index in ids.size():
		var rect:=setting_rect(index);var id:=ids[index]
		patch("BUTTON_CATEGORY_RECTANGLE",Vector2i(rect.position/Vector2(8,12)),50,3)
		text(captions()[id][int(state.settings[id].value)],rect.position+Vector2(16,24),15 if state.settings[id].editable else 0)
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(queue_redraw):state.changed.disconnect(queue_redraw)
