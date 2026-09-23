extends Node
const Contract = preload("res://scripts/management_contract.gd")
const Action = Contract.ManagementAction
const Status = Contract.ManagementStatus
# Single owner of the serialized semantic management channel. Views own only tickets.
signal session_changed
signal completed(ticket: int, result: Dictionary)
var world
var timeout_seconds := 15.0
var retention_limit := 128
var _next_ticket := 1
var _queue: Array[int] = []
var _requests: Dictionary = {}
var _results: Dictionary = {}
var _outcomes: Dictionary = {}
var _active := 0
var _epoch := 0
var _generation := -1
var _invalidating := false
var _transport_lost := false

func configure(source) -> void:
	world = source
	world.reconnect_management()

func submit(domain: String, request: Dictionary, observer: Callable) -> int:
	if _invalidating or _transport_lost: return 0
	var ticket := _next_ticket
	_next_ticket += 1
	_requests[ticket] = {"domain": domain, "request": request.duplicate(true),
		"observer": observer, "detached": false, "sequence": 0, "elapsed": 0.0, "unknown": false}
	_queue.append(ticket)
	return ticket

func detach(ticket: int) -> void:
	if _requests.has(ticket):
		_requests[ticket].observer = Callable()
		_requests[ticket].detached = true
		# A draft still owned by this queue has not reached DF. Cancelling it
		# must remove the intent, not merely stop observing its eventual effect.
		# Sent work instead stays owned here until its receipt is reconciled.
		if not _invalidating and _queue.has(ticket):
			_queue.erase(ticket)
			_publish(ticket, {"status": Status.Rejected, "outcome": "not_sent",
				"message": "Draft cancelled before submission"})
			_requests.erase(ticket)
	if _outcomes.has(ticket): _outcomes[ticket].detached = true

func result(ticket: int) -> Dictionary:
	return _results.get(ticket, {}).duplicate(true)

func last_detached_mutation(domain: String) -> Dictionary:
	var latest := 0
	for ticket in _outcomes:
		var outcome: Dictionary = _outcomes[ticket]
		if outcome.domain == domain and outcome.detached and int(ticket) > latest:
			latest = int(ticket)
	return _outcomes.get(latest, {}).duplicate(true)

func _process(delta: float) -> void:
	poll(delta)

func _publish(ticket: int, state: Dictionary) -> void:
	_results[ticket] = state.duplicate(true)
	var item: Dictionary = _requests[ticket]
	# An unknown outcome consumes the one-shot observer; late resolution is detached.
	if state.get("outcome", "") == "unknown": item.detached = true
	if Contract.is_mutation(int(item.request.get("action", -1))):
		_outcomes[ticket] = {"ticket":ticket,"domain":item.domain,"detached":item.detached,"request":item.request.duplicate(true),"result":state.duplicate(true)}
	while _results.size() > retention_limit:
		var expired: int = _results.keys()[0]
		_results.erase(expired)
		_outcomes.erase(expired)
	var observer: Callable = item.observer
	item.observer = Callable()
	completed.emit(ticket, state.duplicate(true))
	if observer.is_valid(): observer.call(ticket, state.duplicate(true), item.request.duplicate(true))

func _invalidate(message: String = "The world changed before this action was confirmed; it will not be retried automatically") -> void:
	_invalidating = true
	session_changed.emit()
	var invalidated := _requests.keys()
	_queue.clear()
	_active = 0
	for ticket in invalidated:
		_publish(ticket, {"status": Status.Rejected, "outcome": "unknown" if int(_requests[ticket].sequence) > 0 else "not_sent",
			"message": message})
		_requests.erase(ticket)
	_invalidating = false

func poll(delta: float = 0.0) -> void:
	if world == null: return
	var state: Dictionary = world.poll_management()
	# Only confirmed producer loss releases an uncertain sent operation. An
	# elapsed timeout alone must keep draining its durable private receipt.
	if not bool(state.get("transport_alive", true)):
		if not _transport_lost:
			_transport_lost = true
			_invalidate("Management connection ended; sent outcomes are unknown and will not be replayed")
			_epoch = 0
			world.reconnect_management()
		return
	var generation := int(world.session_generation()) if world.has_method("session_generation") else 0
	var epoch := int(state.get("world_epoch", 0))
	if _generation >= 0 and generation != _generation:
		_invalidate()
		_generation = generation
		_epoch = 0
		world.reconnect_management()
		return
	if _epoch > 0 and epoch > 0 and epoch != _epoch:
		_invalidate()
	_generation = generation
	if epoch > 0: _epoch = epoch
	if _transport_lost:
		_transport_lost = false
		# Reconcile model identity first: a new generation must not invalidate
		# the replacement connection's fresh read-only claim.
		submit("construction", {"action": Action.Catalog}, Callable())
	if _active != 0:
		var ticket := _active
		var item: Dictionary = _requests[ticket]
		item.elapsed += maxf(0.0, delta)
		var terminal := int(state.get("status", Status.Idle)) in [Status.Ok, Status.Rejected]
		if terminal and int(state.get("request_seq", 0)) == int(item.sequence):
			_active = 0
			_publish(ticket, state)
			_requests.erase(ticket)
		elif not item.unknown and (float(item.elapsed) >= timeout_seconds or (int(state.get("revision", 0)) == 0 and int(state.get("status", Status.Idle)) == Status.Rejected)):
			item.unknown = true
			_publish(ticket, {"status": Status.Rejected, "outcome": "unknown", "message": "The result is unknown; it will not be retried automatically"})
			# Keep draining this sequence: releasing a timed-out mutation could overwrite its receipt.
	if _active != 0 or _queue.is_empty(): return
	var ticket: int = _queue.pop_front()
	var item: Dictionary = _requests[ticket]
	if item.domain not in ["construction", "areas"]:
		_publish(ticket, {"status":Status.Rejected,"outcome":"not_sent","message":"This action is not supported yet"})
		_requests.erase(ticket)
		return
	if not world.is_live():
		_publish(ticket, {"status": Status.Rejected, "outcome": "not_sent", "message": "Requires a live fortress"})
		_requests.erase(ticket)
		return
	var sequence := int(world.construction_request(item.request) if item.domain == "construction" else world.area_request(item.request))
	if sequence == 0:
		_publish(ticket, {"status": Status.Rejected, "outcome": "not_sent", "message": world.last_error()})
		_requests.erase(ticket)
	else:
		item.sequence = sequence
		_active = ticket
