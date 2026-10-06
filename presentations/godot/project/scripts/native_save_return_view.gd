extends "res://scripts/native_options_view.gd"
# Native empty, single-destination and duplicate-timeline catalog captures.
# IDs are supplied by the session catalog; never emit a native widget index.
signal destination_requested(id: String)
var destination_ids:Array[String]=[]
var detail_colors:Dictionary={"LGREEN":Color8(19,253,101),"LGRAY":Color8(192,192,192),"LRED":Color8(255,113,17),"YELLOW":Color8(255,225,17)}
func _init() -> void:
	header_text = ""
	set_destinations([])

func configure(source) -> void:
	super.configure(source)
	var palette:=FileAccess.get_file_as_string(source.assets_root().path_join("data/init/colors.txt"))
	for token in detail_colors:
		var channels:Array=[]
		for channel in ["R","G","B"]:
			var marker:String="["+token+"_"+channel+":"
			var start:=palette.find(marker)
			if start<0:return
			channels.append(float(palette.substr(start+marker.length()).get_slice("]",0))/255.0)
		detail_colors[token]=Color(channels[0],channels[1],channels[2])

func set_destinations(destinations:Array) -> bool:
	var ids:Array[String]=[]
	for destination in destinations:
		if not destination is Dictionary or not destination.get("id") is String or not destination.get("folder") is String:return false
		if destination.id.is_empty() or destination.folder.is_empty() or destination.id in ids:return false
		ids.append(destination.id)
	entries = [
		["SAVE_TO_NEW_FOLDER_NEW_TIMELINE", "Save to new timeline", 21],
		["SAVE_TO_NEW_FOLDER_EXISTING_TIMELINE", "Save to new folder (same timeline)", 14],
		["RETURN", "Return to game", 24],
	]
	if not destinations.is_empty():
		entries[0].append_array(["Do this if you want to keep the old save.",detail_colors.LGRAY])
		entries[1].append_array(["May interfere with existing saves.",detail_colors.LRED])
	var folders:Array=[]
	for destination in destinations:
		var label:String="Save to this timeline" if destinations.size()==1 else "Save to timeline folder: "+destination.folder
		folders.append(["SAVE_TO_EXISTING_FOLDER",label,floori((63-label.length())/2.0),"Recommended!" if destinations.size()==1 else "Multiple copies of the timeline found.",detail_colors.LGREEN if destinations.size()==1 else detail_colors.YELLOW])
	entries=folders+entries
	destination_ids=ids
	layout_reference();queue_redraw()
	return true

func _gui_input(event:InputEvent) -> void:
	if accepts_input() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for index in destination_ids.size():
			if Rect2(72,48+index*36,360,36).has_point(event.position):
				accept_event();destination_requested.emit(destination_ids[index]);return
	super._gui_input(event)
