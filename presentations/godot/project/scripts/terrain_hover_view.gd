extends Control
# Native map hover: 61 columns attached beneath the top information bar.
# fixtures/hover/layout.json records native ordering, overflow and viewport placement.
var art=preload("res://scripts/original_ui.gd").new()
var entries: Array = []
var labels: Array[Label] = []
var visible_rows := 0

func configure(source) -> void:
	art.configure(source);theme=art.theme
	mouse_filter=Control.MOUSE_FILTER_IGNORE;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	size=Vector2(488,48)

func set_entries(value:Array) -> void:
	entries=value.duplicate(true)
	_refresh_labels()

func _refresh_labels() -> void:
	var count=mini(entries.size(),visible_rows)
	while labels.size()>count:
		var label=labels.pop_back();remove_child(label);label.queue_free()
	while labels.size()<count:
		var label=Label.new();label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size",12)
		label.autowrap_mode=TextServer.AUTOWRAP_OFF
		label.position=Vector2(16,24+labels.size()*12)
		add_child(label);labels.append(label)
	for i in count:
		var row:Dictionary=entries[i]
		labels[i].text=str(row.get("text",""))
		labels[i].add_theme_color_override("font_color",art.world.ui_palette_color(int(row.get("foreground",7))+(8 if row.get("bright",false) else 0)))
		var style=StyleBoxFlat.new();style.bg_color=art.world.ui_palette_color(int(row.get("background",0))) if int(row.get("background",0))!=0 else Color.TRANSPARENT
		labels[i].add_theme_stylebox_override("normal",style)

func layout(view:Vector2) -> void:
	position=Vector2(maxf(0,floorf(view.x/8)-98)*8+floorf(fposmod(view.x,8)*0.5),36+floorf(fposmod(view.y,12)*0.5))
	size.y=36+entries.size()*12
	var count=maxi(0,floori((view.y-floorf(fposmod(view.y,12)*0.5)-position.y-24)/12))
	if count!=visible_rows:
		visible_rows=count;_refresh_labels()
	queue_redraw()

func _draw() -> void:
	var frame:Texture2D=art.texture("HOVER_RECTANGLE")
	if frame==null:return
	var rows:=int(size.y/12)
	for y in mini(rows,visible_rows+2):
		for x in 61:
			var source:=Vector2(0 if x==0 else (16 if x==60 else 8),24 if y==0 or y==rows-1 else 12)
			if y==0 and (x==0 or x==60):
				var join:Texture2D=art.texture("HOVER_RECTANGLE_JOIN_W_S" if x==0 else "HOVER_RECTANGLE_JOIN_E_SE")
				if join!=null:draw_texture_rect(join,Rect2(x*8,0,8,12),false)
			else:draw_texture_rect_region(frame,Rect2(x*8,y*12,8,12),Rect2(source,Vector2(8,12)))
