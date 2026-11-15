extends SceneTree
const Header=preload("res://scripts/building_header_state.gd")
func _initialize() -> void:
	var failed:=false
	for type in [18,15]:
		for status in [-1,0,1,2,3,4]:
			var value={"type":type}
			if status>=0:value.well={"status":status}
			var expected: bool=(status in [0,1,2,3]) if type==18 else status==-1
			if Header.valid_well(value)!=expected:failed=true
	for body in [{"status":true},{"status":0,"extra":0},{},0]:
		if Header.valid_well({"type":18,"well":body}):failed=true
	if failed:push_error("Well contract validation failed")
	else:print("WELL_CONTRACT_PASS")
	quit(1 if failed else 0)
