extends SceneTree
const State=preload("res://scripts/depot_goods_state.gd")
const C=preload("res://scripts/management_contract.gd")
class Service extends Node:
	signal session_changed
	var next:=0
	var calls: Dictionary={}
	var detached: Array=[]
	func submit(domain: String,intent: Dictionary,observer: Callable) -> int:
		next+=1;calls[next]={"domain":domain,"intent":intent.duplicate(true),"observer":observer};return next
	func detach(ticket: int) -> void:detached.append(ticket)
	func reply(ticket: int,payload: Dictionary) -> void:
		var call: Dictionary=calls[ticket]
		call.observer.call(ticket,{"status":C.ManagementStatus.Ok,"action":call.intent.action,"depot_goods":payload},call.intent)
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func snapshot(category: int=-1) -> Dictionary:
	return {"depot_id":7,"revision":9007199254740993,"appraisal":0,"category":category,"categories":[{"type":45,"caption":"Synthetic anvils"}],"groups":[] if category==-1 else [{"subtype":-1,"subcat1":0,"subcat2":1,"amount":2,"caption":"Synthetic group","matches":true,"expanded":true,"flags":0,"item_ids":[11,12],"container_counts":[0,0]}],"items":[]}
func ready(service,state) -> void:
	service.reply(state.ticket,snapshot())
	service.reply(state.ticket,snapshot(45))
func commit_reply(service,ticket: int,outcome: int,patch: Dictionary={}) -> void:
	var call: Dictionary=service.calls[ticket]
	var intent: Dictionary=call.intent
	var receipt: Dictionary={"depot_id":intent.depot_id,"expected_revision":intent.expected_revision,"observed_revision":intent.expected_revision-1 if outcome==C.DepotGoodsCommitOutcome.Stale else intent.expected_revision,"outcome":outcome}
	receipt.merge(patch,true)
	call.observer.call(ticket,{"status":C.ManagementStatus.Ok,"action":intent.action,"depot_commit":receipt},intent)
func drafts(service,state) -> void:
	state.open(7);ready(service,state);state.request_items([11,12])
	var value:=snapshot(45);value.groups[0].flags=2
	value.items=[{"id":11,"caption":"Synthetic first","distance":8,"value":20,"tag":0,"prohibited":false,"value_caption":""},{"id":12,"caption":"Synthetic second","distance":9,"value":20,"tag":0,"prohibited":false,"value_caption":""}]
	service.reply(state.ticket,value)
	state.toggle_item(12)
	var intent: Dictionary=service.calls[state.ticket].intent
	check(intent.draft==[{"id":12,"desired":true}] and intent.sort_draft.is_empty() and intent.expected_revision==value.revision,"Individual draft retains initial native sort basis and exact source")
	value.items[1].tag=1;service.reply(state.ticket,value)
	state.toggle_group(0);intent=service.calls[state.ticket].intent
	check(intent.draft.size()==2 and intent.draft.all(func(row):return row.desired) and intent.sort_draft.is_empty(),"Mixed group selects all native members without re-sorting")
	value.items[0].tag=1;value.groups[0].flags=1;service.reply(state.ticket,value)
	state.set_query("IRON");intent=service.calls[state.ticket].intent
	check(intent.draft.size()==2 and intent.sort_draft.is_empty(),"Search retains checkbox choices and last sorting basis")
	value.items=[];value.categories.append({"type":17,"caption":"Synthetic bags"});service.reply(state.ticket,value)
	state.select_category(17);intent=service.calls[state.ticket].intent
	check(intent.draft==intent.sort_draft and intent.draft.size()==2,"Category navigation sorts using retained cross-category choices")
	var other:=snapshot(17);other.categories=value.categories;other.groups=[];service.reply(state.ticket,other)
	state.select_category(45);service.reply(state.ticket,value)
	state.toggle_all();intent=service.calls[state.ticket].intent
	check(intent.draft.all(func(row):return not row.desired) and intent.sort_draft.all(func(row):return row.desired),"Select All clears selected matching groups while retaining navigation order")
	state.finish();var count: int=service.next
	check(state.phase==State.Phase.Reading and service.next==count,"Finish waits for the outstanding projection")
	value.groups[0].flags=2;service.reply(state.ticket,value)
	check(state.phase==State.Phase.Applying and service.calls[state.ticket].intent.changes.all(func(row):return not row.desired),"Finish commits one complete draft after projection")
	commit_reply(service,state.ticket,C.DepotGoodsCommitOutcome.Applied)
	check(state.phase==State.Phase.Closed,"Draft close waits for confirmed application")
	state.open(7);ready(service,state);state.toggle_group(0)
	value=snapshot(45);value.revision+=1;service.reply(state.ticket,value)
	check(state.phase==State.Phase.Rejected and state.ticket==0,"Changed source cannot silently rebase a retained draft")
