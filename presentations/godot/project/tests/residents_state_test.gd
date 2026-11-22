extends SceneTree
const State=preload("res://scripts/residents_state.gd")
const View=preload("res://scripts/residents_view.gd")
const C=preload("res://scripts/management_contract.gd")
const Owner=preload("res://scripts/residents_panel.gd")
const Shell=preload("res://scripts/fortress_ui.gd")
class MissingCreatureWorld extends RefCounted:
	func inspect_tile(_tile):return [{"kind":1,"id":7}]
	func inspect_entity(_kind,_id):return {}
class Interaction extends Node:
	var construction_active:=false
	var shell_blocked:=false
	var shell_enabled:=true
	var panel:=Control.new()
	func _ready():add_child(panel)
	func cancel_selection():pass
	func set_play_enabled(_value):pass
class Service extends RefCounted:
	signal session_changed
	var next:=0
	var calls: Dictionary={}
	var detached: Array=[]
	func submit(domain: String,request: Dictionary,observer: Callable) -> int:
		next+=1;calls[next]={"domain":domain,"request":request.duplicate(true),"observer":observer};return next
	func detach(ticket: int) -> void:detached.append(ticket)
	func reply(ticket: int,payload: Dictionary) -> void:
		var call: Dictionary=calls[ticket]
		var result:=payload.duplicate(true);result.status=C.ManagementStatus.Ok;result.action=call.request.action
		call.observer.call(ticket,result,call.request)
var failures:=0
func check(value: bool,message: String) -> void:
	if not value:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func sibling_row(kind: int,id: int,inspectable:=true) -> Dictionary:
	return {"kind":kind,"id":id,"first_line":"fixture","second_line":"","can_inspect":inspectable,
		"activity":{"text":"fixture activity","foreground":2,"background":0,"bright":true},
		"pet":{"revision":9,"controls":[{"action":C.PetAction.Adoption,"value":false}]}}
func siblings() -> void:
	var service:=Service.new();var state:=State.new();state.configure(service);state.capacity=2;state.open()
	var residents_ticket:=state.ticket;state.select_tab(1)
	check(service.calls[state.ticket].domain=="creature_list" and service.calls[state.ticket].request.tab==1,"Pets uses the native sibling query")
	service.reply(residents_ticket,{"residents":{"unit_ids":PackedInt32Array([999])}})
	check(state.ids.is_empty(),"Tab replacement retires the resident query")
	service.reply(state.ticket,{"creature_list":{"tab":1,"entries":[{"kind":0,"id":7},{"kind":1,"id":7}]}})
	check(state.ids==PackedInt32Array([7,-8]) and service.calls[state.ticket].request.targets==[{"kind":0,"id":7},{"kind":1,"id":7}],"Typed identities survive equal native IDs")
	service.reply(state.ticket,{"creature_list_rows":{"tab":1,"rows":[sibling_row(0,7),sibling_row(1,7)]}})
	check(state.rows.size()==2 and state.row_at(1).kind==1 and state.row_at(0).activity.caption=="fixture activity","Sibling rows retain typed identity and native activity")
	var inspected: Array[int]=[];state.item_inspect_ready.connect(func(id):inspected.append(id))
	var before:=service.next;state.inspect(-8)
	check(inspected==[7] and service.next==before,"Item sheet handoff never sends a creature-unit request")
	state.pet_action(-8,C.PetAction.Adoption)
	var edit:=state.ticket;var intent: Dictionary=service.calls[edit].request
	check(intent.target=={"kind":1,"id":7} and intent.expected_revision==9 and intent.desired,"Pet edit carries typed identity and observed receipt")
	state.select_tab(2);check(state.tab==1,"Pending mutation blocks tab replacement")
	service.reply(edit,{"pet_edit":{"target":{"kind":1,"id":7},"outcome":C.PetOutcome.Unknown}})
	check(state.phase==State.Phase.Rejected and state.ticket==0 and service.next==edit,"Unknown mutation is not refreshed or replayed")
	state.select_tab(2);var other:=state.ticket;state.select_tab(3)
	service.reply(other,{"creature_list":{"tab":2,"entries":[{"kind":0,"id":999}]}})
	check(state.ids.is_empty(),"Late sibling query cannot enter another tab")
	service.reply(state.ticket,{"creature_list":{"tab":3,"entries":[{"kind":0,"id":7}]}})
	var dead:=sibling_row(0,7,false);dead.erase("pet")
	service.reply(state.ticket,{"creature_list_rows":{"tab":3,"rows":[dead]}})
	before=service.next;state.inspect(7);state.select_sort(C.ResidentsSort.Stress);state.select_sort(C.CreatureListSort.Slaughterability)
	check(service.next==before and not state.row_at(0).can_inspect,"Dead rows suppress sheet navigation and unsupported sorts")
	state.refresh();var pending:=state.ticket;state.close()
	service.reply(pending,{"creature_list":{"tab":3,"entries":[{"kind":0,"id":7}]}})
	check(state.phase==State.Phase.Closed and state.ids.is_empty(),"Closing retires sibling reads")
	state.dispose()
