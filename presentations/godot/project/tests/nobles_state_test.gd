extends SceneTree
const View=preload("res://scripts/nobles_view.gd")
const State=preload("res://scripts/nobles_state.gd")
const C=preload("res://scripts/management_contract.gd")
const Service=preload("res://tests/work_details_state_test.gd").Service
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func row(assignment: int) -> Dictionary:
	return {"draft_slot":0,"entity_id":7,"position_id":2,"assignment_id":assignment,"unit_id":-1,"nemesis_id":-1,"priority":0,"title":"fixture","squad_caption":"","holder_caption":"fixture","can_appoint":true,"has_room_assessment":false,"required_rooms":[0,0,0,0],"actual_rooms":[0,0,0,0],"required_furniture":[0,0,0,0],"actual_furniture":[0,0,0,0],"demand_status":-1,"mandate_status":-1}
func page(ids: Array=[-1],total:=1,offset:=0,revision:=9007199254740993) -> Dictionary:
	return {"nobles":{"outcome":C.NoblesOutcome.None,"list_revision":revision,"total":total,"offset":offset,"rows":ids.map(func(id):return row(id))}}
func stale() -> Dictionary:
	return {"status":C.ManagementStatus.Rejected,"nobles":{"outcome":C.NoblesOutcome.Stale,"list_revision":0,"total":0,"offset":0,"rows":[]}}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();root.add_child(service);var state:=State.new();state.configure(service);state.open()
	service.reply(state.ticket,page([-1],2));check(state.phase==State.Phase.Reading and state.rows.is_empty(),"Partial Nobles list exposed")
	check(service.calls[state.ticket].intent.offset==1 and service.calls[state.ticket].intent.expected_list_revision==9007199254740993,"Continuation lost exact identity")
	service.reply(state.ticket,page([42],2,1));check(state.phase==State.Phase.Ready and state.rows.size()==2,"NEW and assigned office conflated")
	state.seek(99,1);check(state.first==1,"Nobles scroll unbounded")
	state.refresh();var old: int=state.ticket;state.open();var current: int=state.ticket
	service.reply(old,page([99]));check(state.ticket==current and service.detached.has(old) and state.rows.is_empty(),"Reopened controller accepted retired reply")
	state.close();service.reply(current,page());check(state.phase==State.Phase.Closed and state.rows.is_empty(),"Closed controller accepted late reply")
	state.open();old=state.ticket;service.session_changed.emit();service.reply(old,page());check(state.phase==State.Phase.Unavailable and state.rows.is_empty(),"Epoch change accepted old rows")
	state.open();service.reply(state.ticket,page([-1],2));service.reply(state.ticket,stale())
	check(service.calls[state.ticket].intent.offset==0 and service.calls[state.ticket].intent.expected_list_revision==0,"Stale continuation did not restart")
	service.reply(state.ticket,stale());check(state.phase==State.Phase.Rejected and state.ticket==0,"Stale retry unbounded")
	for fault in 7:
		state.open();service.reply(state.ticket,page([-1],2));var second:=page([42],2,1)
		match fault:
			0:second.nobles.rows[0].assignment_id=-1
			1:second.nobles.list_revision+=1
			2:second.nobles.rows=[]
			3:second.nobles.rows[0].actual_rooms=[1,2,3]
			4:second.nobles.rows[0].has_room_assessment=true
			5:second.nobles.rows[0].mandate_status=0
			6:second.nobles.total=3
		service.reply(state.ticket,second);check(state.phase==State.Phase.Rejected and state.rows.is_empty(),"Invalid Nobles page accepted: %d"%fault)
	for fault in 3:
		state.open();var portrait_page:=page()
		var holder: Dictionary=portrait_page.nobles.rows[0]
		holder.unit_id=10 if fault!=1 else -1;holder.has_room_assessment=fault!=1
		holder.appearance={"tile_pages":["fixture"],"palettes":[],"layers":[[0,0,0,1,1,65535,0,0,0,0]]}
		if fault==2:holder.appearance.layers[0][0]=1
		service.reply(state.ticket,portrait_page)
		check(state.phase==(State.Phase.Ready if fault==0 else State.Phase.Rejected),"Nobles holder recipe validation differs")
	state.open();service.reply(state.ticket,page([],0));check(state.phase==State.Phase.Ready and state.rows.is_empty(),"Empty Nobles list rejected")
	state.refresh();old=state.ticket;var submitted: int=service.next;service.reply(old,{"outcome":"unknown"})
	check(state.phase==State.Phase.Rejected and service.next==submitted,"Uncertain read replayed automatically")
	state.open();service.reply(state.ticket,page())
	var target: Dictionary=state.office(state.rows[0]);state.begin_appointment(target);old=state.ticket
	state.cancel_appointment();service.reply(old,{"outcome":"unknown"})
	check(state.phase==State.Phase.Ready and state.rows.size()==1 and state.choices.is_empty(),"Cancelled picker accepted late reply")
	state.begin_appointment(target)
	var candidate: Dictionary={"unit_id":10,"value":42,"caption":"fixture","no_skills":"fixture","skills":[]}
	var candidate_page: Dictionary={"nobles":{"outcome":C.NoblesOutcome.None,"list_revision":9007199254740993,"target":target,"candidate_revision":9007199254740995,"total":2,"offset":0,"candidates":[candidate]}}
	service.reply(state.ticket,candidate_page)
	check(state.phase==State.Phase.CandidatesReading and state.candidates.is_empty(),"Partial picker exposed")
	check(service.calls[state.ticket].intent.expected_candidate_revision==9007199254740995,"Candidate revision lost precision")
	candidate_page.nobles.offset=1;candidate_page.nobles.candidates=[{"unit_id":-1,"value":0,"caption":"fixture","no_skills":"","skills":[]}]
	service.reply(state.ticket,candidate_page)
	check(state.phase==State.Phase.CandidatesReady and state.candidates.size()==2,"Candidate list not published")
	state.choose_candidate(999);check(state.phase==State.Phase.CandidatesReady,"Unlisted candidate selected")
	state.choose_candidate(10);var draft_intent: Dictionary=service.calls[state.ticket].intent
	check(state.phase==State.Phase.Reading and draft_intent.choices==[{"target":target,"expected_unit_id":-1,"unit_id":10}] and draft_intent.expected_list_revision==9007199254740993,"Draft selection lost target or base")
	var draft_page:=page([-1,-1],2);draft_page.nobles.rows[1].draft_slot=1
	service.reply(state.ticket,draft_page)
	check(state.phase==State.Phase.Ready and state.rows.size()==2,"Distinct NEW slots conflated")
	state.refresh();check(state.ticket==0 and state.choices.size()==1,"Refresh discarded pending draft")
	state.begin_appointment(state.office(state.rows[1]));candidate_page.nobles.target=state.office(state.rows[1]);candidate_page.nobles.offset=0;candidate_page.nobles.total=1
	service.reply(state.ticket,candidate_page);state.choose_candidate(-1);submitted=service.next
	service.reply(state.ticket,stale())
	check(state.phase==State.Phase.Rejected and state.choices.size()==2 and service.next==submitted,"Stale draft silently rebased or discarded")
	state.close();check(state.choices.is_empty() and state.candidates.is_empty(),"Closed draft retained owned data")
	var dismissals: Array=[];state.dismissed.connect(func():dismissals.append(true))
	for outcome in ["applied","rejected","unknown","malformed"]:
		state.open();service.reply(state.ticket,page())
		state.choices=[{"target":target,"expected_unit_id":-1,"unit_id":10}]
		state.request_dismiss();var commit: int=state.ticket;submitted=service.next
		state.request_dismiss();check(state.phase==State.Phase.Applying and service.next==submitted,"Repeated dismissal resubmitted mutation")
		check(service.calls[commit].intent.action==C.ManagementAction.NoblesCommit,"Dismissal did not commit draft")
		var result: Dictionary={"nobles":{"outcome":C.NoblesOutcome.Applied}}
		if outcome=="rejected":result={"status":C.ManagementStatus.Rejected,"nobles":{"outcome":C.NoblesOutcome.Stale}}
		elif outcome=="unknown":result={"outcome":"unknown"}
		elif outcome=="malformed":result={}
		service.reply(commit,result)
		check(state.phase==(State.Phase.Closed if outcome=="applied" else State.Phase.Rejected if outcome=="rejected" else State.Phase.Unknown),"Dismissal outcome misclassified: "+outcome)
		state.request_dismiss();check(service.next==submitted,"Failed dismissal replayed automatically")
	check(dismissals.size()==1,"Non-applied mutation granted dismissal")
	state.dispose();state.open();check(state.phase==State.Phase.Unavailable,"Missing service retained rows")
	var view:=View.new();view.state=state;view.size=Vector2(944,708)
	check(view.list_top()==108 and view.capacity()==16 and view.status_x()==496,"Nobles native geometry differs")
	check(view.groups()[1][0]=="Nobles and administrators","Nobles selected header row differs")
	check(view.room_suffix(0,0)=="NA" and view.room_suffix(1,0)=="MISSING" and view.room_suffix(2,1)=="PARTIAL" and view.room_suffix(1,1)=="GOOD","Nobles room artwork mapping differs")
	view.size=Vector2(1344,804);view.wide_tabs=true
	check(view.status_x()==680 and view.list_top()==84,"Nobles wide native status spacing differs")
	var part={"actual":"fixture","required":"fixture","color":15}
	var help={"description":"fixture description","rooms":[part,part,part,part],"furniture":[part,part,part,part],"demands":[],"mandates":[{"text":"fixture mandate","color":6}],"accounting":{"setting":2,"level":1,"title":"fixture title","examples":"fixture examples","attained":"fixture attained","progress":""}}
	check(state._help_bytes(help,true)>0 and state._help_bytes(help,false)==-1,"Nobles holder help accepted on vacancy")
	var bad: Dictionary=help.duplicate(true);bad.rooms[0].color=6
	check(state._help_bytes(bad,true)==-1,"Nobles room help accepted obligation-only color")
	bad=help.duplicate(true);bad.accounting.setting=5
	check(state._help_bytes(bad,true)==-1,"Nobles accounting setting unbounded")
	var holder:=row(42);holder.unit_id=10;holder.has_room_assessment=true;holder.help=help
	state.configure(service);state.rows=[holder];state.phase=State.Phase.Ready
	view.hovered=view.hover_at(Vector2(view.status_x()+56,view.list_top()+18))
	check(view.hovered.get("kind")=="rooms" and view.intro_lines().size()==8,"Nobles room hover omitted assessment text")
	check(view.hover_at(Vector2(24,view.list_top()+18)).get("kind")=="description","Nobles description hitbox excludes native left row")
	check(view.hover_at(Vector2(view.status_x()+320,view.list_top()+18)).get("kind")=="accounting","Nobles accounting hover missing")
	check(view.hover_at(Vector2(0,0)).is_empty(),"Nobles hover retained outside row")
	state._revision=123;state.choices=[{"target":target,"expected_unit_id":-1,"unit_id":10}]
	state.set_accounting(state.office(holder),4);var accounting_ticket: int=state.ticket;submitted=service.next
	state.set_accounting(state.office(holder),3);state.request_dismiss()
	check(state.phase==State.Phase.Accounting and service.next==submitted,"Accounting allowed overlapping writes")
	check(service.calls[accounting_ticket].intent.expected_setting==2 and service.calls[accounting_ticket].intent.setting==4 and service.calls[accounting_ticket].intent.choices==state.choices,"Accounting lost setting authority or draft")
	service.reply(accounting_ticket,{"nobles":{"outcome":C.NoblesOutcome.Applied}})
	check(state.phase==State.Phase.Reading and state.choices.size()==1 and service.calls[state.ticket].intent.expected_list_revision==123,"Accounting application discarded appointment draft")
	state.close()
	state.close();check(view.hover_at(Vector2(24,view.list_top()+18)).is_empty(),"Retired Nobles data retained hover")
	var interaction=preload("res://tests/ui_host_test.gd").Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner=preload("res://scripts/nobles_panel.gd").new();root.add_child(owner);owner.state.configure(service);host.register(owner)
	var destination=preload("res://tests/ui_host_test.gd").View.new();root.add_child(destination);host.register(destination)
	for outcome in ["applied","unknown","reset"]:
		owner.open_panel();service.reply(owner.state.ticket,page())
		owner.state.choices=[{"target":target,"expected_unit_id":-1,"unit_id":10}]
		destination.open_panel();var commit: int=owner.state.ticket
		check(host.active==owner and not destination.panel.visible and owner.state.phase==State.Phase.Applying,"Host switched before appointment receipt")
		submitted=service.next;destination.open_panel();check(service.next==submitted,"Repeated handoff resubmitted appointment")
		if outcome=="reset":host.reset_local_views()
		service.reply(commit,{"outcome":"unknown"} if outcome=="unknown" else {"nobles":{"outcome":C.NoblesOutcome.Applied}})
		check((host.active==destination and destination.panel.visible) if outcome=="applied" else (host.active==owner if outcome=="unknown" else host.active==null),"Handoff ignored mutation outcome or teardown")
		destination.close_panel();owner.close_panel()
	owner.free();destination.free();host.free();interaction.free()
	view.free();state.dispose();service.queue_free();await process_frame
	if failures==0:print("NOBLES_STATE_PASS")
	quit(1 if failures else 0)
