extends Control
# Native215411: CP437 glyph15 is the currency mark; never substitute authored art.
const Format=preload("res://scripts/location_details_format.gd")
const CYAN:=Color8(18,254,207)
const CURRENCY="☼"
const TITLES={2:["Shrine","Temple","Temple Complex"],4:["Meeting place","Guildhall","Grand Guildhall"]}
var art=preload("res://scripts/original_ui.gd").new()
var text: String=""

func configure(source) -> void:
	art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_IGNORE

func layout(view: Vector2) -> void:
	position=Vector2(384,168+fposmod(view.y,12)*0.5)

func display(details: Dictionary) -> void:
	text=content(details);queue_redraw()

static func content(details: Dictionary) -> String:
	if not Format.int32_value(details.get("kind")) or not TITLES.has(details.kind) or not Format.int32_value(details.get("tier")):return ""
	var tier: int=details.tier
	if tier<0 or tier>2:return ""
	var value:=Format.appraised_value(details.get("value"),details.get("appraisal"))
	if value.is_empty():return ""
	var result: String=TITLES[details.kind][tier]+", "+str(value.text)+CURRENCY+str(value.after_currency)
	if tier<2:result+=" (next at "+str(2000 if tier==0 else 10000)+CURRENCY+")"
	return result

func _draw() -> void:
	if theme==null or theme.default_font==null:return
	theme.default_font.draw_string(get_canvas_item(),Vector2(0,12),text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,CYAN)
