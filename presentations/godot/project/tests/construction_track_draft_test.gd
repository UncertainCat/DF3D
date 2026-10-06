extends SceneTree
const Draft=preload("res://scripts/construction_draft.gd")
var failures:=0
func check(value: bool,label: String) -> void:
	if not value: failures+=1;push_error(label)
func preview(path: Array) -> Dictionary:
	return {"status":2,"placement_valid":true,"construction":{"filters":[{"index":0,"quantity":path.size()}],"connected_track":{"status":0,"path":path}}}
func _initialize() -> void:
	var draft=Draft.new()
	var definition={"key":"Construction:Track","supported":true,"orientations":1,"area_mode":3,"max_width":31,"max_height":31,"max_depth":1,
		"footprints":[{"direction":0,"width":1,"height":1,"center_x":0,"center_y":0}]}
	check(draft.choose(definition),"fixture Track definition accepted")
	var first:=Vector3i(100,80,4);var last:=Vector3i(2,3,6)
	check(draft.set_site(first,last),"Track uses endpoint contract, not rectangle volume cap")
	check(draft.origin==first and draft.track_destination==last and draft.dimensions==Vector3i.ONE,"endpoint order and singleton wire dimensions retained")
	for action in [1,2,63]:
		var query: Dictionary=draft.request(action)
		check(query.origin==first and query.connected_track_destination==last and query.width==1 and query.height==1 and query.depth==1 and query.direction==0,"ordered intent through each Track action")
	check(not draft.request(0).has("connected_track_destination"),"Catalog has no Track intent")
	var path: Array=[first,Vector3i(99,80,4),last]
	check(draft.accept_preview(preview(path)),"complete bridge path accepted")
	path[1]=Vector3i.ZERO
	check(draft.track_path[1]==Vector3i(99,80,4),"draft owns copied path")
	var old_query: Dictionary=draft.material_request(0)
	check(old_query.connected_track_destination==last,"material request retains direction")
	var newer:=Vector3i(98,80,4)
	check(draft.set_site(first,newer) and draft.track_path.is_empty() and not draft.preview_valid,"endpoint change clears path and readiness")
	check(draft.accept_preview(preview([first,Vector3i(99,80,4),newer])),"replacement path accepted")
	var page={"status":2,"construction":{"filter":0,"build_phase":0,"list_revision":12,"materials":[],"total":0}}
	check(draft.accept_materials(page,old_query)=="obsolete" and draft.preview_valid,"late material reply from different destination cannot replace current draft")
	var current: Dictionary=draft.material_request(0)
	check(draft.accept_materials(page,current)=="ready","matching endpoint material reply accepted")
	var paged: Dictionary=draft.material_request(0,128)
	check(paged.connected_track_destination==newer and paged.expected_list_revision==12,"page request binds endpoint and revision")
	check(draft.set_site(newer,first) and draft.origin==newer and draft.track_destination==first,"reversing endpoints does not normalize order")
	for bad_path in [[first,newer],[newer,newer,first],[newer,Vector3i(-1,0,0),first],[newer,17,first],[]]:
		check(not draft.accept_preview(preview(bad_path)) and draft.track_path.is_empty() and not draft.preview_valid,"invalid/reversed/duplicate preview cannot become ready")
	check(not draft.set_site(first,first),"coincident endpoints refused")
	check(draft.set_site(first,newer) and draft.accept_preview(preview([first,Vector3i(99,80,4),newer])),"valid path restored for exact submission")
	var row={"item_type":0,"item_subtype":-1,"mat_type":0,"mat_index":1,"count":3,"candidates":[
		{"id":1,"name":"fixture item","distance":1},{"id":2,"name":"fixture item","distance":2},{"id":3,"name":"fixture item","distance":3}]}
	page.construction.materials=[row]
	check(draft.accept_materials(page,draft.material_request(0))=="ready" and draft.select_group(0,0,3),"exact snapshot selected")
	var place: Dictionary=draft.place_request()
	check(not place.is_empty() and place.origin==first and place.connected_track_destination==newer and place.selections[0].item_ids==[1,2,3],"validated Track emits ordered endpoint and exact IDs")
	place.selections[0].item_ids.clear()
	check(draft.selected_ids(0,row)==[1,2,3],"Place owns copied identities")
	draft.selections[0].erase("item_ids")
	check(draft.place_request().is_empty(),"Track cannot substitute aggregate intent")

	draft.clear()
	check(draft.track_destination==Vector3i(-1,-1,-1) and draft.track_path.is_empty(),"clear releases all Track state")
	definition.supported=false
	check(not draft.choose(definition),"production disabled flag remains authoritative")
	print("CONSTRUCTION_TRACK_DRAFT ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
