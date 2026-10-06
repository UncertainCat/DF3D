extends Node
const Contract = preload("res://scripts/management_contract.gd")
const Action = Contract.ManagementAction
const Status = Contract.ManagementStatus
# Single owner of the serialized semantic management channel. Views own only tickets.
signal session_changed
signal completed(ticket: int, result: Dictionary)
var world
var _split_payload := false
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
var _bootstrap := false
var _needs_claim := false
var _claim_delay := 0.0
var _continuation_ticket := 0
var _continuation_domain := ""
var _continuation_used := false

func configure(source, bootstrap := false) -> void:
	_bootstrap = bootstrap; _needs_claim = bootstrap; _claim_delay = 0.0
	world = source
	_split_payload = world.has_method("poll_management_header") and world.has_method("management_payload")
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

func submit_continuation(previous: int, domain: String, request: Dictionary, observer: Callable) -> int:
	# A successful mutation's one-shot observer may finish its existing intent
	# before later queued interactions. This is not a retry or a general priority
	# queue: authority expires on returning from that observer, and cannot cross
	# domains, rejection, unknown outcomes or epoch invalidation.
	var action = request.get("action",-1)
	if previous <= 0 or previous != _continuation_ticket or _continuation_used or domain != _continuation_domain:
		return 0
	if typeof(action) != TYPE_INT or not Contract.is_mutation(action) or Contract.domain_of(action) != domain: return 0
	var ticket := submit(domain,request,observer)
	if ticket != 0:
		_continuation_used = true
		_queue.erase(ticket); _queue.push_front(ticket)
	return ticket

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
	var raw_action = item.request.get("action", -1)
	if typeof(raw_action) == TYPE_INT and Contract.is_mutation(int(raw_action)):
		_outcomes[ticket] = {"ticket":ticket,"domain":item.domain,"detached":item.detached,"request":item.request.duplicate(true),"result":state.duplicate(true)}
	while _results.size() > retention_limit:
		var expired: int = _results.keys()[0]
		_results.erase(expired)
		_outcomes.erase(expired)
	var observer: Callable = item.observer
	item.observer = Callable()
	var previous_ticket := _continuation_ticket
	var previous_domain := _continuation_domain
	var previous_used := _continuation_used
	_continuation_ticket = 0; _continuation_domain = ""; _continuation_used = false
	if completed.has_connections(): completed.emit(ticket, state.duplicate(true))
	if not _invalidating and not item.unknown and int(item.sequence) > 0 and int(state.get("status",Status.Rejected)) == Status.Ok and str(state.get("outcome","")) != "unknown" and typeof(raw_action) == TYPE_INT and Contract.is_mutation(raw_action):
		_continuation_ticket = ticket; _continuation_domain = str(item.domain)
	# poll_management returns an owned value; retention and signal delivery above
	# already have isolated copies. Transfer this last local copy to the one-shot
	# observer instead of copying every material candidate yet again.
	if observer.is_valid(): observer.call(ticket, state, item.request.duplicate(true))
	_continuation_ticket = previous_ticket; _continuation_domain = previous_domain; _continuation_used = previous_used

func _invalidate(message: String = "The world changed before this action was confirmed; it will not be retried automatically") -> void:
	_invalidating = true
	_needs_claim = _bootstrap; _claim_delay = 0.0
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
	var state: Dictionary = world.poll_management_header() if _split_payload else world.poll_management()
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
		if not _bootstrap: submit("construction", {"action": Action.Catalog}, Callable())
	if _active != 0:
		var ticket := _active
		var item: Dictionary = _requests[ticket]
		item.elapsed += maxf(0.0, delta)
		var terminal := int(state.get("status", Status.Idle)) in [Status.Ok, Status.Rejected]
		if terminal and int(state.get("request_seq", 0)) == int(item.sequence):
			if _split_payload:
				state = world.management_payload(epoch,int(state.get("revision",0)),int(item.sequence))
				if state.is_empty(): return # Identity changed; retain the ticket and drain.
			_active = 0
			if (int(state.get("area",{}).get("location_entry_outcome",0)) == Contract.LocationEntryOutcome.Unknown
				or int(state.get("area",{}).get("location_edit_outcome",0)) == Contract.LocationEditOutcome.Unknown
				or int(state.get("construction",{}).get("outcome",0)) == Contract.ConstructionOutcome.Unknown):
				state["outcome"] = "unknown"
			elif int(state.get("construction",{}).get("outcome",0)) == Contract.ConstructionOutcome.Partial:
				state["outcome"] = "partial"
			_publish(ticket, state)
			_requests.erase(ticket)
		elif not item.unknown and (float(item.elapsed) >= timeout_seconds or (int(state.get("revision", 0)) == 0 and int(state.get("status", Status.Idle)) == Status.Rejected)):
			item.unknown = true
			_publish(ticket, {"status": Status.Rejected, "outcome": "unknown", "message": "The result is unknown; it will not be retried automatically"})
			# Keep draining this sequence: releasing a timed-out mutation could overwrite its receipt.
	if _active == 0 and _needs_claim:
		_claim_delay = maxf(0.0, _claim_delay - maxf(0.0, delta))
		if _claim_delay > 0.0 or epoch <= 0 or not world.is_live(): return
		# The native client requires its own Catalog receipt before any other
		# request. Claim first on startup and after session invalidation.
		var claim := submit("construction", {"action": Action.Catalog}, func(_ticket, result, _sent):
			if int(result.get("status", Status.Rejected)) != Status.Ok or int(result.get("action", -1)) != Action.Catalog or result.get("outcome", "") == "unknown":
				_needs_claim = true; _claim_delay = 0.5)
		if claim == 0: return
		_needs_claim = false
		_queue.erase(claim); _queue.push_front(claim)
	if _active != 0 or _queue.is_empty(): return
	var ticket: int = _queue.pop_front()
	var item: Dictionary = _requests[ticket]
	var raw_action = item.request.get("action", -1)
	var action := int(raw_action) if typeof(raw_action) == TYPE_INT else -1
	var action_domain := Contract.domain_of(action)
	if not Contract.is_runtime(action) or (action != Action.Catalog and (action_domain.is_empty() or action_domain != item.domain)):
		_publish(ticket, {"status":Status.Rejected,"outcome":"not_sent","message":"Management action does not match a runtime domain"})
		_requests.erase(ticket)
		return
	if not world.is_live():
		_publish(ticket, {"status": Status.Rejected, "outcome": "not_sent", "message": "Requires a live fortress"})
		_requests.erase(ticket)
		return
	var sequence := int(world.management_request(item.domain, item.request))
	if sequence == 0:
		_publish(ticket, {"status": Status.Rejected, "outcome": "not_sent", "message": world.last_error()})
		_requests.erase(ticket)
	else:
		item.sequence = sequence
		_active = ticket
