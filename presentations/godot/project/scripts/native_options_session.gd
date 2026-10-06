extends Node
# Unexposed session owner. No product copy or inferred completion here.
# Manual filename/overwrite parity and complete protected SaveReturn acceptance remain open.
signal settled(outcome: String)
var world
var options
var latest: Dictionary = {}
var pending_seq := 0
var pending_epoch := 0
var pending_action := -1
var catalog: Dictionary = {}
var last_outcome: Dictionary = {}

func configure(source, view) -> void:
	world = source
	options = view
	options.save_requested.connect(_save)
	options.route_requested.connect(_route)
	options.destination_requested.connect(func(id): _return(1,id,PackedByteArray()))
	options.timeline_requested.connect(func(bytes): _return(3,"",bytes))
	options.confirmed.connect(_confirmed)

func _confirmed(token: String) -> void:
	if token != "QUIT_WITHOUT_SAVING" or options.page != options.Page.CONFIRMATION or options.confirmation.token != token or not _can_return(): return
	_begin(world.quit_without_saving(latest.fortress_epoch),9)

func _route(token: String) -> void:
	if token == "SAVE_TO_NEW_FOLDER_EXISTING_TIMELINE":
		_return(2,"",PackedByteArray())
	elif token == "SAVE_AND_QUIT" and options.page == options.Page.MENU and _can_return():
		catalog.clear()
		_begin(world.read_save_destinations(latest.fortress_epoch),8)

func _can_return() -> bool:
	return pending_seq == 0 and options.accepts_input() and latest.get("phase",4) == 3 and latest.get("fortress_valid",false) and latest.get("can_save_return",false) and latest.get("fortress_epoch",0) != 0

func _return(mode: int, id: String, bytes: PackedByteArray) -> void:
	if not _can_return() or catalog.get("fortress_epoch",0) != latest.fortress_epoch or catalog.get("receipt",0) == 0: return
	if options.page != (options.Page.TIMELINE_NAME if mode == 3 else options.Page.RETURN_CHOICES): return
	_begin(world.save_return_explicit(latest.fortress_epoch,catalog.receipt,mode,id,bytes),2)

func _begin(sequence: int, action: int) -> void:
	if sequence == 0:
		settled.emit("not_sent")
		return
	pending_seq = sequence
	pending_epoch = latest.fortress_epoch
	pending_action = action
	options.session_busy = true

func _save(bytes: PackedByteArray) -> void:
	if pending_seq != 0 or not options.accepts_input() or options.page != options.Page.NAME:
		return
	if latest.get("phase", 4) != 3 or not latest.get("fortress_valid", false) or not latest.get("can_save", false) or latest.get("fortress_epoch", 0) == 0:
		return
	_begin(world.save_fortress_bytes(bytes),1)

func update_session(state: Dictionary) -> void:
	latest = state
	if pending_seq != 0:
		# Missing snapshots are not outcomes: retain ownership for a late reply.
		# Verified producer loss arrives from the model with the original request
		# identity (unknown save or failed read); never replay either operation.
		var matches: bool = state.get("request_seq", 0) == pending_seq and state.get("request_fortress_epoch", 0) == pending_epoch and state.get("request_action", -1) == pending_action
		if matches and state.get("request_status", 0) in [2, 3, 4]:
			var succeeded: bool = state.request_status == 2
			var same_fortress: bool = state.get("fortress_epoch", 0) == pending_epoch
			# A late receipt can settle the operation, but cannot close a newer
			# fortress's dialog. The global host owns session-change dismissal.
			if succeeded and pending_action == 8:
				var received: Dictionary = state.get("save_destinations",{})
				if same_fortress and received.get("fortress_epoch",0) == pending_epoch and received.get("receipt",0) != 0 and received.get("destinations") is Array:
					options.session_busy = false
					if options.show_save_return(received.destinations): catalog = received.duplicate(true)
			elif succeeded and (same_fortress or (pending_action in [2,9] and state.get("phase",4) == 1 and state.get("fortress_epoch",0) == 0)):
				options.close()
			_settle("succeeded" if succeeded else "unknown" if state.request_status == 4 else "rejected")
		elif state.get("fortress_valid", false) and state.get("fortress_epoch", 0) != 0 and state.fortress_epoch != pending_epoch:
			# An authoritative replacement fortress releases the old input gate,
			# but does not prove the old save's result or authorize replay.
			_settle("unknown")
	options.session_busy = pending_seq != 0 or state.get("phase", 4) != 3 or state.get("request_status", 0) == 1

func _settle(outcome: String) -> void:
	last_outcome = {"sequence":pending_seq,"fortress_epoch":pending_epoch,"outcome":outcome}
	pending_seq = 0
	pending_epoch = 0
	pending_action = -1
	settled.emit(outcome)
