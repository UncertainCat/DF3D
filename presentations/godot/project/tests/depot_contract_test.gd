extends SceneTree
const Header=preload("res://scripts/building_header_state.gd")
func _initialize() -> void:
	var failed:=false
	var absent={"requested":false,"anyone":false,"goods_available":false,"trade_available":false,"awaiting_items":0,"worker_id":-1,"broker_id":-1,"broker_name":"","activity":"","foreground":7,"background":0,"bright":false,"accessible":false}
	if not Header.valid_depot({"type":6,"depot":absent}):failed=true
	if Header.valid_depot({"type":6}) or Header.valid_depot({"type":15,"depot":absent}):failed=true
	for change in [{"trade_available":true},{"worker_id":-2},{"awaiting_items":-1},{"broker_id":1},{"activity":"Drink"},{"foreground":8},{"requested":1}]:
		var body: Dictionary=absent.duplicate();body.merge(change,true)
		if Header.valid_depot({"type":6,"depot":body}):failed=true
	var assigned: Dictionary=absent.duplicate()
	assigned.merge({"broker_id":988,"broker_name":"Broker","activity":"Drink","foreground":3,"bright":true,"accessible":true},true)
	if not Header.valid_depot({"type":6,"depot":assigned}):failed=true
	if failed:push_error("Depot contract validation failed")
	else:print("DEPOT_CONTRACT_PASS")
	quit(1 if failed else 0)
