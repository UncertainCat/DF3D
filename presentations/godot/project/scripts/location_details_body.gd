extends Control
# Shared native body rows. Full heading, staff and editing controls are owned by
# the unfinished Details view; this component does not expose a partial route.
const Format = preload("res://scripts/location_details_format.gd")
const GRAY := Color8(192,192,192)
const WHITE := Color8(255,255,255)
const YELLOW := Color8(255,225,17)
const LIGHT_RED := Color8(255,113,17)
var art = preload("res://scripts/original_ui.gd").new()
var rows: Array = []

func configure(source) -> void:
	art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	custom_minimum_size=Vector2(576,588)

func display(details: Dictionary) -> void:
	rows=content(details);queue_redraw()

func layout(view: Vector2) -> void:
	# Native 8x12 cell grid is vertically centered in the viewport.
	position=Vector2(384,60+fposmod(view.y,12)*0.5)

func _draw() -> void:
	var font: Font=theme.default_font if theme != null else null
	if font == null: return
	for row in rows:
		var point=Vector2((int(row.x)-48)*8,(int(row.y)-5)*12+12)
		font.draw_string(get_canvas_item(),point,str(row.caption),HORIZONTAL_ALIGNMENT_LEFT,-1,12,GRAY)
		point.x+=str(row.caption).length()*8
		font.draw_string(get_canvas_item(),point,str(row.value),HORIZONTAL_ALIGNMENT_LEFT,-1,12,row.get("color",WHITE))

static func add(rows: Array, x: int, y: int, caption: String, value: Variant, dance := false) -> void:
	if value == null: return
	rows.append({"x":x,"y":y,"caption":caption,"value":str(value),"dance":dance})

static func facility(rows: Array, d: Dictionary, y: int, key: String, caption: String, x := 48) -> void:
	var value=d.get("facilities",{}).get(key)
	if not Format.int32_value(value) or value<0: return
	add(rows,x,y,caption,value)

static func supply(rows: Array, d: Dictionary, y: int, kind: int, caption: String) -> void:
	for row in d.get("supplies",[]):
		if int(row.get("kind",-1)) != kind: continue
		var stored=Format.supply_quantity(row.get("stored"),kind,false)
		var desired=Format.supply_quantity(row.get("desired"),kind,true)
		if stored!=null and desired!=null: add(rows,49,y,caption,str(stored)+" ("+str(desired)+")")
		return

static func dance(rows: Array, d: Dictionary, y: int) -> void:
	var x=d.get("dance_floor_x");var z=d.get("dance_floor_y")
	if not Format.int32_value(x) or not Format.int32_value(z) or x<0 or z<0 or (x==0)!=(z==0): return
	add(rows,48,y,"Dance floor in common area: ","None" if x==0 else str(x)+"x"+str(z),true)
	# Native210250: absence is light red, either dimension below5 is yellow.
	rows[-1].color=LIGHT_RED if x==0 else YELLOW if x<5 or z<5 else WHITE

static func content(d: Dictionary) -> Array:
	var rows: Array=[]
	match int(d.get("kind",0)):
		1:
			facility(rows,d,14,"chests","Chests in common area: ")
			supply(rows,d,17,0,"Goblets (Desired): ")
			supply(rows,d,20,1,"Stored Instruments (Desired): ")
			dance(rows,d,23)
			var f: Dictionary=d.get("facilities",{})
			if Format.int32_value(f.get("rented_rooms")) and Format.int32_value(f.get("rooms")) and int(f.rented_rooms)>=0 and int(f.rooms)>=0:
				add(rows,88,23,"Rented rooms (Total): ",str(f.rented_rooms)+" ("+str(f.rooms)+")")
		2:
			facility(rows,d,20,"chests","Chests in common area: ")
			supply(rows,d,23,1,"Stored Instruments (Desired): ")
			dance(rows,d,26)
		3:
			facility(rows,d,14,"bookcases","Bookcases: ")
			facility(rows,d,14,"tables","Tables: ",68)
			facility(rows,d,14,"chairs","Chairs: ",88)
			var written=d.get("written_objects")
			if Format.int32_value(written) and written>=0: add(rows,48,17,"Written objects (incl. copies): ",written)
			if Format.int32_value(d.get("desired_copies")): add(rows,49,20,"Total number of each to scribe: ",d.desired_copies)
			facility(rows,d,23,"chests","Chests in common area: ")
			supply(rows,d,26,2,"Writing Material (Desired): ")
		5:
			facility(rows,d,13,"beds","Beds in common area: ")
			facility(rows,d,14,"tables","Tables in common area: ")
			facility(rows,d,15,"traction_benches","Traction benches in common area: ")
			facility(rows,d,17,"chests","Chests in common area: ")
			var captions=["Thread","Cloth","Splints","Crutches","Powder for casts","Buckets","Soap"]
			for i in 7: supply(rows,d,20+i*3,[4,5,3,6,7,8,9][i],captions[i]+" (Desired): ")
	return rows
