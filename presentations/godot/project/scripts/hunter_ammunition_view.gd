extends "res://scripts/location_staff_candidates_frame.gd"
# Staged native ammunition panel. Reference: protected140812, 1200x800.
# Hover and remaining input-edge acceptance remain outstanding.
var state
var colors: Array[Color]=[]
var input_allowed: Callable
var item_icons: Dictionary={}
var picture=preload("res://scripts/native_unit_picture_frame.gd").new()
func configure_ammunition(source,model) -> void:
	configure(source);state=model;colors=art.installed_palette(source.assets_root())
	picture.configure(source)
	mouse_filter=Control.MOUSE_FILTER_STOP;state.changed.connect(refresh)
	scrollbar.input_allowed=allowed;scrollbar.row_changed.connect(scrolled)
	refresh()
func layout(view: Vector2) -> void:
	frame_rows=maxi(25,floori(view.y/12)-21);page_rows=maxi(1,int((frame_rows-13)/3))
	position=Vector2(maxi(4,floori(view.x/8)-129)*8,216+fposmod(view.y,12)*0.5);size=Vector2(808,frame_rows*12)
	scrollbar.dragging=false;scrollbar.position=Vector2(776,60);scrollbar.size=Vector2(16,page_rows*36);scrollbar.page=page_rows
	refresh()
func picker() -> bool:return state.mode in [state.Mode.Types,state.Mode.Materials]
func choices() -> Array:return state.types if state.mode==state.Mode.Types else state.materials
func refresh_art() -> void:
	item_icons.clear()
	for row: Dictionary in state.rules:
		for item: Dictionary in row.items:
			if item.has("appearance"):item_icons[int(item.id)]=world.ammunition_icon(item.appearance,int(item.id))
func rows() -> Array:
	var result: Array=[]
	for index in state.rules.size():
		result.append({"spec":index,"item":-1})
		for item: Dictionary in state.rules[index].items:result.append({"spec":index,"item":item.id,"caption":item.caption})
	return result
func refresh() -> void:
	if state==null or scrollbar==null:return
	refresh_art()
	scrollbar.set_rows(choices().size() if picker() else rows().size(),state.choice_first if picker() else state.first)
	if picker():state.choice_first=scrollbar.first
	else:state.first=scrollbar.first
	queue_redraw()
func scrolled(value: int) -> void:
	if picker():state.choice_first=value
	else:state.first=value
	queue_redraw()
func allowed() -> bool:return is_visible_in_tree() and (not input_allowed.is_valid() or input_allowed.call())
func _input(event: InputEvent) -> void:
	if not allowed():return
	if (event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT):
		state.back();get_viewport().set_input_as_handled();return
	if not event is InputEventKey or not event.pressed or state.mode!=state.Mode.Amount:return
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:state.commit_amount()
	elif event.keycode==KEY_BACKSPACE:state.set_amount_text(state.amount_text.left(-1))
	elif event.unicode>=48 and event.unicode<=57:state.set_amount_text(state.amount_text+char(event.unicode))
	else:return
	get_viewport().set_input_as_handled()
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(scrollbar.first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(page_rows if event.shift_pressed else 1));return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	if Rect2(720,20,72,24).has_point(event.position):state.back();return
	if picker():
		if Rect2(16,60,760,page_rows*36).has_point(event.position):state.choose(state.choice_first+int((event.position.y-60)/36))
		return
	if Rect2(272,20,152,24).has_point(event.position):state.begin_add();return
	var entries:=rows()
	for visible_index in mini(page_rows,entries.size()-state.first):
		var entry: Dictionary=entries[state.first+visible_index];var y:=60+visible_index*36
		if entry.item==-1:
			if Rect2(336,y+8,40,24).has_point(event.position):state.begin_material(entry.spec);return
			if Rect2(384,y+8,40,24).has_point(event.position):state.begin_amount(entry.spec);return
		if Rect2(action_x(),y+8,64,24).has_point(event.position):
			if entry.item==-1:state.delete_rule(entry.spec)
			else:state.remove_stack(entry.spec,entry.item)
			return
func text(value: String,point: Vector2,color: int=15) -> void:
	if theme.default_font!=null:theme.default_font.draw_string(get_canvas_item(),point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,12,colors[color])
func button(value: String,rect: Rect2,color: int=10,cancel: bool=false) -> void:
	patch("HORIZONTAL_OPTION_REMOVE" if cancel else "HORIZONTAL_OPTION_ACTIVE",Vector2i(int(rect.position.x/8),int((rect.position.y-8)/12)),int(rect.size.x/8),3)
	text(value,rect.position+Vector2(16 if value=="Add ammunition" else 8,16),color)
func action_x() -> int:return 704 if scrollbar.visible else 720
func _draw() -> void:
	if world==null or state==null:return
	draw_rect(Rect2(Vector2(4,4),size-Vector2(8,8)),Color8(28,28,28));patch("HOVER_RECTANGLE",Vector2i.ZERO,101,frame_rows)
	if not picker():text("Hunters",Vector2(64,36))
	if picker():button("Cancel",Rect2(728,20,64,24),15,true)
	else:
		button("Add ammunition",Rect2(272,20,152,24));button("Confirm",Rect2(720,20,72,24))
	if picker():
		var list:=choices()
		for visible_index in mini(page_rows,list.size()-state.choice_first):
			var y:=60+visible_index*36
			patch("BUTTON_RECTANGLE",Vector2i(2,int(y/12)),95 if scrollbar.visible else 97,3)
			text(list[state.choice_first+visible_index].caption,Vector2(32,y+24))
		return
	var entries:=rows()
	for visible_index in mini(page_rows,entries.size()-state.first):
		var entry: Dictionary=entries[state.first+visible_index];var y:=60+visible_index*36
		patch("BUTTON_RECTANGLE",Vector2i(2,int(y/12)),95 if scrollbar.visible else 97,3)
		if entry.item==-1:
			text(state.rules[entry.spec].caption,Vector2(32,y+24))
			var amount: String=state.amount_text if state.mode==state.Mode.Amount and state.selected==entry.spec else str(int(state.specs[entry.spec].amount))
			text(str(state.rules[entry.spec].quantity)+"/"+amount,Vector2(256,y+24))
			button("Mat",Rect2(336,y+8,40,24));button("Amt",Rect2(384,y+8,40,24));button("Delete",Rect2(action_x(),y+8,64,24),12)
		else:
			var frame: Texture2D=picture.texture(false)
			if frame!=null:patch("BUTTON_PICTURE_BOX",Vector2i(2,int(y/12)),5,3,frame)
			var icon: Texture2D=item_icons.get(int(entry.item))
			if icon!=null:draw_texture_rect(icon,Rect2(18,y+2,32,32),false)
			text(entry.caption,Vector2(64,y+24),14);button("Remove",Rect2(action_x(),y+8,64,24),12)
func _exit_tree() -> void:
	if state!=null and state.changed.is_connected(refresh):state.changed.disconnect(refresh)
