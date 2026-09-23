extends SceneTree
# Standalone engine reproduction: no DF, extension, assets or application UI.
# Grow fallback-font atlases while the renderer consumes queued image updates.
var labels: Array[Label] = []
var next_code := 0x100
var frames := 0

func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for size in [13, 17, 24, 32]:
		var label := Label.new()
		label.position.y = labels.size() * 100
		label.add_theme_font_size_override("font_size", size)
		root.add_child(label)
		labels.append(label)

func _process(_delta: float) -> bool:
	var text := ""
	for i in 8:
		next_code += 1
		text += char(next_code)
	for label in labels:
		label.text = (label.text if label.text.length() < 400 else "") + text
	frames += 1
	if next_code > 0x2000:
		print("FONT_ATLAS_PROBE_DONE frames=", frames)
		quit()
	return false
