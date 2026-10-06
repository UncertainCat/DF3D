extends RefCounted
# Selection-owned view of service-owned requests. Closing never cancels/replays
# a sent mutation. Explicit desired cancellation is distinct from removal.
const Contract = preload("res://scripts/management_contract.gd")
signal changed
var service
var building_id := -1
var ticket := 0
var state := {}
var uncertain := false

func select(id: int) -> void:
	if ticket != 0: service.detach(ticket)
	ticket = 0; building_id = id; state = {}; uncertain = false
	if id >= 0 and service != null: refresh()

func refresh() -> void:
	if building_id < 0 or service == null or ticket != 0 or uncertain: return
	_send({"action":Contract.ManagementAction.Inspect,"building_id":building_id})

func available() -> bool:
	return building_id >= 0 and ticket == 0 and not uncertain and int(state.get("status",-1)) == Contract.ManagementStatus.Ok and int(state.get("building_id",-1)) == building_id and not str(state.get("construction",{}).get("building_key","")).is_empty() and state.construction.building_key not in ["Stockpile","Civzone"]

func removing() -> bool: return bool(state.get("removing",false))

func act() -> void:
	if not available(): return
	_send({"action":Contract.ManagementAction.Remove,"building_id":building_id,
		"definition":state.construction.building_key,"cancel_removal":removing()})

func _send(request: Dictionary) -> void:
	var target := building_id
	ticket = service.submit("construction",request,func(received: int, result: Dictionary, _request: Dictionary):
		if received != ticket or target != building_id: return
		ticket = 0
		uncertain = result.get("outcome","") == "unknown"
		state = result
		changed.emit())
	changed.emit()
