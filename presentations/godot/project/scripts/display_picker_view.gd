extends "res://scripts/stocks_view.gd"
# Shared native inventory chrome, category rows, item artwork and paging.
# Display selection stays local; no Stocks flag action is exposed here.
func configure_display(source,model) -> void:
	configure_stocks(source,model);search.byte_limit=1024
	search.placeholder_ink=Color8(160,160,160)
	for bar in [scrollbar,item_scrollbar]:bar.use_classic_art=false
func checkbox_rect(index: int) -> Rect2:
	return Rect2(item_canvas.size.x-40,index*36-(item_scrollbar.first%3)*12,24,36)
func help_at(_point: Vector2) -> String:return ""
func _draw_items() -> void:
	for index in page.size():
		var entry: Dictionary=page[index];var y: int=index*36-(item_scrollbar.first%3)*12
		if entry.has("group"):
			_patch(item_canvas,"BUTTON_CATEGORY_RECTANGLE",Vector2(0,y),int(item_canvas.size.x/8))
			_text(item_canvas,entry.group.caption,Vector2(16,y+24))
		else:
			_patch(item_canvas,"BUTTON_RECTANGLE",Vector2(0,y),int(item_canvas.size.x/8))
			_patch(item_canvas,"",Vector2(0,y),5,picture.texture(false))
			var row: Dictionary=state.items.get(entry.id,{})
			if row.is_empty():continue
			var icon: Texture2D=icons.get(row.id,{}).get("texture")
			if icon!=null and y>=0 and y+36<=item_canvas.size.y:item_canvas.draw_texture_rect(icon,Rect2(2,y+2,32,32),false)
			_text(item_canvas,row.caption,Vector2(56,y+24))
			var texture: Texture2D=art.texture("ASSIGN_TRADE_SELECTED" if state.selected.has(row.id) else "ASSIGN_TRADE_NOT_SELECTED")
			if texture!=null:item_canvas.draw_texture_rect(texture,checkbox_rect(index),false)
func _gui_input(event: InputEvent) -> void:
	if not allowed() or not event is InputEventMouseButton or not event.pressed:return
	accept_event()
	if event.button_index!=MOUSE_BUTTON_LEFT or not ready():return
	if Rect2(category_canvas.position,category_canvas.size).has_point(event.position):
		var index: int=int((event.position.y-category_canvas.position.y)/36)+scrollbar.first
		var rows: Array=state.visible_categories()
		if index<rows.size():state.select_category(int(rows[index].type))
		return
	var point: Vector2=event.position-item_canvas.position
	if not Rect2(Vector2.ZERO,item_canvas.size).has_point(point):return
	var index:=int((point.y+(item_scrollbar.first%3)*12)/36)
	if index>=page.size():return
	var entry: Dictionary=page[index]
	# Native Display group and item captions do not toggle selection/expansion.
	if not entry.has("group") and checkbox_rect(index).has_point(point):state.toggle_item(entry.id)
