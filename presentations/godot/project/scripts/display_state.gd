extends RefCounted
# Selection is local until explicit picker closure. Reopening never replays edits.
signal changed
signal picker_closed
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Applying,Rejected,Stale,Unknown,Unavailable}
var service
var phase:=Phase.Closed
var building_id: int=-1
var category: int=-1
var query: String=""
var categories: Array=[]
var groups: Array=[]
var body: Array=[]
var items: Dictionary={}
var selected: Dictionary={}
var expansion: Dictionary={}
var first_category:=0
var first_item:=0
var revision: int=0
var inventory_revision: int=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
var _queries: Array[String]=[]
var _active_query: String=""
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func close() -> void:
	generation+=1
	if service!=null and ticket!=0:service.detach(ticket)
	ticket=0;building_id=-1;category=-1;query="";_active_query="";_queries=[]
	categories=[];groups=[];body=[];items={};selected={};expansion={}
	first_category=0;first_item=0;revision=0;inventory_revision=0;last_result={}
	phase=Phase.Closed;changed.emit()
func _session_changed() -> void:close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0:return
	building_id=id;_read()
func open_picker() -> void:
	if phase!=Phase.Ready or category!=-1:return
	category=-2;selected={};inventory_revision=0;_read()
func key(row: Dictionary) -> String:return "%d:%d:%d:%d"%[row.type,row.subtype,row.subcat1,row.subcat2]
func visible_categories() -> Array:return categories.filter(func(row):return row.matches)
func expanded(row: Dictionary) -> bool:return expansion.get(key(row),row.expanded)
func toggle_expansion(identity: String) -> void:
	if phase!=Phase.Ready:return
	for row in groups:
		if key(row)==identity and row.matches:expansion[identity]=not expanded(row);changed.emit();return
func select_category(value: int) -> void:
	if phase!=Phase.Ready or category<0 or category==value or not categories.any(func(row):return row.type==value and row.matches):return
	category=value;expansion={};first_item=0;items={};_read()
func set_query(value: String) -> void:
	if phase not in [Phase.Ready,Phase.Reading] or category<0 or value==query or value.to_utf8_buffer().size()>1024:return
	query=value;_queries.append(value)
	if phase==Phase.Ready:_active_query=_queries.pop_front();_read()
func toggle_item(id: int) -> void:
	if phase!=Phase.Ready or category<0:return
	if not groups.any(func(row):return row.matches and row.item_ids.has(id)):return
	if selected.has(id):selected.erase(id)
	else:selected[id]=true
	changed.emit()
func request_items(ids: Array) -> void:
	if phase!=Phase.Ready or ids.size()>64:return
	var members: Dictionary={}
	if category<0:
		for row in body:members[row.id]=true
	else:
		for row in groups:
			for id in row.item_ids:members[id]=true
	var seen: Dictionary={}
	for id in ids:
		if typeof(id)!=TYPE_INT or not members.has(id) or seen.has(id):return
		seen[id]=true
	if ids.all(func(id):return items.has(id)):return
	_read(ids)
func finish_picker() -> void:
	if phase!=Phase.Ready or category<0:return
	if selected.is_empty():
		category=-1;query="";_active_query="";_queries=[];inventory_revision=0;_read();picker_closed.emit();return
	var ids: Array=selected.keys();ids.sort()
	phase=Phase.Applying
	_submit({"action":C.ManagementAction.DisplayCommit,"building_id":building_id,"expected_revision":inventory_revision,"selected_ids":ids})
func remove_item(id: int) -> void:
	if phase!=Phase.Ready or category!=-1 or not body.any(func(row):return row.id==id):return
	phase=Phase.Applying
	_submit({"action":C.ManagementAction.DisplayRemove,"building_id":building_id,"expected_revision":revision,"selected_ids":[id]})
func _read(ids: Array=[]) -> void:
	phase=Phase.Reading
	_submit({"action":C.ManagementAction.DisplayRead,"building_id":building_id,"category":category,"query":_active_query,"item_ids":ids.duplicate()})
func _reject(result: Dictionary,uncertain: bool=false) -> void:
	last_result=result.duplicate(true);items={}
	var outcome: int=result.get("display",{}).get("outcome",C.DisplayOutcome.Rejected)
	phase=Phase.Unknown if uncertain or result.get("outcome")=="unknown" or outcome==C.DisplayOutcome.Unknown else (Phase.Stale if outcome==C.DisplayOutcome.Stale else Phase.Rejected)
	changed.emit()
func _submit(intent: Dictionary) -> void:
	if service==null:phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit("display",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var edit: bool=intent.action!=C.ManagementAction.DisplayRead
		var value: Dictionary=result.get("display",{})
		if result.get("outcome")=="unknown" or result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=intent.action or value.get("outcome")!=(C.DisplayOutcome.Applied if edit else C.DisplayOutcome.Available):
			_reject(result);return
		# The typed transport validates rows and memberships; bind this receipt
		# to the local owner and preserve exact 64-bit revision integers.
		if value.get("building_id")!=building_id or typeof(value.get("revision"))!=TYPE_INT or value.revision<=0 or typeof(value.get("inventory_revision"))!=TYPE_INT or typeof(value.get("body"))!=TYPE_ARRAY or typeof(value.get("categories"))!=TYPE_ARRAY or typeof(value.get("groups"))!=TYPE_ARRAY or typeof(value.get("items"))!=TYPE_ARRAY:
			_reject(result,edit);return
		var received_category: Variant=value.get("category")
		if typeof(received_category)!=TYPE_INT or received_category < -1 or received_category>92 or (edit and received_category!=-1) or (received_category>=0 and (value.categories.size()!=93 or value.inventory_revision<=0)) or (received_category==-1 and (value.inventory_revision!=0 or not value.categories.is_empty() or not value.groups.is_empty())):
			_reject(result,edit);return
		if not edit and category!=-1 and inventory_revision!=0 and value.inventory_revision!=inventory_revision:
			_reject({"display":{"outcome":C.DisplayOutcome.Stale}});return
		if edit:
			category=-1;query="";_active_query="";_queries=[];selected={};expansion={};items={}
		elif intent.category==-2:category=value.category
		elif value.get("category")!=category:_reject(result);return
		revision=value.revision;inventory_revision=value.inventory_revision
		body=value.body.duplicate(true);categories=value.categories.duplicate(true);groups=value.groups.duplicate(true)
		for row in value.items:items[row.id]=row.duplicate(true)
		if category>=0:
			var choices:=visible_categories()
			var next: int=categories[0].type if choices.is_empty() else (category if choices.any(func(row):return row.type==category) else choices[0].type)
			if next!=category:category=next;expansion={};first_item=0;items={};_read();return
		if not _queries.is_empty():_active_query=_queries.pop_front();items={};_read();return
		last_result={};phase=Phase.Ready;changed.emit()
		if intent.action==C.ManagementAction.DisplayCommit:picker_closed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