func commits(service,state) -> void:
	state.open(7);ready(service,state)
	var changes: Array=[{"id":11,"desired":true},{"id":12,"desired":false}]
	var original: int=state.revision;var count: int=service.next
	check(not state.commit_and_close(original-1,changes),"Draft revision cannot be silently rebased")
	for invalid in [[],[changes[0],changes[0]],[{"id":11,"desired":1}],[{"id":-1,"desired":true}]]:
		check(not state.commit_and_close(original,invalid),"Malformed draft must remain unsent")
	check(service.next==count and state.phase==State.Phase.Ready,"Invalid drafts leave ready source intact")
	check(state.commit_and_close(original,changes),"Valid draft submits")
	var pending: int=state.ticket
	changes[0].desired=false
	check(service.calls[pending].intent.changes[0].desired and service.calls[pending].intent.expected_revision==9007199254740993,"Commit owns a precise immutable draft")
	state.set_query("ignored");state.select_category(45);state.request_items([11])
	check(not state.commit_and_close(original,changes) and state.ticket==pending and state.phase==State.Phase.Applying,"Pending commit disables reads and duplicate submissions")
	commit_reply(service,pending,C.DepotGoodsCommitOutcome.Applied)
	check(state.phase==State.Phase.Closed and state.depot_id==-1,"Confirmed application closes picker")
	for outcome in [C.DepotGoodsCommitOutcome.Rejected,C.DepotGoodsCommitOutcome.Stale,C.DepotGoodsCommitOutcome.Unknown]:
		state.open(7);ready(service,state);state.commit_and_close(state.revision,changes);pending=state.ticket
		commit_reply(service,pending,outcome)
		var expected: int={C.DepotGoodsCommitOutcome.Rejected:State.Phase.Rejected,C.DepotGoodsCommitOutcome.Stale:State.Phase.Stale,C.DepotGoodsCommitOutcome.Unknown:State.Phase.Unknown}[outcome]
		check(state.phase==expected and not state.groups.is_empty(),"Unsuccessful commit keeps disabled source without retry")
		count=service.next;check(not state.commit_and_close(original,changes) and service.next==count,"Terminal commit cannot replay")
	state.open(7);ready(service,state);state.commit_and_close(state.revision,changes);pending=state.ticket
	commit_reply(service,pending,C.DepotGoodsCommitOutcome.Applied,{"depot_id":8})
	check(state.phase==State.Phase.Unknown,"Mismatched success receipt is uncertain, never successful")
	state.open(7);ready(service,state);state.commit_and_close(state.revision,changes);pending=state.ticket
	state.close();state.open(8);var replacement: int=state.ticket
	commit_reply(service,pending,C.DepotGoodsCommitOutcome.Applied)
	check(service.detached.has(pending) and state.depot_id==8 and state.ticket==replacement and state.phase==State.Phase.Reading,"Late success cannot close a replacement picker")
	state.open(7);ready(service,state);state.commit_and_close(state.revision,changes);pending=state.ticket
	service.session_changed.emit();commit_reply(service,pending,C.DepotGoodsCommitOutcome.Applied)
	check(state.phase==State.Phase.Unavailable and state.depot_id==-1,"Session replacement retires pending commit ownership")
