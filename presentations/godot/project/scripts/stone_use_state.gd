extends RefCounted
# Native owns eligibility, captions, magma safety and restriction effects.
# Local category/scroll intent never supplies authority for an edit.
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Applying,Rejected,Unknown,Unavailable}
var service
var phase:=Phase.Closed
var rows: Array=[]
var restrictions: Array=[]
var category:=0
var first: Array[int]=[0,0]
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
func _clear() -> void:rows=[];restrictions=[]
func _retire() -> void:
	generation+=1;var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close(retain_navigation: bool=false) -> void:
	_retire();_clear();last_result={}
	if not retain_navigation:category=0;first=[0,0]
	phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(retain_navigation: bool=false) -> void:
	close(retain_navigation);_read()
func category_rows() -> Array:return rows.filter(func(row):return int(row.category)==category)
func select_category(value: int) -> void:
	if phase!=Phase.Ready or value not in [0,1] or category==value:return
	category=value;changed.emit()
func seek(value: int,capacity: int) -> void:
	if phase!=Phase.Ready:return
	first[category]=clampi(value,0,maxi(0,category_rows().size()-maxi(0,capacity)));changed.emit()
func toggle(index: int) -> void:
	if phase!=Phase.Ready or not rows.any(func(row):return int(row.category)==category and int(row.index)==index):return
	var intent: Dictionary={"action":C.ManagementAction.StoneUseApply,"category":category,"index":index,"expected":restrictions.duplicate()}
	_clear();phase=Phase.Applying;_submit(intent)
func _read() -> void:
	_clear();phase=Phase.Reading;_submit({"action":C.ManagementAction.StoneUseRead})
func _integer(value: Variant,low: int,high: int) -> bool:return typeof(value)==TYPE_INT and value>=low and value<=high
func _valid(value: Dictionary) -> bool:
	if typeof(value.get("rows"))!=TYPE_ARRAY or typeof(value.get("restrictions"))!=TYPE_ARRAY or value.rows.size()>65536 or value.restrictions.size()>65536:return false
	for flag in value.restrictions:
		if not _integer(flag,0,1):return false
	var seen: Dictionary={}
	for row in value.rows:
		if typeof(row)!=TYPE_DICTIONARY or not _integer(row.get("category"),0,1) or not _integer(row.get("index"),0,value.restrictions.size()-1):return false
		if seen.has(row.index) or typeof(row.get("restricted"))!=TYPE_BOOL or row.restricted!=(value.restrictions[row.index]!=0) or typeof(row.get("magma_safe"))!=TYPE_BOOL:return false
		seen[row.index]=true
		for field in ["name","uses","material_token"]:
			if typeof(row.get(field))!=TYPE_STRING:return false
		if row.name.is_empty() or row.name.to_utf8_buffer().size()>16384 or row.uses.to_utf8_buffer().size()>65536 or (row.category==1 and not row.uses.is_empty()) or row.material_token.is_empty() or row.material_token.to_utf8_buffer().size()>256:return false
	return true
func _reject(result: Dictionary) -> void:
	_clear();last_result=result.duplicate(true)
	var value: Variant=result.get("stone_use",{})
	phase=Phase.Unknown if result.get("outcome","")=="unknown" or (typeof(value)==TYPE_DICTIONARY and value.get("outcome",-1)==C.StoneUseOutcome.Unknown) else Phase.Rejected
	changed.emit()
func _submit(intent: Dictionary) -> void:
	if service==null:_clear();phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit("stone_use",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("stone_use",{})
		var apply: bool=intent.action==C.ManagementAction.StoneUseApply
		if typeof(value)!=TYPE_DICTIONARY or result.get("outcome","")=="unknown" or result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=intent.action or value.get("outcome",-1)!=(C.StoneUseOutcome.Applied if apply else C.StoneUseOutcome.None) or not _valid(value):
			_reject(result);return
		if apply:
			if not value.rows.is_empty() or not value.restrictions.is_empty():_reject(result);return
			_read();return
		rows=value.rows.duplicate(true);restrictions=value.restrictions.duplicate()
		for kind in 2:first[kind]=mini(first[kind],maxi(0,rows.filter(func(row):return int(row.category)==kind).size()-1))
		last_result={};phase=Phase.Ready;changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()
