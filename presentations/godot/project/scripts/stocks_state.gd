extends RefCounted
# DF supplies categories, filtering, group membership, captions and edit receipts.
# Only navigation/expansion is local. No receipt survives a pending command.
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Applying,Rejected,Unknown,Unavailable}
var service
var phase:=Phase.Closed
var category: int=-1
var query: String=""
var _active_query: String=""
var _queries: Array[String]=[]
var categories: Array=[]
var groups: Array=[]
var items: Dictionary={}
var expansion: Dictionary={}
var first_category:=0
var first_item:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _clear() -> void:categories=[];groups=[];items={}
func _retire() -> void:
	generation+=1;var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	_retire();_clear();category=-1;query="";_active_query="";_queries=[];expansion={};first_category=0;first_item=0
	last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:close();_read()
func key(row: Dictionary) -> String:return "%d:%d:%d:%d"%[row.type,row.subtype,row.subcat1,row.subcat2]
func visible_categories() -> Array:return categories.filter(func(row):return row.matches)
func expanded(row: Dictionary) -> bool:return expansion.get(key(row),row.expanded)
func toggle_expansion(identity: String) -> void:
	if phase!=Phase.Ready:return
	for row in groups:
		if key(row)==identity and row.matches:
			expansion[identity]=not expanded(row);changed.emit();return
func select_category(value: int) -> void:
	if phase!=Phase.Ready or category==value or not categories.any(func(row):return row.type==value and row.matches):return
	category=value;expansion={};first_item=0;_read()
func set_query(value: String) -> void:
	if phase not in [Phase.Ready,Phase.Reading] or value==query or value.to_utf8_buffer().size()>4096:return
	# Each native keystroke can change category. Preserve those transitions
	# while requests are asynchronous, including intermediate empty matches.
	query=value;_queries.append(value)
	if phase==Phase.Ready:_active_query=_queries.pop_front();_read()
func request_items(ids: Array) -> void:
	if phase!=Phase.Ready or ids.size()>64:return
	var members: Dictionary={};var seen: Dictionary={}
	for row in groups:
		for id in row.item_ids:members[id]=true
	for id in ids:
		if typeof(id)!=TYPE_INT or not members.has(id) or seen.has(id):return
		seen[id]=true
	if ids.all(func(id):return items.has(id)):return
	_read(ids)
func apply_group(identity: String,operation: int,value: bool) -> void:
	if phase!=Phase.Ready or operation<0 or operation>3:return
	for row in groups:
		if key(row)!=identity or not row.matches:continue
		var intent: Dictionary={"action":C.ManagementAction.StocksGroupApply,"category":category,
			"subtype":row.subtype,"subcat1":row.subcat1,"subcat2":row.subcat2,
			"expected_revision":row.revision,"operation":operation,"value":int(value)}
		_clear();phase=Phase.Applying;_submit(intent);return
func apply_item(id: int,operation: int,value: bool) -> void:
	if phase!=Phase.Ready or operation<0 or operation>3 or not items.has(id):return
	var item: Dictionary=items[id]
	if (operation==1 and not item.can_dump) or (operation==2 and not item.can_melt):return
	for row in groups:
		if not row.matches or not row.item_ids.has(id):continue
		var intent: Dictionary={"action":C.ManagementAction.StocksItemApply,"category":category,
			"subtype":row.subtype,"subcat1":row.subcat1,"subcat2":row.subcat2,"item_id":id,
			"expected_revision":row.revision,"operation":operation,"value":int(value)}
		_clear();phase=Phase.Applying;_submit(intent);return
func _read(ids: Array=[]) -> void:
	_clear();phase=Phase.Reading
	_submit({"action":C.ManagementAction.StocksMenuRead,"category":category,"query":_active_query,"item_ids":ids.duplicate()})
func _integer(value: Variant,low: int,high: int) -> bool:return typeof(value)==TYPE_INT and value>=low and value<=high
func _text(value: Variant,limit: int,empty: bool=true) -> bool:
	return typeof(value)==TYPE_STRING and (empty or not value.is_empty()) and value.to_utf8_buffer().size()<=limit
