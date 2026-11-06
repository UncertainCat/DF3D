extends SceneTree
const View=preload("res://scripts/work_details_view.gd")
const Owner=preload("res://scripts/work_details_panel.gd")
const State=preload("res://scripts/work_details_state.gd")
const C=preload("res://scripts/management_contract.gd")
const A=C.ManagementAction
class Service extends RefCounted:
	signal session_changed
	var next:=0
	var calls: Dictionary={}
	var detached: Array=[]
	func submit(domain: String,intent: Dictionary,observer: Callable) -> int:
		next+=1;calls[next]={"domain":domain,"intent":intent.duplicate(true),"observer":observer};return next
	func submit_continuation(_previous: int,domain: String,intent: Dictionary,observer: Callable) -> int:return submit(domain,intent,observer)
	func detach(ticket: int) -> void:detached.append(ticket)
	func reply(ticket: int,payload: Dictionary) -> void:
		var call: Dictionary=calls[ticket];var result:=payload.duplicate(true)
		if not result.has("status"):result.status=C.ManagementStatus.Ok
		result.action=call.intent.action;call.observer.call(ticket,result,call.intent)
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func detail(index: int,revision: int=9007199254740993) -> Dictionary:
	return {"index":index,"revision":revision,"name":"Synthetic detail","editable":true,"mode_editable":true,"mode":3,"assigned_units":PackedInt32Array([7]),"cannot_be_everybody":false}
func page(rows: Array,revision: int=9007199254740995,next: int=0) -> Dictionary:
	return {"citizen":{"details":rows,"detail_list_revision":revision,"next_cursor":next,"external_controller":false}}