func run() -> void:
	siblings()
	var service:=Service.new();var state:=State.new();state.configure(service);state.capacity=2;state.open()
	var stale:=state.ticket
	state.set_query(PackedByteArray([84,195]))
	check(service.detached.has(stale) and service.calls[state.ticket].request.query_bytes==PackedByteArray([84,195]),"Raw textbox bytes survive replacement")
	service.reply(stale,{"residents":{"unit_ids":PackedInt32Array([999])}})
	check(state.ids.is_empty(),"Late superseded roster cannot publish")
	service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42,7,19,3])}})
	var first_batch:=state.ticket
	check(service.calls[first_batch].request.unit_ids==PackedInt32Array([42,7]),"Rows follow native order")
	state.seek(2,2)
	service.reply(first_batch,{"residents_rows":{"rows":[{"id":42},{"id":7}]}})
	check(service.calls[state.ticket].request.unit_ids==PackedInt32Array([19,3]),"Scroll during read fills current viewport next")
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":19},{"id":3}]}})
	check(state.phase==State.Phase.Ready and state.row_at(2).id==19 and state.rows.size()<=4,"Visible rows become ready without reordering")
	state.select_sort(C.ResidentsSort.Name);state.select_sort(C.ResidentsSort.Name)
	state.select_sort(C.ResidentsSort.Activity);state.select_sort(C.ResidentsSort.Name)
	check(state.directions[C.ResidentsSort.Name] and service.calls[state.ticket].request.descending,"Reselecting inactive header retains direction")
	var old:=state.ticket;service.session_changed.emit()
	service.reply(old,{"residents":{"unit_ids":PackedInt32Array([42])}})
	check(state.phase==State.Phase.Unavailable and state.ids.is_empty() and state.rows.is_empty(),"Session retirement rejects late rows")
	state.open();service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array()}})
	check(state.phase==State.Phase.Ready and state.ticket==0,"Empty native search requires no content request")
	state.refresh();service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42,7])}})
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":7},{"id":42}]}})
	check(state.phase==State.Phase.Rejected and state.rows.is_empty(),"Mismatched row receipt cannot acquire identity authority")
	state.refresh();service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":42,"specialization":{"only_assigned":false,"revision":91}}]}})
	state.specialize(42);var edit_ticket:=state.ticket
	check(state.phase==State.Phase.Applying and service.calls[edit_ticket].request.only_assigned and service.calls[edit_ticket].request.expected_revision==91,"Specialization uses the displayed receipt")
	state.specialize(42);check(state.ticket==edit_ticket,"Pending edit cannot be repeated")
	service.reply(edit_ticket,{"residents_specialization":{"unit_id":42,"outcome":C.ResidentsSpecializationOutcome.Applied,"only_assigned":true}})
	check(state.phase==State.Phase.Reading and service.calls[state.ticket].request.action==C.ManagementAction.ResidentsQuery,"Successful edit refreshes native rows")
	service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":42,"specialization":{"only_assigned":true,"revision":92}}]}})
	state.specialize(42);edit_ticket=state.ticket;state.close()
	service.reply(edit_ticket,{"residents_specialization":{"unit_id":42,"outcome":C.ResidentsSpecializationOutcome.Applied,"only_assigned":false}})
	check(state.phase==State.Phase.Closed and state.ticket==0 and state.rows.is_empty(),"Late edit completion cannot reopen a closed screen")
	state.open();service.reply(state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(state.ticket,{"residents_rows":{"rows":[{"id":42,"activity_target":{"activity_id":50,"event_id":8}}]}})
	state.activity_capacity=44;state.show_activity(42,110)
	var activity_ticket:=state.ticket
	check(service.calls[activity_ticket].domain=="residents_activity" and service.calls[activity_ticket].request.event_id==8,"Activity opens the displayed native event")
	state.resize_activity(80)
	var page: Dictionary={"unit_id":42,"activity_id":50,"event_id":8,"columns":110,"max_y":60,"words":[],"links":[]}
	service.reply(activity_ticket,{"residents_activity":page})
	check(state.phase==State.Phase.ActivityReading and state.activity_page.is_empty(),"Late layout cannot replace resized Activity")
	page.columns=80;service.reply(state.ticket,{"residents_activity":page})
	state.scroll_activity(100,44)
	check(state.phase==State.Phase.ActivityReady and state.activity_first==17,"Activity scroll uses native line extent")
	state.resize_activity(90);activity_ticket=state.ticket;state.close_activity()
	page.columns=90;service.reply(activity_ticket,{"residents_activity":page})
	check(state.phase==State.Phase.Ready and not state.activity_open() and state.row_at(0).id==42,"Close restores roster and retires pending description")
	state.show_activity(42,110);page.columns=110;page.event_id=9
	service.reply(state.ticket,{"residents_activity":page})
	check(state.phase==State.Phase.ActivityRejected and state.activity_page.is_empty(),"Changed event cannot appear under the selected activity")
	state.close_activity();state.show_activity(42,110);activity_ticket=state.ticket
	service.session_changed.emit();page.event_id=8;service.reply(activity_ticket,{"residents_activity":page})
	check(state.phase==State.Phase.Unavailable and not state.activity_open(),"Session replacement retires Activity and late content")
	state.dispose()
	var view:=View.new();view.state=state;view.ticks_override=0
	view.search=LineEdit.new();view.add_child(view.search);root.add_child(view)
	view.size=Vector2(944,708);view.page_rows=2
	var inspected: Array[int]=[]
	var focused: Array[Vector3i]=[]
	view.inspect_requested.connect(func(id):inspected.append(id))
	view.focus_requested.connect(func(tile):focused.append(tile))
	state.ids=PackedInt32Array([7,42]);state.rows={7:{"id":7},42:{"id":42,"position":Vector3i(25,31,4)}};state.first=1;state.phase=State.Phase.Ready
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=Vector2(348,view.list_top()+18);view._gui_input(click)
	check(inspected==[42],"Details uses the scrolled row identity")
	var help=preload("res://scripts/native_hover_view.gd").new();root.add_child(help);help.set_process(false)
	view.hover_help=help;view.pointer_known=true;view.pointer_position=click.position;view.update_hover()
	check(help.state.key=="residents_details","Visible details control claims shared native help")
	view.hide();view.update_hover();check(help.state.key.is_empty(),"Hidden Residents releases its help claim")
	view.show();help.free();view.hover_help=null
	click.position.x=316;view._gui_input(click)
	check(focused==[Vector3i(25,31,4)],"Recenter uses the captured row position")
	state.rows[42].can_inspect=false;click.position.x=348;view._gui_input(click)
	check(inspected==[42] and view.hover_target(click.position).is_empty(),"Absent native sheet control has neither input nor hover target")
	state.rows[42].can_inspect=true
	state.rows[-43]={"kind":1,"id":42};state.ids=PackedInt32Array([42,-43]);view._gui_input(click)
	check(inspected==[42,-43],"Item and unit sheet buttons retain distinct typed identities")
	state.close();view._gui_input(click)
	check(inspected==[42,-43] and focused==[Vector3i(25,31,4)],"Closed rows cannot navigate using retired identity")
	view.free()
	var interaction:=Interaction.new();root.add_child(interaction)
	var host=preload("res://scripts/ui_host.gd").new();host.interaction=interaction;root.add_child(host)
	var owner:=Owner.new();root.add_child(owner);owner.set_process(false)
	owner.panel=Control.new();owner.add_child(owner.panel);owner.ui_host=host;owner.state.configure(service);host.register(owner)
	var navigated: Array=[]
	owner.inspect_requested.connect(func(tile,id):navigated.append([tile,id]))
	owner.open_panel();service.reply(owner.state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(owner.state.ticket,{"residents_rows":{"rows":[{"id":42}]}})
	check(host.active==owner and interaction.construction_active and owner.panel.visible,"Residents owns the modal input gate")
	owner.job_state.configure(service)
	owner.state.rows[42].job_target={"job_id":71,"building_id":3}
	owner._job(42)
	var job_read: int=owner.job_state.ticket
	check(owner.job_open() and not owner.panel.visible and host.active==owner,"Job details retains the roster input owner")
	check(service.calls[job_read].request.job_id==71 and service.calls[job_read].request.building_id==3 and service.calls[job_read].request.unit_id==42,"Job entry uses the displayed row target")
	owner.job_state.close()
	check(owner.panel.visible and owner.state.rows[42].job_target.job_id==71 and host.active==owner,"Closing job details restores the retained roster")
	service.reply(job_read,{"job_settings":{}})
	check(not owner.job_open(),"Retired job read cannot reopen details")
	owner.state.inspect(42);var navigation: int=owner.state.ticket;owner.state.inspect(42)
	check(owner.state.ticket==navigation and service.calls[navigation].domain=="creature_sheet_location","Details has one semantic navigation request")
	service.reply(navigation,{"creature_position":{"unit_id":42,"position":Vector3i(5,6,7)}})
	check(navigated==[[Vector3i(5,6,7),42]],"Owner hands off resolved position and exact identity")
	owner.state.inspect(42);navigation=owner.state.ticket;host.reset_local_views()
	service.reply(navigation,{"creature_position":{"unit_id":42,"position":Vector3i(8,9,10)}})
	check(navigated.size()==1 and not owner.panel.visible and host.active==null and not interaction.construction_active,"Retired owner cannot navigate from a late reply")
	owner.open_panel();service.reply(owner.state.ticket,{"residents":{"unit_ids":PackedInt32Array([42])}})
	service.reply(owner.state.ticket,{"residents_rows":{"rows":[{"id":42}]}})
	owner.focus_requested.connect(func(tile):focused.append(tile))
	owner._focus(Vector3i(11,12,13))
	check(focused[-1]==Vector3i(11,12,13) and host.active==null and not owner.panel.visible,"Recenter closes the roster and releases world input")
	owner.free();host.free();interaction.free()
	var inspector=preload("res://scripts/context_inspector.gd").new()
	inspector.world=MissingCreatureWorld.new();inspector.panel=Panel.new();inspector.add_child(inspector.panel)
	check(not inspector.open_target(Vector3i(1,2,3),1,42,true) and inspector.selected.is_empty(),"Missing exact creature cannot select another tile occupant")
	# This isolated target check deliberately does not run the asset-heavy _ready.
	# Adopt the editor that _ready normally parents before tearing down the owner.
	inspector.customize.add_child(inspector.customize.entry)
	inspector.add_child(inspector.customize);inspector.free();var shell:=Shell.new();shell.free()
	if failures==0:print("RESIDENTS_STATE_PASS")
	quit(1 if failures else 0)