func _valid(value: Dictionary,intent: Dictionary) -> bool:
	if value.get("category")!=intent.category:return false
	for field in ["categories","groups","items"]:
		if typeof(value.get(field))!=TYPE_ARRAY:return false
	if value.categories.size()!=93 or value.groups.size()>65536 or value.items.size()>64:return false
	var types: Dictionary={};var keys: Dictionary={};var members: Dictionary={};var ids: Dictionary={}
	for row in value.categories:
		if typeof(row)!=TYPE_DICTIONARY or not _integer(row.get("type"),0,92) or types.has(row.type):return false
		types[row.type]=true
		if not _text(row.get("caption"),16384,false) or not _text(row.get("stored"),64,false) or not _text(row.get("unavailable"),64) or typeof(row.get("matches"))!=TYPE_BOOL:return false
	for row in value.groups:
		if typeof(row)!=TYPE_DICTIONARY or row.get("type")!=category:return false
		for field in ["subtype","subcat1","subcat2"]:
			if not _integer(row.get(field),-1,32767):return false
		if keys.has(key(row)) or not _integer(row.get("revision"),1,9223372036854775807) or not _integer(row.get("flags"),0,255) or not _integer(row.get("amount"),-2147483648,2147483647):return false
		keys[key(row)]=true
		if not _text(row.get("caption"),16384,false) or typeof(row.get("matches"))!=TYPE_BOOL or typeof(row.get("expanded"))!=TYPE_BOOL or typeof(row.get("item_ids"))!=TYPE_ARRAY or row.item_ids.is_empty():return false
		for id in row.item_ids:
			if not _integer(id,0,2147483647) or members.has(id):return false
			members[id]=true
		if members.size()>1048576:return false
	for row in value.items:
		if typeof(row)!=TYPE_DICTIONARY or not _integer(row.get("id"),0,2147483647) or ids.has(row.id) or not members.has(row.id) or row.get("type")!=category:return false
		ids[row.id]=true
		if not _text(row.get("caption"),16384,false) or not _text(row.get("material_token"),256) or not _text(row.get("subtype_raw"),256) or not _integer(row.get("flags"),0,4294967295):return false
		if typeof(row.get("can_dump"))!=TYPE_BOOL or typeof(row.get("can_melt"))!=TYPE_BOOL:return false
		if row.has("appearance"):
			var a: Variant=row.appearance
			if typeof(a)!=TYPE_DICTIONARY or a.size()!=(6 if row.type==13 else 5):return false
			if not _text(a.get("material_token"),256,false) or a.material_token!=row.material_token or not _text(a.get("subtype_raw"),128) or a.subtype_raw!=row.subtype_raw or not _text(a.get("color_token"),128):return false
			if not _integer(a.get("stack"),1,2147483647) or not _integer(a.get("flags"),0,96) or (a.flags&~96):return false
			if row.type==13:
				if typeof(a.get("instrument"))!=TYPE_DICTIONARY or a.instrument.size()!=2 or not _integer(a.instrument.get("family"),0,3) or not _integer(a.instrument.get("placed"),0,1):return false
			elif a.has("instrument"):return false
	if category==-1 and (not value.groups.is_empty() or not value.items.is_empty()):return false
	var requested: Array=intent.get("item_ids",[])
	return ids.size()==requested.size() and requested.all(func(id):return ids.has(id))
func _reject(result: Dictionary) -> void:
	_clear();last_result=result.duplicate(true)
	var value: Variant=result.get("stocks_menu",{})
	phase=Phase.Unknown if result.get("outcome","")=="unknown" or (typeof(value)==TYPE_DICTIONARY and value.get("outcome")==C.StocksMenuOutcome.Unknown) else Phase.Rejected
	changed.emit()
func _submit(intent: Dictionary) -> void:
	if service==null:_clear();phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit("stocks_menu",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("stocks_menu",{})
		var apply: bool=intent.action in [C.ManagementAction.StocksGroupApply,C.ManagementAction.StocksItemApply]
		if typeof(value)!=TYPE_DICTIONARY or result.get("outcome","")=="unknown" or result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=intent.action or value.get("outcome")!=(C.StocksMenuOutcome.Applied if apply else C.StocksMenuOutcome.None) or not _valid(value,intent):
			_reject(result);return
		# The mutation receipt is unfiltered. Refresh with the retained search
		# before allowing another action; never issue the mutation again.
		if apply:_read();return
		categories=value.categories.duplicate(true);groups=value.groups.duplicate(true);items={}
		for row in value.items:items[row.id]=row.duplicate(true)
		var choices:=visible_categories()
		var selected: int=category
		if choices.is_empty():selected=int(categories[0].type)
		elif not choices.any(func(row):return row.type==category):selected=int(choices[0].type)
		if selected!=category:
			category=selected;expansion={};first_item=0;_read();return
		if not _queries.is_empty():_active_query=_queries.pop_front();_read();return
		last_result={};phase=Phase.Ready;changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()
