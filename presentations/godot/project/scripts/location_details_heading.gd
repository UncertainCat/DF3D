extends Control
# Native210852/214045 name/type and affiliation rows. Full Details controls and
# value artwork remain unfinished; this component does not expose the route.
const Format=preload("res://scripts/location_details_format.gd")
const TEMPLE_TIERS=["Shrine","Temple","Temple complex"]
const GUILD_TIERS=["meeting place","guildhall","grand guildhall"]
var art=preload("res://scripts/original_ui.gd").new()
var rows: Array=[]
const GRAY:=Color8(192,192,192)
const YELLOW:=Color8(255,225,17)
const CYAN:=Color8(18,254,207)
const MAGENTA:=Color8(232,17,255)

func configure(source) -> void:
	art.configure(source);theme=art.theme
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;mouse_filter=Control.MOUSE_FILTER_IGNORE

func layout(view: Vector2) -> void:
	position=Vector2(432,60+fposmod(view.y,12)*0.5)

func display(details: Dictionary) -> void:
	rows=content(details);queue_redraw()

static func content(details: Dictionary) -> Array:
	if not Format.int32_value(details.get("kind")) or details.kind not in [1,2,3,4,5] or typeof(details.get("name"))!=TYPE_STRING:return []
	var first:=5 if details.kind in [2,4] else 6
	var result: Array=[]
	if not details.name.is_empty():result.append({"x":54,"y":first,"text":str(details.name).left(57)+"..." if str(details.name).length()>60 else details.name})
	var title: String={1:"Tavern",3:"Library",5:"Hospital"}.get(int(details.kind),"")
	if details.kind in [2,4]:
		if not Format.int32_value(details.get("tier")):return result
		var tier: int=details.tier
		if details.kind==2:
			title=TEMPLE_TIERS[tier] if tier>=0 and tier<TEMPLE_TIERS.size() else ""
		else:
			if not Format.int32_value(details.get("profession")):return result
			var mapping: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://panels/area_location_labels.json"))
			for row in mapping.guild_professions:
				if int(row.profession)==details.profession:
					title=str(row.label)
					if tier>=0 and tier<GUILD_TIERS.size():title+=" "+GUILD_TIERS[tier]
					break
	if not title.is_empty():result.append({"x":54,"y":first+1,"text":title})
	result.append_array(affiliation_rows(details))
	return result

static func affiliation_rows(details: Dictionary) -> Array:
	if details.get("kind") not in [2,4] or typeof(details.get("affiliation"))!=TYPE_DICTIONARY:return []
	var a: Dictionary=details.affiliation
	for key in ["kind","id","count","workers"]:
		if not Format.int32_value(a.get(key)):return []
	if typeof(a.get("name"))!=TYPE_STRING or a.count<0:return []
	var text: String="";var color:=YELLOW
	var result: Array=[]
	if details.kind==2:
		if a.kind==1:
			if a.id!=-1 or a.count!=0 or a.name!="" or a.workers!=-1:return []
			text="No particular deity";color=GRAY
		elif a.kind in [2,3] and a.id>=0 and a.workers==-1:
			text=("Dedicated to " if a.kind==2 else "")+str(a.name)
			color=CYAN if a.kind==2 else YELLOW
		else:return []
		result.append({"x":92,"y":14,"text":"No worshippers" if a.count==0 else str(a.count)+(" worshipper" if a.count==1 else " worshippers"),"color":GRAY if a.count==0 else Color.WHITE})
	else:
		if a.kind!=4 or a.id<-1 or a.workers<0:return []
		if a.id==-1:
			if a.name!="" or a.count!=0:return []
			text="No established guild, "+("no workers" if a.workers==0 else str(a.workers)+(" worker" if a.workers==1 else " workers"));color=MAGENTA
		else:text=str(a.name)+", "+("no members" if a.count==0 else str(a.count)+(" member" if a.count==1 else " members"))
	result.push_front({"x":54,"y":7,"text":text,"color":color})
	return result

func _draw() -> void:
	if theme==null or theme.default_font==null:return
	for row in rows:
		theme.default_font.draw_string(get_canvas_item(),Vector2((int(row.x)-54)*8,(int(row.y)-5)*12+12),str(row.text),HORIZONTAL_ALIGNMENT_LEFT,-1,12,row.get("color",Color.WHITE))
