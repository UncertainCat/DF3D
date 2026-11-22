extends RefCounted
# Native pet row columns and installed graphics (protected120107/094804).
# Presence and selected values are supplied by DF; this maps them to artwork.
const C=preload("res://scripts/management_contract.gd")
const COLUMNS={C.PetAction.Slaughter:936,C.PetAction.Adoption:960,C.PetAction.Gelding:984,C.PetAction.Trainer:656,C.PetAction.War:680,C.PetAction.Hunting:704}
static func controls(row: Dictionary,y: int) -> Array:
	var result: Array=[]
	for control: Dictionary in row.get("pet",{}).get("controls",[]):
		var action:=int(control.action)
		if not COLUMNS.has(action):continue
		var token: String
		match action:
			C.PetAction.Trainer:token="ASSIGN_TRAINER"
			C.PetAction.Adoption:token="AVAILABLE_AS_PET" if control.value else "UNAVAILABLE_AS_PET"
			_:
				var prefix: String={C.PetAction.Slaughter:"SLAUGHTER",C.PetAction.Gelding:"GELD",C.PetAction.War:"WAR_TRAINING",C.PetAction.Hunting:"HUNT_TRAINING"}[action]
				token=prefix+("_ACTIVE" if control.value else "_INACTIVE")
		result.append({"action":action,"rect":Rect2(COLUMNS[action],y,24,36),"token":"PETS_LIVESTOCK_"+token,"control":control})
	return result

static func training_captions(row: Dictionary,y: int) -> Array:
	var result: Array=[]
	for caption: Dictionary in row.get("pet",{}).get("training",[]):
		var value:=str(caption.text)
		# Native372433/37244e selects ellipses and24 columns. Widget14196e0
		# keeps21 single-byte glyphs and appends dots; UTF8 is decoded here.
		if value.is_empty():continue
		if value.length()>24:value=value.left(21)+"..."
		result.append({"text":value,"point":Vector2(368,y+36),"color":int(caption.foreground)+8*int(caption.bright)})
	return result