func expansion(service,state) -> void:
	state.open(7);ready(service,state);var count: int=service.next
	state.toggle_expansion(0)
	check(state.row_count()==1 and state.page(0,10).size()==1 and service.next==count,"Group collapse is local and hides only member rows")
	state.set_query("IRON");var value:=snapshot(45);service.reply(state.ticket,value)
	check(not state.groups[0].expanded and state.row_count()==1,"Search retains current group collapse")
	state.toggle_group(0);service.reply(state.ticket,value)
	check(not state.groups[0].expanded,"Checkbox projection retains current group collapse")
	state.set_query("");value.categories.append({"type":17,"caption":"Synthetic bags"});service.reply(state.ticket,value)
	state.select_category(17);var other:=snapshot(17);other.categories=value.categories;other.groups=[];service.reply(state.ticket,other)
	state.select_category(45);service.reply(state.ticket,value)
	check(state.groups[0].expanded and state.row_count()==3,"Category return restores native expansion default")
func _initialize() -> void:call_deferred("run")
func containers(service,state) -> void:
	state.open(7);ready(service,state);state.set_query("containers")
	var value:=snapshot(45);value.groups[0].container_counts=[3,0]
	value.categories.append({"type":17,"caption":"Synthetic bags"})
	service.reply(state.ticket,value)
	var calls: int=service.next
	state.toggle_container(11)
	check(state.row_count()==6 and state.page(2,2)==[{"parent_id":11,"child_index":0},{"parent_id":11,"child_index":1}] and service.next==calls,"Container expansion is local and adds direct-child slots")
	state.toggle_item(21);check(service.next==calls,"Contained item cannot become a hauling draft")
	state.request_contents(11,1,2)
	var intent: Dictionary=service.calls[state.ticket].intent
	check(intent.expected_revision==value.revision and intent.container_id==11 and intent.container_offset==1 and intent.container_limit==2,"Child page is bound to exact source")
	var content: Dictionary=value.duplicate(true)
	content.container={"parent_id":11,"offset":1,"total":3,"items":[{"id":21,"type":2,"contained_count":0,"value":42,"prohibited":false,"caption":"Synthetic child","value_caption":""},{"id":22,"type":0,"contained_count":0,"value":11,"prohibited":false,"caption":"Synthetic bar","value_caption":""}]}
	service.reply(state.ticket,content)
	check(state.phase==State.Phase.Ready and state.contained_item(11,1).id==21 and state.contained_item(11,0).is_empty() and state.item_type(21)==2,"Child page retains offset and semantic artwork type")
	calls=service.next;state.request_contents(11,1,2);check(service.next==calls,"Cached child page is not fetched again")
	state.appearances[21]={"synthetic":true};state.retain_contents([])
	check(state.contained_item(11,1).is_empty() and not state.appearances.has(21),"Offscreen child data and artwork are released")
	state.request_appearances([21]);check(service.next==calls,"Retired child cannot request artwork without a current page")
	state.set_query("");service.reply(state.ticket,value)
	check(state.row_count()==6 and state.contained_item(11,1).is_empty(),"Search retains expansion while refreshing child details")
	state.select_category(17);var other:=snapshot(17);other.groups=[];other.categories=value.categories;service.reply(state.ticket,other)
	state.select_category(45);service.reply(state.ticket,value)
	check(state.row_count()==6,"Category navigation retains container expansion")
	state.request_contents(11,1,2);var pending: int=state.ticket;state.close();service.reply(pending,content)
	check(state.phase==State.Phase.Closed and state._container_expanded.is_empty() and state._contents.is_empty(),"Close retires pending child pages")
	for fault in ["parent","offset","count","source"]:
		state.open(7);ready(service,state);state.set_query("containers");service.reply(state.ticket,value);state.request_contents(11,1,2)
		var invalid: Dictionary=content.duplicate(true)
		if fault=="parent":invalid.container.parent_id=12
		if fault=="offset":invalid.container.offset=0
		if fault=="count":invalid.container.items.pop_back()
		if fault=="source":invalid.revision+=1
		service.reply(state.ticket,invalid)
		check(state.phase==State.Phase.Rejected and state._contents.is_empty(),"Mismatched child page must retire source: "+fault)
