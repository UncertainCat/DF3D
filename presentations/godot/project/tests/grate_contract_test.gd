extends SceneTree
const Item=preload("res://scripts/item_sheet_state.gd")
func _initialize() -> void:
	var failed:=false
	var look={"material_token":"INORGANIC:DOLOMITE","subtype_raw":"","color_token":"","stack":1,"flags":0}
	for wall in [false,true]:
		for opened in [false,true]:
			look.grate={"wall":wall,"open":opened}
			if not Item._valid_appearance(look,79) or Item._valid_appearance(look,7):failed=true
	for malformed in [{"wall":true},{"wall":true,"open":1},{"wall":true,"open":false,"extra":false}]:
		look.grate=malformed
		if Item._valid_appearance(look,79):failed=true
	look.erase("grate")
	if not Item._valid_appearance(look,79):failed=true
	if failed:push_error("Grate contract validation failed")
	else:print("GRATE_CONTRACT_PASS")
	quit(1 if failed else 0)
