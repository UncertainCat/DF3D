extends RefCounted
# Selection and receipt state only. DF discovers rooms and owns their full set.
# The controller must clear this state on session change; its action service
# supplies epoch/client identity and serializes Finish after any sent selection.
const Contract = preload("res://scripts/management_contract.gd")
const Op = Contract.AreaOperation
const Outcome = Contract.AreaRoomOutcome
var interaction_id := 0
static var _next_interaction := 1
var furniture := 0
var map_size := Vector2i.ZERO
var undo_token := 0
var pending: Dictionary = {}
var observed: Dictionary = {}
var stopped := false

func clear() -> void:
	interaction_id = 0; furniture = 0; map_size = Vector2i.ZERO
	undo_token = 0; pending = {}; observed = {}; stopped = false

func open(kind: int, bounds: Vector2i) -> bool:
	clear()
	if kind < 1 or kind > 4 or bounds.x < 1 or bounds.y < 1 or bounds.x > 32768 or bounds.y > 32768 or _next_interaction <= 0: return false
	interaction_id = _next_interaction
	# Never wrap and reuse an interaction identity, including across clear/open.
	_next_interaction = 0 if _next_interaction == 9223372036854775807 else _next_interaction + 1
	furniture = kind; map_size = bounds
	return true

func ready() -> bool:
	return interaction_id > 0 and not stopped and pending.is_empty()

func selection(first: Vector3i, last: Vector3i) -> Dictionary:
	if not ready() or first.z < 0 or first.z > 32767 or first.z != last.z: return {}
	var low := Vector2i(mini(first.x,last.x),mini(first.y,last.y))
	var high := Vector2i(maxi(first.x,last.x),maxi(first.y,last.y))
	if low.x < 0 or low.y < 0 or high.x >= map_size.x or high.y >= map_size.y: return {}
	# This rectangle selects furniture. It is not a painted footprint and must
	# not inherit per-room geometry, tile-count or reply-page limits.
	pending = {"action":Contract.ManagementAction.AreaCreate,"kind":1,"operation":Op.MultiCreate,
		"interaction_id":interaction_id,"room_furniture":furniture,
		"origin":Vector3i(low.x,low.y,first.z),"width":high.x-low.x+1,"height":high.y-low.y+1}
	return pending.duplicate(true)

func undo() -> Dictionary:
	if not ready(): return {}
	if undo_token <= 0:
		# Native Undo after an all-rejected selection clears its result panel.
		# There is no created set or deletion authority to send to the bridge.
		observed = {}; return {}
	pending = {"action":Contract.ManagementAction.AreaUpdate,"kind":1,"operation":Op.MultiUndo,
		"interaction_id":interaction_id,"undo_token":undo_token}
	return pending.duplicate(true)

func has_result() -> bool:
	return int(observed.get("operation",-1)) == Op.MultiCreate and int(observed.get("room_outcome",Outcome.None)) == Outcome.Completed and (int(observed.get("rooms_created",0)) > 0 or int(observed.get("rooms_in_use",0)) > 0 or int(observed.get("rooms_unenclosed",0)) > 0)

func finish() -> Dictionary:
	if interaction_id <= 0: return {}
	var request := {"action":Contract.ManagementAction.AreaUpdate,"kind":1,"operation":Op.MultiFinish,
		"interaction_id":interaction_id}
	clear() # retire locally before any late result can restore authority
	return request

func stop() -> void:
	stopped = true; pending = {}; undo_token = 0; observed = {}

func accept(result: Dictionary, sent: Dictionary) -> bool:
	if pending.is_empty() or stopped or sent != pending: return false
	if str(result.get("outcome","")) == "not_sent":
		pending = {} # no native action occurred; the preceding token still applies
		return true
	if str(result.get("outcome","")) == "unknown":
		stop(); return false
	var page: Dictionary = result.get("area",{})
	var operation := int(pending.operation)
	if int(result.get("action",-1)) != int(pending.action) or int(page.get("interaction_id",0)) != interaction_id or int(page.get("operation",-1)) != operation:
		stop(); return false
	var outcome := int(page.get("room_outcome",Outcome.None))
	var status := int(result.get("status",Contract.ManagementStatus.Rejected))
	if outcome == Outcome.Unknown or outcome == Outcome.None or outcome > Outcome.Unknown or outcome < Outcome.None:
		stop(); return false
	if outcome != Outcome.Completed:
		# Stale/rejected native operations provide no new authority. Continuing
		# requires an explicit fresh selection, never automatic resubmission.
		if status != Contract.ManagementStatus.Rejected:
			stop(); return false
		pending = {}; undo_token = 0; observed = page.duplicate(true)
		return true
	var token := int(page.get("undo_token",0))
	var created := int(page.get("rooms_created",0))
	var dormitories := int(page.get("rooms_dormitories",0))
	if status != Contract.ManagementStatus.Ok or token < 0 or created < 0 or dormitories < 0 or dormitories > created or (furniture != 1 and dormitories != 0) or (operation == Op.MultiCreate and (created > 0) != (token > 0)) or (operation == Op.MultiUndo and token != 0):
		stop(); return false
	pending = {}; undo_token = token; observed = page.duplicate(true)
	return true
