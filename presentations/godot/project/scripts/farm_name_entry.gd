extends "res://scripts/area_name_entry.gd"
signal caption_changed
# Local draft rendering only. Native semantic receipts remain name authority.
# DF53.16 renderer1804f1 appends the blink cursor then formats via52d650.
# The formatter skips bracketed text and leading spaces/quotes, capitalizes
# one eligible CP437 byte and stops. It is not Unicode title case.
const UPPER={129:154,130:144,132:142,134:143,135:128,145:146,148:153,164:165}

func _init() -> void:byte_limit=30

static func caption(draft: String) -> String:
	var depth:=0
	var initial:=true
	for index in draft.length():
		var character:=draft.unicode_at(index)
		if character==91:depth+=1;continue
		if character==93:depth-=1;continue
		if depth>0:continue
		if not initial:
			var previous:=draft.unicode_at(index-1)
			var eligible:=previous in [32,34]
			if previous==39 and index>=2 and draft.unicode_at(index-2) in [32,44]:eligible=true
			if not eligible:continue
		var replacement:=character
		if character>=97 and character<=122:replacement=character-32
		else:
			var high:=Art.CP437_HIGH.find(character)
			if high>=0 and UPPER.has(high+128):replacement=Art.CP437_HIGH[UPPER[high+128]-128]
		if replacement!=character:return draft.left(index)+String.chr(replacement)+draft.substr(index+1)
		if character in [32,34]:initial=false
		else:return draft
	return draft

func _refresh() -> void:
	text=caption(value+("_" if cursor_visible else ""))
	caption_changed.emit()
