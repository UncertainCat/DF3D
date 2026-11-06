extends SceneTree
const State=preload("res://scripts/job_settings_state.gd")
const View=preload("res://scripts/work_order_details_view.gd")
const C=preload("res://scripts/management_contract.gd")
class Service extends RefCounted:
	signal session_changed
	var next:=0
	var calls: Dictionary={}
	var detached: Array=[]
	func submit(domain,request,callback):
		next+=1;calls[next]={"domain":domain,"request":request.duplicate(true),"callback":callback};return next
	func detach(id):detached.append(id)
	func reply(id,page):calls[id].callback.call(id,{"action":C.ManagementAction.JobSettingsRead,"status":C.ManagementStatus.Ok,"job_settings":page},calls[id].request)
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func page(cursor: int=0,next: int=0,revision: int=12) -> Dictionary:
	return {"job_id":42,"building_id":3,"unit_id":6534,"revision":11,"choices_revision":revision,"caption":"Fixture job","options":[{"kind":0,"index":0,"caption":"Fixture setting"}],"selected_option":0,"choices":[{"id":cursor+7,"caption":"Fixture material"}],"cursor":cursor,"total":2 if cursor or next else 1,"next_cursor":next}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();var state:=State.new();state.configure(service);state.open(3,42,6534)
	check(service.calls[state.ticket].domain=="job_settings" and service.calls[state.ticket].request.job_id==42,"Job state uses the typed job domain")
	service.reply(state.ticket,page(0,1));var old:=state.ticket
	check(state.phase==State.Phase.Reading and state.rows.is_empty(),"Partial catalog stays unpublished")
	state.set_query("stone");service.reply(old,page(1))
	check(state.rows.is_empty() and service.detached.has(old),"Superseded query cannot append old page")
	service.reply(state.ticket,page());check(state.phase==State.Phase.Ready and state.rows.size()==1,"Filtered catalog becomes ready")
	var applied: Array=[];state.applied.connect(func():applied.append(true))
	state.choose(999);state.choose(7);var edit: int=state.ticket;state.choose(7)
	var intent: Dictionary=service.calls[edit].request
	check(intent.action==C.ManagementAction.JobSettingsApply and intent.job_id==42 and intent.expected_revision==11 and intent.expected_choices_revision==12 and state.ticket==edit and state.phase==State.Phase.Applying,"Selection submits one exact job edit and blocks duplicate clicks")
	service.calls[edit].callback.call(edit,{"action":C.ManagementAction.JobSettingsApply,"status":C.ManagementStatus.Ok,"job_settings_edit":{"job_id":42,"building_id":3,"unit_id":6534,"outcome":C.JobSettingsEditOutcome.Applied}},intent)
	check(state.phase==State.Phase.Closed and applied.size()==1,"Confirmed edit closes Details")
	state.open(3,42,6534);service.reply(state.ticket,page());state.choose(7);edit=state.ticket
	service.calls[edit].callback.call(edit,{"outcome":"unknown"},service.calls[edit].request)
	var calls: int=service.next;state.choose(7);state.read_root()
	check(state.phase==State.Phase.Unknown and service.next==calls and applied.size()==1,"Unknown outcome is not retried or reported applied")
	state.open(3,42,6534);service.reply(state.ticket,page(0,1));service.reply(state.ticket,page(1,0,13))
	check(state.phase==State.Phase.Rejected and state.rows.is_empty(),"Changed catalog revision cannot splice pages")
	state.open(3,42,6534);old=state.ticket;service.session_changed.emit();service.reply(old,page())
	check(state.phase==State.Phase.Closed and state.snapshot.is_empty(),"Session replacement retires late settings")
	state.open(3,42,6534)
	var view:=View.new();view.job_context=true;view.state=state;root.add_child(view)
	view.cancelled.connect(state.close);view.back();service.reply(service.next,page())
	check(state.phase==State.Phase.Closed,"Escape can retire a pending read")
	view.free();state.dispose()
	if failures==0:print("JOB_SETTINGS_STATE_PASS")
	quit(1 if failures else 0)
