extends Control
# Native renderer3f7dda..3f92fe; recorded cells in native_petition_tracker.json.
# This view consumes semantic snapshots only. Visibility/input belong to its host.
const HEADINGS={5:{1:"Build a temple",2:"Build a temple complex"},10:{1:"Build a guildhall",2:"Build a grand guildhall"}}
var art=preload("res://scripts/original_ui.gd").new()
var lines: Array=[]

func configure(source) -> void:
	art.configure(source);theme=art.theme
	mouse_filter=Control.MOUSE_FILTER_IGNORE;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	size=Vector2(488,216);hide()

func layout(view: Vector2) -> void:
	position=Vector2((floori(view.x/8)-98)*8+floorf(fposmod(view.x,8)*0.5),36+floorf(fposmod(view.y,12)*0.5))

func display(snapshot: Dictionary) -> void:
	lines=content(snapshot);visible=not lines.is_empty();queue_redraw()

static func shortened(text: String) -> String:
	# Native bounds bytes in its CP437 string: 56 or more -> first52 + ellipsis.
	return text.substr(0,52)+"..." if text.length()>=56 else text

static func line(y: int, text: String, color: int) -> Dictionary:
	return {"y":y,"text":text,"color":color}

static func content(snapshot: Dictionary) -> Array:
	if snapshot.is_empty():return []
	var row: Dictionary=snapshot.row
	var facts: Dictionary=snapshot.details
	var result: Array=[line(5,"Accepted petition:",15)]
	var kind: int=row.entity_type
	if not HEADINGS.has(kind):return result
	var tier: int=row.tier
	result.append(line(7,HEADINGS[kind].get(tier,""),11))
	result.append(line(8,"for",7))
	result.append(line(9,shortened(str(row.applicant)+"."),14))
	result.append(line(11,"The associated zones must have enough value. ("+(str(int(facts.required_value)) if tier in [1,2] else "")+"☼)",15))
	if kind==5 and tier in [1,2]:
		result.append(line(12,"A priest must then be elevated." if tier==1 else "A high priest must then be elevated.",13))
	if facts.site_available:
		var y:=14 if kind==5 else 13
		var noun: String="temple" if kind==5 else "guildhall"
		if facts.location_id<0:
			result.append(line(y,"No "+noun+" location currently assigned to a zone.",12))
		else:
			var color:=10 if facts.tier_met else 14
			result.append(line(y,"Current "+("top " if facts.matching_locations>1 else "")+noun+" location:",color))
			result.append(line(y+1,str(facts.location_name)+", "+str(int(facts.location_value))+"☼",color))
	result.append(line(18,"Agreement date: "+str(row.date),7))
	return result

func _draw() -> void:
	if lines.is_empty():return
	var frame: Texture2D=art.texture("HOVER_RECTANGLE")
	if frame==null or theme.default_font==null:return
	for y in 18:
		for x in 61:
			var origin:=Vector2(0 if x==0 else (16 if x==60 else 8),24 if y==0 or y==17 else 12)
			if y==0 and x in [0,60]:
				var join: Texture2D=art.texture("HOVER_RECTANGLE_JOIN_W_S" if x==0 else "HOVER_RECTANGLE_JOIN_E_SE")
				if join!=null:draw_texture_rect(join,Rect2(x*8,0,8,12),false)
			else:draw_texture_rect_region(frame,Rect2(x*8,y*12,8,12),Rect2(origin,Vector2(8,12)))
	for entry in lines:
		theme.default_font.draw_string(get_canvas_item(),Vector2(16,(entry.y-2)*12),entry.text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,art.world.ui_palette_color(entry.color))
