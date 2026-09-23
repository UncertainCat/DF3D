extends RefCounted
# Installed files only. Discovery runs once on the audio worker, never on a
# combat frame. Keys preserve native folder/material/variant distinctions.
static func scan(install: String) -> Dictionary:
	var result := {"cues": {}, "announcements": {}}
	var root := install.path_join("data/sound")
	for folder in ["combat", "actions", "doors", "locomotion", "notifications", "ui"]:
		_walk(root.path_join("audio").path_join(folder), folder, result.cues)
	_walk(root.path_join("sounds"), "announcement", result.cues)
	var definition := install.path_join("data/vanilla/vanilla_music/objects/sound_standard.txt")
	if FileAccess.file_exists(definition):
		var sound := ""
		for line in FileAccess.get_file_as_string(definition).split("\n"):
			line = line.strip_edges()
			if line.begins_with("[FILE:DEFAULT_SOUND_"):
				sound = "announcement/" + line.trim_prefix("[FILE:DEFAULT_SOUND_").trim_suffix("]").to_lower()
			elif line.begins_with("[SOUND:"):
				sound = ""
			elif line.begins_with("[ANNOUNCEMENT:") and result.cues.has(sound):
				result.announcements[line.trim_prefix("[ANNOUNCEMENT:").trim_suffix("]")] = sound
	return result

static func _walk(directory: String, prefix: String, cues: Dictionary) -> void:
	var dir := DirAccess.open(directory)
	if dir == null: return
	var files := dir.get_files()
	files.sort()
	for file in files:
		if file.get_extension().to_lower() != "ogg": continue
		var stem := file.get_basename().to_lower()
		# Native variants have numeric suffixes, e.g. hit-001, door-002.
		var dash := stem.rfind("-")
		if dash >= 0 and stem.substr(dash + 1).is_valid_int(): stem = stem.left(dash)
		var key := prefix + "/" + stem
		if not cues.has(key): cues[key] = []
		cues[key].append(directory.path_join(file))
	for child in dir.get_directories():
		_walk(directory.path_join(child), prefix + "/" + child, cues)
