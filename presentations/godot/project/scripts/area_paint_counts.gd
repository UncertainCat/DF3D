extends RefCounted
const Contract = preload("res://scripts/management_contract.gd")
signal changed
# One read ticket, latest local demand. These are refresh cadences, not native
# mutation budgets. Idle refresh includes dependencies absent from tile hover
# data (adjacent/lower water, occupancy and soil), even while DF is paused.
var minimum_interval := 0.1
var refresh_interval := 0.5
var identity: Array = []
var desired: Dictionary = {}
var values: Dictionary = {}
var ticket := 0
var service
var _generation := 0
var _cooldown := 0.0
var _age := 0.0
var _due := false

func demand(key: Array, request: Dictionary) -> void:
	if key == identity: return
	identity = key.duplicate(true)
	desired = request.duplicate(true)
	values = {}; _age = 0.0; _due = true
	changed.emit()

func clear() -> void:
	if identity.is_empty() and ticket == 0: return
	_generation += 1
	if service != null and ticket != 0: service.detach(ticket)
	ticket = 0; identity = []; desired = {}; values = {}
	_cooldown = 0.0; _age = 0.0; _due = false
	changed.emit()

func poll(delta: float) -> void:
	_cooldown = maxf(0.0,_cooldown-maxf(0.0,delta))
	if desired.is_empty() or service == null: return
	_age += maxf(0.0,delta)
	if not values.is_empty() and _age >= refresh_interval:
		values = {}; _due = true
		changed.emit()
	if ticket != 0 or not _due or _cooldown > 0.0: return
	_generation += 1
	var request := desired.duplicate(true)
	request.count_generation = _generation
	var key := identity.duplicate(true)
	_due = false; _cooldown = minimum_interval
	ticket = service.submit("areas",request,func(received_ticket, result, sent):
		if received_ticket != ticket: return
		ticket = 0
		if key != identity or int(sent.get("count_generation",0)) != _generation: return
		_age = 0.0
		var area: Dictionary = result.get("area",{})
		var valid := int(result.get("status",-1)) == Contract.ManagementStatus.Ok and int(result.get("action",-1)) == Contract.ManagementAction.AreaInspect
		valid = valid and int(area.get("operation",-1)) == Contract.AreaOperation.PaintCounts and int(area.get("count_generation",0)) == _generation
		for field in ["painted_count","preview_count"]:
			valid = valid and typeof(area.get(field)) == TYPE_INT and int(area.get(field,-2)) >= -1 and int(area.get(field,-2)) <= 32768
		if valid:
			values = {"painted":int(area.painted_count),"preview":int(area.preview_count)}
		else:
			values = {}; _due = true; _cooldown = refresh_interval
		changed.emit())
	if ticket == 0: _due = true
