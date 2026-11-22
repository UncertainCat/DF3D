extends RefCounted
# Native133629 main-help text, wrapping and shortcuts. Keys are DF hover IDs.
const ENTRIES={
	247:{"lines":["Assign a trainer to","this creature."],"key":KEY_T,"shortcut":"Ctrl+t"},
	249:{"lines":["Toggle whether this","creature will receive","war training.  War","animals have more","lethal attacks."],"key":KEY_W,"shortcut":"Ctrl+w"},
	250:{"lines":["Toggle whether this","creature will receive","hunting training.","Hunting animals can","move stealthfully","during hunts."],"key":KEY_H,"shortcut":"Ctrl+h"},
	251:{"lines":["Toggle whether this","creature is available","as a pet for any","interested citizen or","resident."],"key":KEY_E,"shortcut":"Ctrl+e"},
	270:{"lines":["Toggle whether this","creature will be","slaughtered at a","butcher's shop when the","opportunity arises."],"key":KEY_B,"shortcut":"Ctrl+b"},
	271:{"lines":["Toggle whether this","creature will be gelded","at a farmer's workshop","when the opportunity","arises."],"key":KEY_G,"shortcut":"Ctrl+g"}}
static func observed(control: Dictionary) -> int:
	var id:=int(control.get("hover_help",-1))
	return id if control.get("help_observed",false) and ENTRIES.has(id) else -1
