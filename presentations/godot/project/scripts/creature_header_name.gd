extends Control
const NativeText = preload("res://scripts/native_creature_text.gd")
const NameColor = preload("res://scripts/native_name_color.gd")
var description: Dictionary = {}
var lines: Array[Label] = []

# Native15b93f..15bbd3: strict width comparison, split above the normal
# name row, and shorten each split string to width-1 with three dots.
static func fit(text: String, columns: int) -> String:
	if text.length()<columns: return text
	var count:=maxi(0,columns-1)
	return text.left(count-3)+"..." if count>3 else text.left(count)

func configure(facts: Dictionary, columns: int):
	description={"effect":int(facts.get("effect",-1)),
		"color":[int(facts.get("foreground",-1)),int(facts.get("background",-1)),int(facts.get("bright",-1))],
		"alternate":[int(facts.get("alternate_foreground",-1)),int(facts.get("alternate_background",-1)),int(facts.get("alternate_bright",-1))]}
	var combined:=str(facts.get("combined",""))
	if combined.length()<columns: add_line(combined,12,columns)
	else:
		add_line(fit(str(facts.get("name","")),columns),0,columns)
		add_line(fit(str(facts.get("profession","")),columns),12,columns)
	apply_time(Time.get_ticks_msec())
	set_process(is_visible_in_tree() and int(description.effect)!=0)

func add_line(text: String, y: int, columns: int):
	var label:=Label.new()
	label.text=text;label.position=Vector2(0,y);label.size=Vector2(columns*8,12)
	label.clip_text=true;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",12)
	var background:=ColorRect.new();background.name="GlyphBackground"
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE;background.show_behind_parent=true
	background.size=Vector2(text.length()*8,12)
	label.add_child(background);add_child(label);lines.append(label)

func apply_time(milliseconds: int, fire_choice: int = -1):
	var color:=NameColor.choose(description,milliseconds,randi_range(0,1) if fire_choice<0 else fire_choice)
	if color.is_empty(): return
	for label in lines:
		label.add_theme_color_override("font_color",NativeText.colors[color[0]+8*color[2]])
		var background:=label.get_node("GlyphBackground") as ColorRect
		background.visible=color[1]!=0;background.color=NativeText.colors[color[1]]

func _process(_delta: float): apply_time(Time.get_ticks_msec())
func _notification(what: int):
	if what==NOTIFICATION_VISIBILITY_CHANGED: set_process(is_visible_in_tree() and int(description.get("effect",0))!=0)
