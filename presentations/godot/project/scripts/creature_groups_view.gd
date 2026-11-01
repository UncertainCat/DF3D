extends "res://scripts/creature_items_view.gd"
# Native Groups renderer 178f51: semantic captions arrive from the bridge.
# Groups have no item portraits or item navigation targets.
func present(records:Array) -> void:
	rows=records;icons.clear();layout()

func clipped(value:String,columns:int) -> String:
	if value.length()<columns:return value
	return value.left(maxi(0,columns-4))+"..." if columns>4 else value.left(maxi(0,columns-1))

func _draw() -> void:
	if world==null or theme.default_font==null:return
	var width:=size.x-(32 if scrollbar.visible else 16)
	if rows.is_empty():
		# Native literal1600320, white text one line below the body origin.
		theme.default_font.draw_string(get_canvas_item(),Vector2(8,24),"No groups",HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[15])
	var texture:Texture2D=art.texture("BUTTON_RECTANGLE")
	for index in range(first,mini(rows.size(),first+capacity())):
		var row:Dictionary=rows[index];var top:=Vector2(8,(index-first)*36)
		# Native17915f begins at left+1: the first text cell has no patch.
		if texture!=null:
			for y in 3:
				for x in range(1,int(width/8)):
					draw_texture_rect_region(texture,Rect2(top+Vector2(x*8,y*12),Vector2(8,12)),Rect2(16 if x==int(width/8)-1 else 8,y*12,8,12))
		var category:=str(fact(row,"native_type",""))
		var caption:=clipped(str(row.get("name","")),int(width/8)-3)
		var role:=clipped(str(fact(row,"native_role","")),int(width/8)-3)
		theme.default_font.draw_string(get_canvas_item(),top+Vector2(0,24),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[11])
		theme.default_font.draw_string(get_canvas_item(),top+Vector2(width-category.length()*8,24),category,HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[14])
		theme.default_font.draw_string(get_canvas_item(),top+Vector2(0,36),role,HORIZONTAL_ALIGNMENT_LEFT,-1,12,NativeText.colors[15])

func hover_kind(_point:Vector2) -> String:return ""

func _gui_input(event:InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.move_to(first+(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1)*(capacity() if event.shift_pressed else 1))
		accept_event()
