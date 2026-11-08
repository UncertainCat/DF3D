extends RefCounted
# DF owns the rows, ordering, eligibility and toggle effects. This owner retains
# local query/navigation and complete receipts only until the next intent.
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var rows: Array=[]
var exclusions: Array=[]
var query: Dictionary={"type_filter":-1,"capability_filter":0,"query":"","sorts":[{"column":0,"reverse":false}]}
var first:=0
var selected:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
var sort_directions: Array[bool]=[false,false,false,false,false]

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _clear() -> void:
	rows=[];exclusions=[]
func _retire() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	_retire();_clear();first=0;selected=0;last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();query={"type_filter":-1,"capability_filter":0,"query":"","sorts":[{"column":0,"reverse":false}]}
	sort_directions=[false,false,false,false,false]
	phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();_read()
func set_query(value: Dictionary) -> void:
	if phase not in [Phase.Ready,Phase.Reading] or not _valid_query(value) or value==query:return
	_retire();query=value.duplicate(true);first=0;selected=0;_read()
func set_search(bytes: PackedByteArray) -> void:
	var value:=query.duplicate(true);value.query=bytes.get_string_from_utf8();set_query(value)
func seek(value: int,capacity: int) -> void:
	first=clampi(value,0,maxi(0,rows.size()-maxi(0,capacity)));changed.emit()
func move_selection(delta: int,capacity: int) -> void:
	if phase!=Phase.Ready or rows.is_empty() or capacity<=0:return
	selected=clampi(selected+delta,0,rows.size()-1)
	if selected<first:first=selected
	elif selected>=first+capacity:first=selected-capacity+1
	changed.emit()
func cycle_type(delta: int) -> void:
	var value:=query.duplicate(true);value.type_filter=posmod(int(value.type_filter)+1+delta,5)-1;set_query(value)
func toggle_capability(permission: int) -> void:
	if permission not in [1,2]:return
	var value:=query.duplicate(true);value.capability_filter=int(value.capability_filter)^permission;set_query(value)
func select_sort(column: int) -> void:
	if phase not in [Phase.Ready,Phase.Reading] or column<0 or column>4:return
	if int(query.sorts[0].column)==column:sort_directions[column]=not sort_directions[column]
	var value:=query.duplicate(true);value.sorts=[{"column":column,"reverse":sort_directions[column]}];set_query(value)
func _read() -> void:
	_clear();phase=Phase.Reading
	var intent:=query.duplicate(true);intent.action=C.ManagementAction.KitchenRead;_submit(intent)
func toggle(index: int,permission: int) -> void:
	if phase!=Phase.Ready or index<0 or index>=rows.size() or permission not in [1,2]:return
	var target: Dictionary=rows[index].receipt
	if not (int(target.capabilities)&permission):return
	var intent: Dictionary={"action":C.ManagementAction.KitchenApply,"target":target.duplicate(true),"permission":permission,"expected":exclusions.duplicate(true)}
	_clear();phase=Phase.Applying;_submit(intent)
func _integer(d: Dictionary,key: String,low: int,high: int) -> bool:
	return typeof(d.get(key))==TYPE_INT and d[key]>=low and d[key]<=high
func _valid_query(v: Dictionary) -> bool:
	if v.size()!=4 or not _integer(v,"type_filter",-1,3) or not _integer(v,"capability_filter",0,3) or typeof(v.get("query"))!=TYPE_STRING or v.query.to_utf8_buffer().size()>4096 or typeof(v.get("sorts"))!=TYPE_ARRAY:return false
	if v.sorts.is_empty() or v.sorts.size()>5:return false
	var seen: Dictionary={}
	for sort in v.sorts:
		if typeof(sort)!=TYPE_DICTIONARY or sort.size()!=2 or not _integer(sort,"column",0,4) or typeof(sort.get("reverse"))!=TYPE_BOOL or seen.has(sort.column):return false
		seen[sort.column]=true
	return true
func _key(v: Variant) -> bool:
	return typeof(v)==TYPE_DICTIONARY and v.size()==4 and _integer(v,"item_type",0,32767) and _integer(v,"item_subtype",-1,32767) and _integer(v,"mat_type",-1,32767) and _integer(v,"mat_index",-1,2147483647)
func _valid(value: Dictionary) -> bool:
	if typeof(value.get("rows"))!=TYPE_ARRAY or typeof(value.get("exclusions"))!=TYPE_ARRAY or value.rows.size()>65536 or value.exclusions.size()>65536:return false
	var seen: Dictionary={}
	for row in value.rows:
		if typeof(row)!=TYPE_DICTIONARY or typeof(row.get("receipt"))!=TYPE_DICTIONARY:return false
		var receipt: Dictionary=row.receipt
		if not _key(receipt.get("key")) or not _integer(receipt,"count",0,2147483647) or not _integer(receipt,"capabilities",1,3):return false
		var k: Dictionary=receipt.key
		var identity: String="%d:%d:%d:%d"%[k.item_type,k.item_subtype,k.mat_type,k.mat_index]
		if seen.has(identity):return false
		seen[identity]=true
		for field in ["name","count_caption","material_token"]:
			if typeof(row.get(field))!=TYPE_STRING or row[field].is_empty():return false
		if row.name.to_utf8_buffer().size()>16384 or row.count_caption.to_utf8_buffer().size()>64 or row.material_token.to_utf8_buffer().size()>256 or typeof(row.get("estimated"))!=TYPE_BOOL or not _integer(row,"excluded",0,3):return false
	for row in value.exclusions:
		if typeof(row)!=TYPE_DICTIONARY or not _key(row.get("key")) or not _integer(row,"flags",0,3):return false
	return true
func _reject(result: Dictionary) -> void:
	_clear();last_result=result.duplicate(true)
	var value: Variant=result.get("kitchen_menu",{})
	phase=Phase.Unknown if result.get("outcome","")=="unknown" or (typeof(value)==TYPE_DICTIONARY and value.get("outcome",-1)==C.KitchenMenuOutcome.Unknown) else Phase.Rejected
	changed.emit()
func _submit(intent: Dictionary) -> void:
	if service==null:_clear();phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit("kitchen_menu",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("kitchen_menu",{})
		var apply: bool=intent.action==C.ManagementAction.KitchenApply
		if typeof(value)!=TYPE_DICTIONARY or result.get("outcome","")=="unknown" or result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=intent.action or value.get("outcome",-1)!=(C.KitchenMenuOutcome.Applied if apply else C.KitchenMenuOutcome.None) or not _valid(value):
			_reject(result);return
		if apply:
			if not value.rows.is_empty() or not value.exclusions.is_empty():_reject(result);return
			_read();return
		rows=value.rows.duplicate(true);exclusions=value.exclusions.duplicate(true);first=mini(first,maxi(0,rows.size()-1))
		last_result={};phase=Phase.Ready;changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()
