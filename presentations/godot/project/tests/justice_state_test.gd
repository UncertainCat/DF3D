extends SceneTree
const View=preload("res://scripts/justice_view.gd")
const Owner=preload("res://scripts/justice_panel.gd")
const Registry=preload("res://scripts/ui_availability.gd")
const State=preload("res://scripts/justice_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func page(ids: Array=[9,10],offset:=0,total:=2,tab:=0,revision:=8) -> Dictionary:
	return {"justice":{"outcome":C.JusticeOutcome.None,"tab":tab,"list_revision":revision,"offset":offset,"total":total,"rows":ids.map(func(id):return {"crime_id":id,"caption":"fixture"})}}
func report(id:=9,offset:=0,total:=1,revision:=12,tab:=0) -> Dictionary:
	return {"justice":{"outcome":C.JusticeOutcome.None,"tab":tab,"list_revision":8,"detail":{"crime_id":id,"resolution":C.JusticeCaseResolution.Unsolved,"revision":revision,"caption":"fixture","status":"fixture status","total":total,"offset":offset,"witnesses":[{"witness":"fixture witness","description":"","date":"event","reported":"reported"}]}}}
func _initialize() -> void:call_deferred("run")
func candidates(ids: Array=[42,43],offset:=0,total:=2,revision:=22) -> Dictionary:
	return {"justice":{"outcome":C.JusticeOutcome.None,"tab":0,"list_revision":8,"candidates":{"crime_id":9,"revision":revision,
		"offset":offset,"total":total,"rows":ids.map(func(id):return {"unit_id":id,"rank":3,"interrogation_pending":false,"counterintelligence":true,"display":{"columns":28,"name":"fixture","witness_count":0,"witness_label":"fixture","witness_color":6,"deceased":"","name_color":{"color":[4,0,0],"alternate":[4,0,0],"effect":0}}})}}}
func ready(service,state) -> void:
	state.open();service.reply(state.ticket,page());service.reply(state.ticket,report())
func test_candidates(service,state) -> void:
	ready(service,state);state.open_candidates();var picker=state.candidates
	service.reply(picker.ticket,candidates([42],0,2))
	check(picker.rows.is_empty() and service.calls[picker.ticket].intent.offset==1 and service.calls[picker.ticket].intent.expected_candidate_revision==22,"Partial candidates leaked or lost revision")
	service.reply(picker.ticket,candidates([43],1,2));check(picker.rows.size()==2 and picker.phase==picker.Phase.Ready,"Candidate pages failed to assemble")
	picker.search("first");var old: int=picker.ticket;picker.search("second");var current: int=picker.ticket
	service.reply(old,candidates());check(picker.ticket==current and picker.rows.is_empty(),"Old search replaced current query")
	service.reply(current,candidates());picker.convict(42);current=picker.ticket
	var intent: Dictionary=service.calls[current].intent
	check(intent.query=="second" and intent.unit_id==42 and intent.expected_candidate_revision==22 and intent.expected_case_revision==12 and intent.expected_list_revision==8,"Conviction lost selection scope")
	picker.convict(42);picker.search("changed");state.open_candidates()
	check(picker.ticket==current and picker.phase==picker.Phase.Applying,"Pending conviction allowed another request")
	service.reply(current,{"status":C.ManagementStatus.Rejected,"justice":{"outcome":C.JusticeOutcome.Unknown}})
	check(picker.phase==picker.Phase.Unknown and picker.rows.size()==2,"Unknown conviction lost disabled rows")
	var count: int=service.next;picker.convict(42);picker.search("retry");state.open_candidates()
	check(service.next==count,"Unknown conviction replayed or refreshed implicitly")
	ready(service,state);state.open_candidates();service.reply(picker.ticket,candidates());picker.convict(42);old=picker.ticket
	state.close();service.reply(old,{"justice":{"outcome":C.JusticeOutcome.Applied}})
	check(state.phase==State.Phase.Closed and picker.phase==picker.Phase.Closed,"Late conviction reopened parent")
	ready(service,state);state.open_candidates();service.reply(picker.ticket,candidates());picker.convict(42)
	service.reply(picker.ticket,{"justice":{"outcome":C.JusticeOutcome.Applied}})
	check(state.phase==State.Phase.Reading and state.rows.is_empty() and picker.phase==picker.Phase.Closed,"Applied conviction failed to refresh parent cases")
	for fault in 3:
		ready(service,state);state.open_candidates();service.reply(picker.ticket,candidates([42],0,2));var continuation:=candidates([43],1,2)
		match fault:
			0:continuation.justice.candidates.revision=23
			1:continuation.justice.candidates.rows[0].unit_id=42
			2:continuation.justice.candidates.rows=[]
		service.reply(picker.ticket,continuation)
		check(picker.phase==picker.Phase.Rejected and picker.rows.is_empty() and picker.ticket==0,"Malformed candidate continuation accepted or replayed")
	ready(service,state);state.open_candidates();old=picker.ticket;state.select_case(10);service.reply(old,candidates())
	check(picker.phase==picker.Phase.Closed and picker.rows.is_empty(),"Case switch retained old candidate picker")
	ready(service,state);state.open_candidates();old=picker.ticket;service.session_changed.emit();service.reply(old,candidates())
	check(state.phase==State.Phase.Unavailable and picker.phase in [picker.Phase.Closed,picker.Phase.Unavailable] and picker.rows.is_empty(),"Session change accepted late candidates")
func run() -> void:
	check(Registry.PANEL_SCRIPTS.has("justice") and not Registry.PANEL_ROUTES.has("Justice"),"Justice public gate changed")
	var service:=Service.new();root.add_child(service);var state:=State.new();state.configure(service);state.open()
	service.reply(state.ticket,page([9],0,2));check(state.rows.is_empty() and state.phase==State.Phase.Reading,"Partial cases exposed")
	check(service.calls[state.ticket].intent.offset==1 and service.calls[state.ticket].intent.expected_list_revision==8,"Case continuation lost receipt")
	service.reply(state.ticket,page([10],1,2));check(state.rows.size()==2 and state.selected_id==9 and state.phase==State.Phase.DetailReading,"Initial native selection missing")
	service.reply(state.ticket,report(9,0,2));check(state.detail.is_empty(),"Partial witnesses exposed")
	check(service.calls[state.ticket].intent.offset==1 and service.calls[state.ticket].intent.expected_case_revision==12,"Witness continuation lost receipt")
	service.reply(state.ticket,report(9,1,2));check(state.phase==State.Phase.Ready and state.detail.witnesses.size()==2 and not state.detail.has("injured_party"),"Witness pages not assembled")
	state.seek_witness(99,1);check(state.witness_first==1,"Witness scroll not clamped")
	state.select_case(10);var old: int=state.ticket;state.select_case(9);var current: int=state.ticket
	service.reply(old,report(10));check(state.ticket==current and state.detail.is_empty() and service.detached.has(old),"Late old case replaced current detail")
	service.reply(current,report());state.select_case(10);old=state.ticket;state.select_tab(2);current=state.ticket
	service.reply(old,report(10));check(state.ticket==current and state.rows.is_empty() and state.selected_id==-1,"Tab switch retained old selection")
	service.reply(current,page([],0,0,2));check(state.phase==State.Phase.Ready and state.detail.is_empty(),"Empty tab rejected")
	state.open();service.reply(state.ticket,page());old=state.ticket;state.close();service.reply(old,report())
	check(state.phase==State.Phase.Closed and state.detail.is_empty(),"Close accepted late detail")
	state.open();service.reply(state.ticket,page());old=state.ticket;service.session_changed.emit();service.reply(old,report())
	check(state.phase==State.Phase.Unavailable and state.rows.is_empty(),"Session change retained case rows")
	for fault in 4:
		state.open();service.reply(state.ticket,page());service.reply(state.ticket,report(9,0,2));var second:=report(9,1,2)
		match fault:
			0:second.justice.detail.revision=13
			1:second.justice.detail.crime_id=10
			2:second.justice.detail.witnesses=[]
			3:second.justice.detail.status="changed"
		service.reply(state.ticket,second);check(state.phase==State.Phase.Ready and state.detail.is_empty() and state.ticket==0,"Malformed detail accepted or replayed")
	state.open();var stale: Dictionary={"status":C.ManagementStatus.Rejected,"justice":{"outcome":C.JusticeOutcome.Stale,"tab":0}}
	service.reply(state.ticket,stale);check(service.calls[state.ticket].intent.expected_list_revision==0,"Stale list restart lost initial request")
	service.reply(state.ticket,stale);check(state.phase==State.Phase.Rejected and state.ticket==0,"Stale retry unbounded")
	test_candidates(service,state)
	state.dispose();service.queue_free();await process_frame
	if failures==0:print("JUSTICE_STATE_PASS")
	quit(1 if failures else 0)
