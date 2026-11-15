extends RefCounted
# Native snapshots own filtering, captions, membership and order. This staged
# controller owns local checkbox intent; native projections own group states.
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Rejected,Unknown,Unavailable,Applying,Stale}
var service
var phase:=Phase.Closed
var depot_id: int=-1
var category: int=-1
var revision: int=0
var query: String=""
var sort_by_distance:=true
var pending_on_top:=true
var exclude_prohibited:=false
var categories: Array=[]
var groups: Array=[]
var items: Dictionary={}
var first_category:=0
var first_item:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
var _active_query: String=""
var _queries: Array[String]=[]
var appearances: Dictionary={}
var _inspection
var _appearance_queue: Array=[]
var _appearance_id: int=-1
var _draft: Dictionary={}
var _sort_draft: Dictionary={}
var _draft_revision: int=0
var _finish_pending:=false
var _expanded: Dictionary={}
func _group_key(row: Dictionary) -> String:return "%d:%d:%d"%[row.subtype,row.subcat1,row.subcat2]
func toggle_expansion(index: int) -> void:
	if phase!=Phase.Ready or index<0 or index>=groups.size() or not groups[index].matches:return
	var row: Dictionary=groups[index]
	row.expanded=not row.expanded;_expanded[_group_key(row)]=row.expanded;changed.emit()
func _choices(source: Dictionary) -> Array:
	var result: Array=[]
	for id in source:result.append({"id":id,"desired":source[id]})
	return result
func toggle_item(id: int) -> void:
	if phase==Phase.Ready and items.has(id):_stage([id],items[id].tag<=0)
func toggle_group(index: int) -> void:
	if phase!=Phase.Ready or index<0 or index>=groups.size():return
	var row: Dictionary=groups[index]
	if row.matches:_stage(row.item_ids,(row.flags&1)==0)
func toggle_all() -> void:
	if phase!=Phase.Ready:return
	var ids: Array=[];var selected:=true
	for row in groups:
		if row.matches and not row.item_ids.is_empty():
			ids.append_array(row.item_ids);selected=selected and (row.flags&1)!=0
	_stage(ids,not selected)
func _stage(ids: Array,desired: bool) -> void:
	if ids.is_empty():return
	var next: Dictionary=_draft.duplicate()
	for id in ids:next[id]=desired
	if next.size()>65536:return # Never split one close into partial commits.
	if _draft_revision==0:_draft_revision=revision
	_draft=next;_read(items.keys())
func finish() -> void:
	if phase==Phase.Applying:return
	if phase==Phase.Reading:
		_finish_pending=true;_queries=[];return
	if phase==Phase.Ready and not _draft.is_empty():commit_and_close(_draft_revision,_choices(_draft))
	else:close()
func configure(source) -> void:
	dispose();service=source
	if service!=null:
		service.session_changed.connect(_session_changed)
		_inspection=preload("res://scripts/item_sheet_state.gd").new();_inspection.configure(service)
		_inspection.changed.connect(_inspection_changed)
func dispose() -> void:
	close()
	if _inspection!=null:_inspection.dispose();_inspection=null
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _clear() -> void:
	revision=0;categories=[];groups=[];items={};appearances={};_appearance_queue=[];_appearance_id=-1
	if _inspection!=null:_inspection.close()
func request_appearances(ids: Array) -> void:
	if phase!=Phase.Ready or _inspection==null or ids.size()>64:return
	for id in ids:
		if typeof(id)!=TYPE_INT or not items.has(id):return
	for id in ids:
		if not appearances.has(id) and id!=_appearance_id and not _appearance_queue.has(id):_appearance_queue.append(id)
	_next_appearance()
func _next_appearance() -> void:
	if phase!=Phase.Ready or _appearance_id>=0 or _appearance_queue.is_empty():return
	_appearance_id=_appearance_queue.pop_front();_inspection.open(_appearance_id)
func appearance_pending() -> bool:return _appearance_id>=0 or not _appearance_queue.is_empty()
func _inspection_changed() -> void:
	if _appearance_id<0 or phase!=Phase.Ready or _inspection.phase in [_inspection.Phase.Closed,_inspection.Phase.Reading]:return
	var id:=_appearance_id;_appearance_id=-1
	# This is the existing owned inspection API, whose selector is also called
	# by native depot38b783. A rejected read leaves absent artwork, never a retry.
	appearances[id]={}
	if _inspection.phase==_inspection.Phase.Ready:
		var value: Dictionary=_inspection.snapshot
		if value.id==id and value.item_type==category and value.has("appearance"):appearances[id]=value.appearance.duplicate(true)
	changed.emit();_next_appearance()
