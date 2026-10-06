extends SceneTree
const Session = preload("res://scripts/native_options_session.gd")
class FakeWorld:
	extends RefCounted
	var requests: Array[PackedByteArray] = []
	var next_seq := 42
	var return_requests: Array = []
	func read_save_destinations(epoch: int) -> int:
		return_requests.append({"read":epoch})
		return next_seq
	func save_return_explicit(epoch: int, receipt: int, mode: int, id: String, bytes: PackedByteArray) -> int:
		return_requests.append({"epoch":epoch,"receipt":receipt,"mode":mode,"id":id,"bytes":bytes.duplicate()})
		return next_seq
	func save_fortress_bytes(bytes: PackedByteArray) -> int:
		requests.append(bytes.duplicate())
		return next_seq
	func quit_without_saving(epoch: int) -> int:
		return_requests.append({"quit":epoch})
		return next_seq
class FakeConfirmation:
	extends RefCounted
	var token := ""
class FakeOptions:
	extends RefCounted
	signal save_requested(bytes: PackedByteArray)
	signal route_requested(token: String)
	signal destination_requested(id: String)
	signal timeline_requested(bytes: PackedByteArray)
	signal confirmed(token: String)
	var confirmation=FakeConfirmation.new()
	enum Page { CLOSED, MENU, NAME, CONFIRMATION, RETURN_CHOICES, TIMELINE_NAME }
	var page := Page.NAME
	var session_busy := false
	var closed := 0
	var destinations: Array = []
	func show_save_return(rows: Array) -> bool:
		if page != Page.MENU or not accepts_input(): return false
		destinations=rows.duplicate(true)
		page=Page.RETURN_CHOICES
		return true
	func accepts_input() -> bool: return not session_busy
	func close() -> void:
		closed += 1
		page = Page.CLOSED
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var owner = Session.new()
	var world = FakeWorld.new()
	var view = FakeOptions.new()
	owner.configure(world, view)
	var outcomes: Array[String] = []
	owner.settled.connect(func(value):outcomes.append(value))
	var ready := {"phase":3,"fortress_valid":true,"fortress_epoch":7,"can_save":true}
	owner.update_session(ready)
	# Include truncated UTF-8: the presentation must not repair native bytes.
	var name := PackedByteArray([97, 46, 195])
	view.save_requested.emit(name)
	name[0] = 98
	view.save_requested.emit(name)
	check(world.requests == [PackedByteArray([97,46,195])] and view.session_busy, "One submission with unchanged native bytes")
	owner.update_session({"phase":4})
	owner.update_session(ready)
	view.save_requested.emit(name)
	check(world.requests.size()==1 and owner.pending_seq==42, "Disconnect/reconnect retains ownership without replay")
	var receipt := ready.duplicate()
	receipt.merge({"request_seq":42,"request_fortress_epoch":8,"request_action":1,"request_status":2}, true)
	owner.update_session(receipt)
	check(view.closed==0 and owner.pending_seq==42, "Wrong epoch must not settle save")
	receipt.request_fortress_epoch=7
	receipt.request_action=2
	owner.update_session(receipt)
	check(view.closed==0 and owner.pending_seq==42, "Wrong action must not settle save")
	receipt.request_action=1
	receipt.request_seq=41
	owner.update_session(receipt)
	check(view.closed==0 and owner.pending_seq==42, "Old sequence must not settle save")
	receipt.request_seq=42
	owner.update_session(receipt)
	owner.update_session(receipt)
	check(view.closed==1 and outcomes==["succeeded"] and owner.pending_seq==0, "Exact late receipt closes once")
	view.page=view.Page.NAME
	world.next_seq=43
	owner.update_session(ready)
	view.save_requested.emit(name)
	receipt.request_seq=43
	receipt.request_status=3
	owner.update_session(receipt)
	check(view.page==view.Page.NAME and not view.session_busy and outcomes[-1]=="rejected", "Rejection preserves naming page and permits explicit editing")
	world.next_seq=0
	view.save_requested.emit(name)
	check(owner.pending_seq==0 and not view.session_busy and outcomes[-1]=="not_sent", "Not-sent request does not acquire ownership")
	world.next_seq=44
	view.save_requested.emit(name)
	receipt.request_seq=44
	receipt.request_status=2
	receipt.fortress_epoch=9
	owner.update_session(receipt)
	check(view.closed==1 and owner.pending_seq==0, "Old fortress receipt cannot close new fortress dialog")
	owner.update_session(ready)
	world.next_seq=45
	view.save_requested.emit(name)
	owner.update_session({"phase":4})
	var replacement:=ready.duplicate()
	replacement.fortress_epoch=10
	var request_count:int=world.requests.size()
	owner.update_session(replacement)
	check(owner.pending_seq==0 and not view.session_busy and view.closed==1 and world.requests.size()==request_count, "Replacement fortress releases old input without closing new dialog or replaying save")
	check(owner.last_outcome=={"sequence":45,"fortress_epoch":7,"outcome":"unknown"}, "Replacement preserves unknown old save outcome")
	# A new producer can reuse a sequence. Epoch still separates its receipt.
	view.save_requested.emit(name)
	receipt.request_seq=45
	receipt.fortress_epoch=10
	owner.update_session(receipt)
	check(owner.pending_seq==45 and view.closed==1, "Late old receipt cannot settle reused sequence in new fortress")
	receipt.request_fortress_epoch=10
	owner.update_session(receipt)
	check(owner.pending_seq==0 and view.closed==2, "Replacement request settles on its own epoch")
	view.page=view.Page.MENU
	replacement.can_save_return=true
	owner.update_session(replacement)
	world.next_seq=46
	view.route_requested.emit("SAVE_AND_QUIT")
	check(world.return_requests==[{"read":10}] and owner.pending_seq==46 and view.session_busy, "SaveReturn first requests a current catalog")
	var read_receipt:=replacement.duplicate()
	read_receipt.merge({"request_seq":46,"request_fortress_epoch":10,"request_action":8,"request_status":2,"save_destinations":{"receipt":91,"fortress_epoch":10,"destinations":[{"id":"91:0","folder":"region16"}]}},true)
	owner.update_session(read_receipt)
	check(view.page==view.Page.RETURN_CHOICES and not view.session_busy and view.destinations.size()==1, "Successful matching read opens native chooser")
	world.next_seq=47
	view.destination_requested.emit("91:0")
	check(world.return_requests[-1]=={"epoch":10,"receipt":91,"mode":1,"id":"91:0","bytes":PackedByteArray()}, "Destination intent retains catalog and epoch")
	view.destination_requested.emit("91:0")
	check(world.return_requests.size()==2, "Pending destination is not replayed")
	owner.update_session({"phase":4})
	owner.update_session({"phase":1,"fortress_epoch":0,"request_seq":47,"request_fortress_epoch":10,"request_action":2,"request_status":2})
	check(view.closed==3 and owner.pending_seq==0, "SaveReturn receipt settles after native world unload")
	# A late catalog cannot replace a new fortress's menu.
	view.page=view.Page.MENU
	owner.update_session(replacement);world.next_seq=48
	view.route_requested.emit("SAVE_AND_QUIT")
	var next_fort:=replacement.duplicate();next_fort.fortress_epoch=11
	owner.update_session(next_fort)
	read_receipt.request_seq=48;read_receipt.fortress_epoch=11
	owner.update_session(read_receipt)
	check(view.page==view.Page.MENU and owner.pending_seq==0, "Old catalog cannot open in replacement fortress")
	view.page=view.Page.NAME;owner.update_session(next_fort);world.next_seq=49
	view.save_requested.emit(PackedByteArray([97]))
	var unknown:=next_fort.duplicate()
	unknown.merge({"request_seq":49,"request_fortress_epoch":11,"request_action":1,"request_status":4},true)
	var before_unknown:int=world.requests.size()
	owner.update_session(unknown);owner.update_session(unknown)
	check(owner.pending_seq==0 and owner.last_outcome.outcome=="unknown" and view.page==view.Page.NAME and view.closed==3 and world.requests.size()==before_unknown, "Unknown writer outcome preserves draft without success or automatic replay")
	world.next_seq=50
	view.save_requested.emit(PackedByteArray([98]))
	unknown.request_seq=50;unknown.phase=4;unknown.fortress_valid=false;unknown.fortress_epoch=0
	owner.update_session(unknown)
	check(owner.pending_seq==0 and owner.last_outcome=={"sequence":50,"fortress_epoch":11,"outcome":"unknown"}, "Verified producer loss releases request ownership with its original save epoch")
	owner.update_session({"phase":1,"fortress_epoch":0})
	check(owner.pending_seq==0 and view.page==view.Page.NAME and view.closed==3 and world.requests.size()==before_unknown+1, "Reconnect at title cannot replay or report success for lost producer")
	view.page=view.Page.MENU;owner.update_session(next_fort);world.next_seq=51
	var before_read_loss:int=world.return_requests.size()
	view.route_requested.emit("SAVE_AND_QUIT")
	owner.update_session({"phase":4,"fortress_epoch":0,"request_seq":51,"request_fortress_epoch":11,"request_action":8,"request_status":3})
	check(owner.pending_seq==0 and owner.last_outcome.outcome=="rejected" and view.page==view.Page.MENU and owner.catalog.is_empty(), "Lost catalog producer releases ownership without opening an empty chooser")
	owner.update_session({"phase":1,"fortress_epoch":0})
	check(owner.pending_seq==0 and world.return_requests.size()==before_read_loss+1, "Lost destination read is not replayed at replacement title")
	owner.update_session(next_fort);world.next_seq=52
	var before_quit:int=world.return_requests.size()
	view.confirmation.token="QUIT_WITHOUT_SAVING"
	view.confirmed.emit("QUIT_WITHOUT_SAVING")
	check(world.return_requests.size()==before_quit, "Quit cannot bypass its confirmation page")
	view.page=view.Page.CONFIRMATION
	view.confirmed.emit("ABANDON_FORTRESS")
	check(world.return_requests.size()==before_quit, "Other confirmation cannot dispatch quit")
	view.confirmed.emit("QUIT_WITHOUT_SAVING");view.confirmed.emit("QUIT_WITHOUT_SAVING")
	check(owner.pending_seq==52 and world.return_requests.size()==before_quit+1 and world.return_requests[-1]=={"quit":11}, "Confirmed Quit sends one epoch-scoped operation")
	owner.update_session({"phase":7,"request_seq":52,"request_fortress_epoch":11,"request_action":9,"request_status":1})
	check(owner.pending_seq==52 and view.session_busy, "Native unloading retains ownership")
	owner.update_session({"phase":1,"fortress_epoch":0,"request_seq":52,"request_fortress_epoch":11,"request_action":9,"request_status":2})
	check(owner.pending_seq==0 and view.page==view.Page.CLOSED and view.closed==4, "Confirmed native quit closes only on matching title completion")
	owner.free()
	print("NATIVE_OPTIONS_SESSION_TEST failures=", failures)
	quit(1 if failures else 0)
