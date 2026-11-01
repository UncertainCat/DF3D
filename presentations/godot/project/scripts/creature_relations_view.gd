extends "res://scripts/creature_items_view.gd"
signal focus_requested(tile:Vector3i)
signal inspect_relative_requested(tile:Vector3i,unit_id:int)
const NameColor=preload("res://scripts/native_name_color.gd")
var names: Array=[]
func present(records:Array) -> void:
	super.present(records);names.clear();icons.clear()
	for row in rows:
		var unit:=int(fact(row,"unit_id",-1))
		icons.append(world.selection_icon(1,unit,true) if unit>=0 else null)
		var decoder:=JSON.new();var color:Dictionary={}
		if decoder.parse(str(fact(row,"name_color","{}")))==OK and decoder.data is Dictionary:
			color=decoder.data
			for key in ["color","alternate"]:
				if color.get(key) is Array:
					for i in color[key].size():color[key][i]=int(color[key][i])
		names.append(color)
	set_process(is_visible_in_tree() and names.any(func(color):return int(color.get("effect",0))!=0))
func button_rect(index:int,which:int) -> Rect2:
	return Rect2(size.x-(88 if scrollbar.visible else 72)+which*32,(index-first)*36,24,36)
func _draw() -> void:
	if world==null or theme.default_font==null:return
	var width:=size.x-(32 if scrollbar.visible else 16)
	for index in range(first,mini(rows.size(),first+capacity())):
		var row:Dictionary=rows[index];var top:=Vector2(8,(index-first)*36)
		patch(art.texture("BUTTON_RECTANGLE"),top,int(width/8))
		var active:=int(fact(row,"unit_id",-1))>=0
		if active:
			patch(picture.texture(false),top,5)
			if icons[index]!=null:draw_texture_rect(icons[index],Rect2(top+Vector2(2,2),Vector2(32,32)),false)
		var columns:=maxi(0,int(width/8)-(14 if active else 7))
		var caption:=str(row.get("name",""))
		if caption.length()>=columns:caption=caption.left(maxi(0,columns-4))+"..." if columns>4 else caption.left(maxi(0,columns-1))
		var color:=NameColor.choose(names[index],Time.get_ticks_msec(),randi_range(0,1))
		var palette:=15 if color.is_empty() else int(color[0])+8*int(color[2])
		if not color.is_empty() and int(color[1])!=0:draw_rect(Rect2(top+Vector2(56,12),Vector2(caption.length()*8,12)),NativeText.colors[int(color[1])])
		theme.default_font.draw_string(get_canvas_item(),top+Vector2(56,24),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[palette])
		theme.default_font.draw_string(get_canvas_item(),top+Vector2(56,36),str(fact(row,"native_description","")),HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[clampi(int(fact(row,"description_color",15)),0,15)])
		if active:
			for which in 2:
				var texture:Texture2D=art.texture("STOCKS_RECENTER" if which==0 else "STOCKS_VIEW_ITEM")
				if texture!=null:draw_texture_rect(texture,button_rect(index,which),false)
func _gui_input(event:InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(capacity() if event.shift_pressed else 1));accept_event();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var index:=first+floori(event.position.y/36)
	if index<first or index>=mini(rows.size(),first+capacity()):return
	var row:Dictionary=rows[index];var unit:=int(fact(row,"unit_id",-1))
	if unit<0:return
	if button_rect(index,1).has_point(event.position):
		accept_event();inspect_relative_requested.emit(Vector3i(int(fact(row,"x",-1)),int(fact(row,"y",-1)),int(fact(row,"z",-1))),unit)
	elif button_rect(index,0).has_point(event.position):
		accept_event();focus_requested.emit(Vector3i(int(fact(row,"x",-1)),int(fact(row,"y",-1)),int(fact(row,"z",-1))))

func _process(_delta:float) -> void:queue_redraw()
func _notification(what:int) -> void:
	if what==NOTIFICATION_VISIBILITY_CHANGED:set_process(is_visible_in_tree() and names.any(func(color):return int(color.get("effect",0))!=0))

func hover_kind(point:Vector2) -> String:
	if not allowed():return ""
	var index:=first+floori(point.y/36)
	if index<first or index>=mini(rows.size(),first+capacity()) or int(fact(rows[index],"unit_id",-1))<0:return ""
	if button_rect(index,0).has_point(point):return "relations_recenter"
	if button_rect(index,1).has_point(point):return "inventory_creature"
	return ""