func workers(ids: Array) -> Dictionary:return {"residents":{"unit_ids":PackedInt32Array(ids)}}
func complete_workers(service,state,ids: Array) -> void:
	service.reply(state.ticket,workers(ids))
	if state.ticket!=0 and service.calls[state.ticket].intent.action==A.WorkDetailRowsRead:
		var page: Array=[]
		for id in service.calls[state.ticket].intent.unit_ids:page.append({"id":id,"skills":[],"member":id==7})
		service.reply(state.ticket,{"residents_rows":{"rows":page}})
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var service:=Service.new();var state:=State.new();state.configure(service);state.open()
	service.reply(state.ticket,page([detail(0)],9007199254740995,1))
	check(state.details.is_empty() and service.calls[state.ticket].intent.expected_list_revision==9007199254740995,"List pages retain exact receipt and publish atomically")
	service.reply(state.ticket,page([detail(1)],9007199254740995))
	var old:=state.ticket
	check(service.calls[old].intent.expected_revision==9007199254740993,"Selected worker query uses exact detail revision")
	state.select_detail(1);service.reply(old,workers([999]))
	check(state.ids.is_empty() and state.selected.index==1 and service.detached.has(old),"Late query cannot replace another detail")
	complete_workers(service,state,[42,7,19])
	check(state.ids==PackedInt32Array([42,7,19]),"Native worker order is retained")
	state.seek(1,2);check(state.first==1 and state.capacity==2,"Local viewport follows native IDs")
	state.set_query(PackedByteArray([84,195]));old=state.ticket
	check(service.calls[old].intent.query_bytes==PackedByteArray([84,195]),"Partial UTF8 search survives unchanged")
	state.select_sort(C.WorkDetailWorkerSort.Name);service.reply(old,workers([999]))
	complete_workers(service,state,[7,42])
	state.select_sort(C.WorkDetailWorkerSort.Name);state.select_sort(C.WorkDetailWorkerSort.Skills);state.select_sort(C.WorkDetailWorkerSort.Name)
	check(service.calls[state.ticket].intent.descending,"Each header retains its direction")
	complete_workers(service,state,[7,42])
	state.set_member(42,true);old=state.ticket
	check(state.phase==State.Phase.Applying and service.calls[old].intent.unit_id==42 and service.calls[old].intent.expected_revision==9007199254740993,"Membership uses selected detail authority")
	state.set_member(42,true);state.select_detail(0);state.set_mode(2);state.create_detail()
	check(state.ticket==old,"Pending action blocks duplicate and conflicting inputs")
	service.reply(old,{"citizen":{"selected_detail":1}})
	check(service.calls[state.ticket].intent.action==A.WorkDetailList and state.details.is_empty(),"Applied membership refreshes all header receipts")
	service.reply(state.ticket,page([detail(0,11),detail(1,12)],13));complete_workers(service,state,[7,42])
	state.set_mode(1);old=state.ticket
	check(service.calls[old].intent.expected_revision==12 and service.calls[old].intent.mode==1,"Mode uses refreshed authority")
	service.reply(old,{"status":C.ManagementStatus.Rejected,"outcome":"unknown"})
	var count:=service.next;state.create_detail();state.set_mode(1)
	check(state.phase==State.Phase.Rejected and service.next==count and state.selected.is_empty(),"Unknown mutation has no automatic replay or reusable receipt")
	state.open();old=state.ticket;state.close();service.reply(old,page([detail(0)]))
	check(state.phase==State.Phase.Closed and state.details.is_empty(),"Closed owner ignores late list")
	state.open();service.reply(state.ticket,page([]));state.create_detail();old=state.ticket
	check(service.calls[old].intent.action==A.WorkDetailCreate and service.calls[old].intent.expected_revision==9007199254740995,"Empty list can create using list receipt")
	service.reply(old,{"citizen":{"selected_detail":0}});service.reply(state.ticket,page([detail(0)]));complete_workers(service,state,[])
	check(state.phase==State.Phase.Ready and state.ids.is_empty(),"Empty worker list is valid")
	state.refresh();service.reply(state.ticket,page([detail(0)],10,1));service.reply(state.ticket,page([detail(1)],11))
	check(state.phase==State.Phase.Rejected and state.details.is_empty(),"Changed paginated list cannot publish mixed identities")
	state.open();service.reply(state.ticket,page([detail(0)]));old=state.ticket;service.session_changed.emit();service.reply(old,workers([7]))
	check(state.phase==State.Phase.Unavailable and state.ids.is_empty() and state.list_revision==0,"Session retirement clears all authority")
	state.open();service.reply(state.ticket,page([detail(0)]));service.reply(state.ticket,workers([7,42]))
	old=state.ticket
	check(service.calls[old].intent.expected_revision==9007199254740993 and service.calls[old].intent.unit_ids==PackedInt32Array([7,42]),"Visible row request carries exact selected authority and native order")
	state.set_query(PackedByteArray([88]));service.reply(old,{"residents_rows":{"rows":[{"id":7,"skills":[],"member":true},{"id":42,"skills":[],"member":false}]}})
	check(state.rows.is_empty(),"Late content cannot repopulate replaced query")
	service.reply(state.ticket,workers([7,42]));service.reply(state.ticket,{"residents_rows":{"rows":[{"id":42,"skills":[],"member":false},{"id":7,"skills":[],"member":true}]}})
	check(state.phase==State.Phase.Rejected and state.rows.is_empty(),"Reordered content cannot acquire row authority")
	var view:=View.new();root.add_child(view);view.state=state;view.layout(Vector2(1200,800))
	check(view.position==Vector2(32,52) and view.size==Vector2(944,708) and view.list_top()==228 and view.page_rows==10,"Native default Work Details frame geometry")
	check(view.member_rect(0)==Rect2(800,228,32,36) and view.mode_rect(1)==Rect2(584,156,184,36),"Native membership and mode geometry")
	state.phase=State.Phase.Ready
	for entry in [[0,"name"],[2,"profession"],[3,"skills"]]:
		check(view.hover_target(Vector2(View.DETAIL_SORT_X[entry[0]]*8+4,view.list_top()-18)).get("widget")==entry[1],"Captured sort header has its native widget help")
	var help:=preload("res://scripts/native_hover_view.gd").new()
	help.enter_work_detail_widget(10,"name");check(help.displayed=="detail_widget_name","Widget help activates independently of main hover delay")
	help.enter_work_detail_widget(11,"skills");help.leave(10)
	check(help.displayed=="detail_widget_skills","Late departure cannot retire another widget owner")
	help.enter_owner_filter(11);check(help.displayed=="owner_filter","Filter replaces sort help for the same owner")
	help.leave(11);check(help.displayed.is_empty(),"Owner departure retires widget overlay")
	help.free()
	state.phase=State.Phase.Ready;state.editing_settings=true;state.settings=settings_page().work_detail_settings
	state.details=[{"icon":0,"labors":PackedInt32Array([1])},{"icon":1,"labors":PackedInt32Array([1])}]
	# Synthetic catalog has12 categories followed by labor1; both badges are
	# visible on row12 and must share the actual rendering geometry.
	var icon_y:=view.settings_rect(12).position.y
	check(view.hover_target(Vector2(856,icon_y+18)).get("staff")=="work_detail" and view.hover_target(Vector2(824,icon_y+18)).get("staff")=="work_detail","Every visible settings badge has native work-detail help")
	check(view.hover_target(Vector2(888,icon_y+18)).is_empty() and view.hover_target(Vector2(500,icon_y+18)).is_empty(),"Settings checkbox and labor caption do not invent help")
	state.seek_settings(13,view.settings_capacity());check(view.hover_target(Vector2(856,view.settings_top()+18)).is_empty(),"Scrolled-out settings badge cannot retain hover authority")
	state.settings_first=0;state.phase=State.Phase.Applying;check(view.hover_target(Vector2(856,icon_y+18)).is_empty(),"Pending mutation retires settings help")
	view.state=null;view.queue_free();await process_frame
	state.open();service.reply(state.ticket,page([detail(0)]));complete_workers(service,state,[7])
	state.open_settings();old=state.ticket
	check(state.editing_settings and service.calls[old].intent.action==A.WorkDetailSettingsRead and state.rows.is_empty(),"Settings replaces roster observations with a revision-bound read")
	state.close_settings();service.reply(old,settings_page())
	check(state.settings.is_empty() and not state.editing_settings,"Done retires a late settings read")
	service.reply(state.ticket,page([detail(0)]));complete_workers(service,state,[7]);state.open_settings();service.reply(state.ticket,settings_page())
	state.seek_settings(30,15);state.toggle_setting(-2);old=state.ticket
	check(service.calls[old].intent.setting_id==-2 and service.calls[old].intent.expected_revision==9007199254740993,"Group toggle uses exact displayed receipt")
	state.toggle_setting(11);state.close_settings();state.set_mode(2)
	check(state.ticket==old and state.editing_settings,"Pending toggle blocks conflicting edits and Done")
	service.reply(old,settings_page(9007199254740997));check(service.calls[state.ticket].intent.action==A.WorkDetailList,"Toggle refreshes definition header authority")
	service.reply(state.ticket,page([detail(0,9007199254740997)],9007199254740999))
	check(service.calls[state.ticket].intent.action==A.WorkDetailSettingsRead,"Settings remains open across definition refresh")
	service.reply(state.ticket,settings_page(9007199254740997));check(state.settings_first==30,"Toggle retains settings scroll")
	state.close_settings();service.reply(state.ticket,page([detail(0,9007199254740997)]));complete_workers(service,state,[7])
	check(not state.editing_settings and state.phase==State.Phase.Ready,"Done returns to authoritative roster")
	state.open_settings();service.reply(state.ticket,settings_page(9007199254740997));state.toggle_setting(11);old=state.ticket
	service.reply(old,{"outcome":"unknown","status":C.ManagementStatus.Rejected});count=service.next;state.toggle_setting(11)
	check(state.settings.is_empty() and service.next==count,"Unknown settings mutation drops authority and cannot replay")
	state.close();service.reply(old,settings_page(9007199254740999));check(state.settings.is_empty() and not state.editing_settings,"Closed settings ignore late mutation receipt")
	state.open();service.reply(state.ticket,page([detail(0)]));complete_workers(service,state,[])
	state.open_settings();service.reply(state.ticket,settings_page());count=service.next;state.reset_settings()
	check(service.next==count,"Custom detail cannot Reset")
	state.settings.no_modify=true;state.seek_settings(20,15);state.reset_settings();old=state.ticket
	check(service.calls[old].intent.action==A.WorkDetailEdit and service.calls[old].intent.edit==3 and service.calls[old].intent.expected_revision==9007199254740993,"Reset uses displayed settings authority")
	state.reset_settings();state.close_settings();check(state.ticket==old and state.editing_settings,"Pending Reset blocks repeated Reset and Done")
	service.reply(old,{"citizen":{"selected_detail":0}});service.reply(state.ticket,page([detail(0,55)]));service.reply(state.ticket,settings_page(55))
	check(state.editing_settings and state.settings_first==20 and state.phase==State.Phase.Ready,"Reset refreshes settings without leaving the editor or losing scroll")
	state.settings.no_modify=true;count=service.next;state.delete_detail();check(service.next==count,"Built-in detail cannot Delete")
	state.settings.no_modify=false;state.delete_detail();old=state.ticket
	check(service.calls[old].intent.action==A.WorkDetailDelete and service.calls[old].intent.expected_revision==55 and not state.editing_settings,"Delete consumes displayed receipt and leaves settings")
	state.delete_detail();state.create_detail();check(state.ticket==old,"Pending Delete blocks duplicate and conflicting writes")
	service.reply(old,{"citizen":{"selected_detail":0}});service.reply(state.ticket,page([detail(0,57)]));complete_workers(service,state,[])
	check(state.selected.index==0 and state.roster_ready and not state.editing_settings,"Delete returns to first detail roster")
	var naming=preload("res://scripts/work_detail_name_session.gd").new();root.add_child(naming);naming.configure(service,detail(0,57))
	naming.edit("First");old=naming.ticket;naming.edit("Second");naming.finish()
	check(naming.ticket==old and service.calls[old].intent.name=="First","Typing buffers behind one exact rename request")
	var renamed:=detail(0,59);renamed.name="First";service.reply(old,{"citizen":{"details":[renamed]}})
	check(service.calls[naming.ticket].intent.name=="Second" and service.calls[naming.ticket].intent.expected_revision==59,"Buffered typing uses confirmed rename receipt")
	renamed=detail(0,61);renamed.name="Second";service.reply(naming.ticket,{"citizen":{"details":[renamed]}})
	check(naming.stopped,"Finishing waits for buffered explicit typing")
	naming=preload("res://scripts/work_detail_name_session.gd").new();root.add_child(naming);naming.configure(service,detail(0,61));naming.edit("First");old=naming.ticket;naming.edit("Second");count=service.next
	service.reply(old,{"status":C.ManagementStatus.Rejected,"outcome":"unknown"})
	check(naming.stopped and naming.snapshot.is_empty() and service.next==count,"Uncertain rename discards buffered typing without replay")
	await process_frame
	state.dispose()
	if failures==0:print("WORK_DETAILS_STATE_PASS")
	quit(0 if failures==0 else 1)

func settings_page(revision: int=9007199254740993) -> Dictionary:
	var catalog: Array=[]
	for id in range(-13,-1):catalog.append({"id":id,"caption":"Synthetic category"})
	for id in range(1,80):catalog.append({"id":id,"caption":"Synthetic labor"})
	return {"work_detail_settings":{"detail_index":0,"revision":revision,"editable":true,"no_modify":false,"labors":PackedInt32Array(),"catalog":catalog}}