func close() -> void:
	generation+=1;var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	_clear();depot_id=-1;category=-1;query="";_active_query="";_queries=[]
	_draft={};_sort_draft={};_draft_revision=0;_finish_pending=false;_expanded={}
	sort_by_distance=true;pending_on_top=true;exclude_prohibited=false
	first_category=0;first_item=0;last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:return
	depot_id=id;_read()
func commit_and_close(expected_revision: int,changes: Array) -> bool:
	# The caller must retain the draft's original revision. Never rebase a draft
	# onto a later read, split it, or replay a rejected/uncertain commit.
	if phase!=Phase.Ready or revision<=0 or expected_revision!=revision or changes.is_empty() or changes.size()>65536:return false
	var seen: Dictionary={}
	for row in changes:
		if typeof(row)!=TYPE_DICTIONARY or row.size()!=2 or not _integer(row.get("id"),0,2147483647) or typeof(row.get("desired"))!=TYPE_BOOL:return false
		if seen.has(row.id):return false
		seen[row.id]=true
	if service==null:phase=Phase.Unavailable;changed.emit();return false
	var intent: Dictionary={"action":C.ManagementAction.DepotGoodsCommit,"depot_id":depot_id,"expected_revision":expected_revision,"changes":changes.duplicate(true)}
	var owner:=generation
	phase=Phase.Applying;last_result={}
	_appearance_queue=[];_appearance_id=-1
	if _inspection!=null:_inspection.close()
	ticket=service.submit("depot_goods",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;last_result=result.duplicate(true)
		var receipt: Variant=result.get("depot_commit",{})
		if result.get("outcome")=="unknown":phase=Phase.Unknown
		elif result.get("status")==C.ManagementStatus.Rejected:phase=Phase.Rejected
		elif result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=intent.action or not _valid_commit(receipt,intent):phase=Phase.Unknown
		elif receipt.outcome==C.DepotGoodsCommitOutcome.Applied:close();return
		elif receipt.outcome==C.DepotGoodsCommitOutcome.Stale:phase=Phase.Stale
		elif receipt.outcome==C.DepotGoodsCommitOutcome.Rejected:phase=Phase.Rejected
		else:phase=Phase.Unknown
		changed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit();return ticket!=0
func _valid_commit(value: Variant,intent: Dictionary) -> bool:
	if typeof(value)!=TYPE_DICTIONARY or value.get("depot_id")!=intent.depot_id or value.get("expected_revision")!=intent.expected_revision:return false
	if not _integer(value.get("outcome"),0,3) or not _integer(value.get("observed_revision"),0,9223372036854775807):return false
	if value.outcome==C.DepotGoodsCommitOutcome.Stale:return value.observed_revision>0 and value.observed_revision!=intent.expected_revision
	if value.outcome in [C.DepotGoodsCommitOutcome.Applied,C.DepotGoodsCommitOutcome.Unknown]:return value.observed_revision==intent.expected_revision
	return true
func select_category(value: int) -> void:
	if phase!=Phase.Ready or category==value or not categories.any(func(row):return row.type==value):return
	category=value;first_item=0;_sort_draft=_draft.duplicate();_expanded={};_read()
func set_query(value: String) -> void:
	if _finish_pending or phase not in [Phase.Ready,Phase.Reading] or value==query or value.to_utf8_buffer().size()>2048:return
	query=value;_queries.append(value)
	if phase==Phase.Ready:_active_query=_queries.pop_front();first_item=0;_read()
func set_options(distance: bool,pending: bool,exclude: bool) -> void:
	if phase!=Phase.Ready or [distance,pending,exclude]==[sort_by_distance,pending_on_top,exclude_prohibited]:return
	sort_by_distance=distance;pending_on_top=pending;exclude_prohibited=exclude;first_item=0;_sort_draft=_draft.duplicate();_expanded={};_read()
func request_items(ids: Array) -> void:
	if phase!=Phase.Ready or ids.size()>64:return
	var members: Dictionary={};var seen: Dictionary={}
	for group in groups:
		for id in group.item_ids:members[id]=true
	for id in ids:
		if typeof(id)!=TYPE_INT or not members.has(id) or seen.has(id):return
		seen[id]=true
	if ids.all(func(id):return items.has(id)):return
	_read(ids)
func row_count() -> int:
	# Native37aeb0 skips the entire list when no category items remain, even
	# if exclusion leaves an abstract group marked as matching.
	if not groups.any(func(row):return not row.item_ids.is_empty()):return 0
	var count:=0
	for row in groups:
		if row.matches:count+=1+(row.item_ids.size() if row.expanded else 0)
	return count
func page(first: int,limit: int) -> Array:
	var result: Array=[]
	if first<0 or limit<1 or limit>256 or row_count()==0:return result
	var offset:=0
	for row in groups:
		if not row.matches:continue
		if offset>=first and result.size()<limit:result.append({"group":row})
		offset+=1
		if row.expanded:
			for index in range(maxi(0,first-offset),mini(row.item_ids.size(),first+limit-offset)):
				if result.size()<limit:result.append({"id":row.item_ids[index]})
			offset+=row.item_ids.size()
		if result.size()==limit:break
	return result
func _integer(value: Variant,low: int,high: int) -> bool:return typeof(value)==TYPE_INT and value>=low and value<=high
func _text(value: Variant) -> bool:return typeof(value)==TYPE_STRING and not value.is_empty() and value.to_utf8_buffer().size()<=16384
func _valid(value: Dictionary,intent: Dictionary) -> bool:
	if value.get("depot_id")!=intent.depot_id or value.get("category")!=intent.category or not _integer(value.get("revision"),1,9223372036854775807):return false
	if intent.expected_revision!=0 and value.revision!=intent.expected_revision:return false
	for field in ["categories","groups","items"]:
		if typeof(value.get(field))!=TYPE_ARRAY:return false
	if value.categories.size()>93 or value.groups.size()>65536 or value.items.size()>64:return false
	var types: Dictionary={};var keys: Dictionary={};var members: Dictionary={};var ids: Dictionary={}
	for row in value.categories:
		if typeof(row)!=TYPE_DICTIONARY or not _integer(row.get("type"),0,92) or types.has(row.type) or not _text(row.get("caption")):return false
		types[row.type]=true
	for row in value.groups:
		if typeof(row)!=TYPE_DICTIONARY:return false
		for field in ["subtype","subcat1","subcat2"]:
			if not _integer(row.get(field),-1,32767):return false
		var key: String="%d:%d:%d"%[row.subtype,row.subcat1,row.subcat2]
		if keys.has(key) or not _integer(row.get("amount"),0,2147483647) or not _integer(row.get("flags"),0,3) or not _text(row.get("caption")):return false
		keys[key]=true
		if typeof(row.get("matches"))!=TYPE_BOOL or typeof(row.get("expanded"))!=TYPE_BOOL or typeof(row.get("item_ids"))!=TYPE_ARRAY:return false
		for id in row.item_ids:
			if not _integer(id,0,2147483647) or members.has(id):return false
			members[id]=true
		if members.size()>1048576:return false
	for row in value.items:
		if typeof(row)!=TYPE_DICTIONARY or not _integer(row.get("id"),0,2147483647) or ids.has(row.id) or not members.has(row.id) or not _text(row.get("caption")):return false
		ids[row.id]=true
		if not _integer(row.get("distance"),-2147483648,2147483647) or not _integer(row.get("value"),-2147483648,2147483647) or not _integer(row.get("tag"),-2,3) or typeof(row.get("prohibited"))!=TYPE_BOOL:return false
		if intent.expected_revision==0 and row.tag not in [0,2,3]:return false
	if intent.category==-1 and (not value.groups.is_empty() or not value.items.is_empty()):return false
	return ids.size()==intent.item_ids.size() and intent.item_ids.all(func(id):return ids.has(id))
func _read(ids: Array=[]) -> void:
	_clear();phase=Phase.Reading
	if service==null:phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	var intent: Dictionary={"action":C.ManagementAction.DepotGoodsRead,"depot_id":depot_id,"category":category,"query":_active_query,"sort_by_distance":sort_by_distance,"pending_on_top":pending_on_top,"exclude_prohibited":exclude_prohibited,"item_ids":ids.duplicate()}
	intent.expected_revision=_draft_revision;intent.draft=_choices(_draft);intent.sort_draft=_choices(_sort_draft)
	ticket=service.submit("depot_goods",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("depot_goods",{})
		if typeof(value)!=TYPE_DICTIONARY or result.get("outcome")=="unknown" or result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=intent.action or not _valid(value,intent):
			_clear();last_result=result.duplicate(true);phase=Phase.Unknown if result.get("outcome")=="unknown" else Phase.Rejected;changed.emit();return
		revision=value.revision;categories=value.categories.duplicate(true);groups=value.groups.duplicate(true);items={}
		# Native group-label clicks change only current_type_a_expanded.
		# Search/detail/draft projections retain it; category/options rebuild it.
		for row in groups:
			if _expanded.has(_group_key(row)):row.expanded=_expanded[_group_key(row)]
		for row in value.items:items[row.id]=row.duplicate(true)
		if category==-1 and not categories.is_empty():category=categories[0].type;_read();return
		if _finish_pending:_finish_pending=false;phase=Phase.Ready;finish();return
		# Native query/exclusion can retain a selected type absent from the
		# filtered category list. Do not replace it with a guessed fallback.
		if not _queries.is_empty():_active_query=_queries.pop_front();first_item=0;_read();return
		last_result={};phase=Phase.Ready;changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()