func run() -> void:
	var service:=Service.new();root.add_child(service)
	var state:=State.new();state.configure(service);state.open(7)
	check(service.calls[state.ticket].domain=="depot_goods","Reads use semantic depot domain")
	ready(service,state)
	check(state.phase==State.Phase.Ready and state.revision==9007199254740993,"Catalog selects first native category without losing revision precision")
	check(state.row_count()==3 and state.page(1,2)==[{"id":11},{"id":12}],"Expanded rows retain native membership order")
	check(state.page(2,1)==[{"id":12}] and state.page(3,2).is_empty(),"Viewport bounds omit preceding and trailing rows")
	state.request_items([11]);var intent: Dictionary=service.calls[state.ticket].intent
	check(intent.item_ids==[11] and state.groups.is_empty(),"Detail read retires old source")
	var value:=snapshot(45);value.items=[{"id":11,"caption":"Synthetic item","distance":8,"value":20,"tag":2,"prohibited":false,"value_caption":""}]
	service.reply(state.ticket,value)
	check(state.items.has(11),"Requested native detail is published")
	var count: int=service.next;state.request_items([11]);state.request_items([999]);state.request_items([12,12])
	check(service.next==count,"Cached, foreign and duplicate detail requests do not submit")
	state.request_appearances([11]);var artwork_ticket: int=service.next
	check(service.calls[artwork_ticket].domain=="production" and service.calls[artwork_ticket].intent.independent_item and service.calls[artwork_ticket].intent.item_id==11,"Artwork reuses owned item inspection")
	service.reply(artwork_ticket,{})
	check(state.appearances.has(11) and state.appearances[11].is_empty() and not state.appearance_pending(),"Rejected artwork remains absent")
	state.request_appearances([11]);check(service.next==artwork_ticket,"Absent artwork does not loop on rejected reads")
	state.set_query("I");state.set_query("IR");state.set_query("IRON")
	for query in ["I","IR","IRON"]:
		check(service.calls[state.ticket].intent.query==query,"Queued query preserves input order")
		service.reply(state.ticket,snapshot(45))
	check(state.phase==State.Phase.Ready and state.query=="IRON","Search settles after final native response")
	state.set_options(true,true,true);value=snapshot(45);value.categories=[];value.groups[0].item_ids=[];value.groups[0].container_counts=[]
	service.reply(state.ticket,value)
	check(state.category==45 and state.row_count()==0 and state.page(0,10).is_empty(),"Exclusion retains selected category but native empty-item gate hides groups")
	state.set_query("");var old: int=state.ticket;state.close();service.reply(old,snapshot(45))
	check(service.detached.has(old) and state.phase==State.Phase.Closed and state.groups.is_empty(),"Close retires late replies")
	state.open(7);old=state.ticket;service.session_changed.emit();service.reply(old,snapshot())
	check(state.phase==State.Phase.Unavailable and state.depot_id==-1,"Session replacement retires source ownership")
	state.open(7);ready(service,state);state.request_items([11]);value=snapshot(45)
	service.reply(state.ticket,value)
	check(state.phase==State.Phase.Rejected and state.revision==0 and state.groups.is_empty(),"Missing requested detail rejects without stale data")
	state.open(7);ready(service,state);state.set_query("bad");value=snapshot(45);value.groups[0].item_ids=[11,11]
	service.reply(state.ticket,value)
	check(state.phase==State.Phase.Rejected,"Duplicate membership rejects")
	state.open(7);ready(service,state);state.request_items([11]);value=snapshot(45)
	value.items=[{"id":11,"caption":"Synthetic item","distance":8,"value":20,"tag":2,"prohibited":false,"value_caption":""}]
	service.reply(state.ticket,value);state.request_appearances([11]);artwork_ticket=service.next
	state.close();service.reply(artwork_ticket,{})
	check(service.detached.has(artwork_ticket) and state.appearances.is_empty() and not state.appearance_pending(),"Closing retires artwork ownership and late callbacks")
	commits(service,state)
	drafts(service,state)
	expansion(service,state)
	containers(service,state)
	state.dispose();service.queue_free()
	if failures==0:print("PASS depot goods state")
	quit(1 if failures else 0)
