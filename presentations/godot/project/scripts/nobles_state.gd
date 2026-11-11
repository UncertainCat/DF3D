extends RefCounted
# Native order and assessments are authority; paging and scroll belong here.
signal changed
signal dismissed
const C=preload("res://scripts/management_contract.gd")
const MAX_RETAINED_BYTES=64*1024*1024
enum Phase {Closed,Reading,Ready,Rejected,Unavailable,CandidatesReading,CandidatesReady,Applying,Unknown,Accounting,Symbols}
var symbols=preload("res://scripts/nobles_symbols_state.gd").new()
func _init() -> void:
	symbols.changed.connect(_symbols_changed)
	symbols.finished.connect(_symbols_finished)
func _symbols_changed() -> void:changed.emit()
func _symbols_finished() -> void:
	if phase!=Phase.Symbols:return
	rows=[];_pending=[];_seen={};_bytes=0;_total=0;phase=Phase.Reading;_page()
func begin_symbols(target: Dictionary) -> void:
	if phase!=Phase.Ready:return
	for row in rows:
		if office(row)==target and row.assignment_id>=0:
			_retire();phase=Phase.Symbols;symbols.open(target,choices,_revision);changed.emit();return
var service
var phase:=Phase.Closed
var rows: Array=[]
var first:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
var _pending: Array=[]
var _seen: Dictionary={}
var _revision:=0
var _total:=0
var _bytes:=0
var _restarts:=0
var choices: Array=[]
var candidates: Array=[]
var candidate_first:=0
var candidate_target: Dictionary={}
var _candidate_pending: Array=[]
var _candidate_seen: Dictionary={}
var _candidate_revision:=0
var _candidate_total:=0
var _candidate_bytes:=0
var _expected_unit: int=-1
func configure(source) -> void:
	dispose();service=source;symbols.configure(source)
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _clear() -> void:
	rows=[];_pending=[];_seen={};_revision=0;_total=0;_bytes=0
func _retire() -> void:
	generation+=1;var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	symbols.close()
	_retire();_clear();choices=[];_clear_candidates();first=0;last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();phase=Phase.Rejected;refresh()
func refresh() -> void:
	if phase not in [Phase.Ready,Phase.Rejected] or not choices.is_empty():return
	_retire();_clear();_restarts=0;last_result={};phase=Phase.Reading;_page()
func seek(value: int,capacity: int) -> void:
	if phase!=Phase.Ready:return
	first=clampi(value,0,maxi(0,rows.size()-maxi(1,capacity)));changed.emit()
func _integer(value: Variant,low: int,high: int) -> bool:return typeof(value)==TYPE_INT and value>=low and value<=high
func _valid_page(value: Dictionary,intent: Dictionary) -> bool:
	if not _integer(value.get("list_revision"),1,9223372036854775807) or not _integer(value.get("total"),0,65536) or value.get("offset")!=intent.offset or typeof(value.get("rows"))!=TYPE_ARRAY:return false
	if value.rows.size()>intent.limit or intent.offset+value.rows.size()>value.total or (intent.offset<value.total and value.rows.is_empty()):return false
	if _revision and (value.list_revision!=_revision or (not _pending.is_empty() and value.total!=_total)):return false
	var bytes:=0
	for row in value.rows:
		if typeof(row)!=TYPE_DICTIONARY:return false
		for key in ["entity_id","position_id","assignment_id","unit_id","nemesis_id"]:
			if not _integer(row.get(key),0 if key in ["entity_id","position_id"] else -1,2147483647):return false
		if not _integer(row.get("draft_slot"),0,choices.size()) or (row.assignment_id>=0 and row.draft_slot!=0):return false
		var identity:=Vector4i(row.entity_id,row.position_id,row.assignment_id,row.draft_slot)
		if _seen.has(identity):return false
		_seen[identity]=true;bytes+=192
		for key in ["title","squad_caption","holder_caption"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>16384:return false
			bytes+=row[key].to_utf8_buffer().size()
		if not _integer(row.get("priority"),-2147483648,2147483647) or typeof(row.get("can_appoint"))!=TYPE_BOOL or typeof(row.get("has_room_assessment"))!=TYPE_BOOL:return false
		if row.has_room_assessment!=(row.unit_id>=0):return false
		for key in ["required_rooms","actual_rooms","required_furniture","actual_furniture"]:
			if typeof(row.get(key))!=TYPE_ARRAY or row[key].size()!=4:return false
			for number in row[key]:
				if not _integer(number,-2147483648,2147483647) or (not row.has_room_assessment and number!=0):return false
		for key in ["demand_status","mandate_status"]:
			if not _integer(row.get(key),-1,3) or (not row.has_room_assessment and row[key]!=-1):return false
		if row.has("appearance"):
			if row.unit_id<0 or not preload("res://scripts/item_sheet_state.gd")._valid_recipe(row.appearance):return false
			bytes+=12+row.appearance.layers.size()*16
			for key in ["tile_pages","palettes"]:
				for name in row.appearance[key]:bytes+=4+name.to_utf8_buffer().size()
		if row.has("help"):
			var help_size:=_help_bytes(row.help,row.unit_id>=0)
			if help_size<0:return false
			bytes+=help_size
	if bytes>384*1024 or _bytes+bytes>MAX_RETAINED_BYTES:return false
	_bytes+=bytes;return true
func _help_bytes(help: Variant,present: bool) -> int:
	if typeof(help)!=TYPE_DICTIONARY or typeof(help.get("description"))!=TYPE_STRING or help.description.to_utf8_buffer().size()>16384:return -1
	var bytes: int=68+help.description.to_utf8_buffer().size()
	for key in ["rooms","furniture"]:
		if typeof(help.get(key))!=TYPE_ARRAY or help[key].size()!=4:return -1
		for part in help[key]:
			if typeof(part)!=TYPE_DICTIONARY or not _integer(part.get("color"),0,15) or part.color not in [11,12,14,15]:return -1
			bytes+=16
			for field in ["actual","required"]:
				if typeof(part.get(field))!=TYPE_STRING or part[field].to_utf8_buffer().size()>16384:return -1
				if not present and (not part[field].is_empty() or part.color!=15):return -1
				bytes+=4+part[field].to_utf8_buffer().size()
	for key in ["demands","mandates"]:
		if typeof(help.get(key))!=TYPE_ARRAY or help[key].size()>65536 or (not present and not help[key].is_empty()):return -1
		for part in help[key]:
			if typeof(part)!=TYPE_DICTIONARY or typeof(part.get("text"))!=TYPE_STRING or part.text.to_utf8_buffer().size()>16384 or not _integer(part.get("color"),0,15) or part.color not in [6,12,14,15]:return -1
			bytes+=20+part.text.to_utf8_buffer().size()
	if help.has("accounting"):
		var a: Variant=help.accounting
		if not present or typeof(a)!=TYPE_DICTIONARY or not _integer(a.get("setting"),0,4) or not _integer(a.get("level"),0,4):return -1
		bytes+=16
		for key in ["title","examples","attained","progress"]:
			if typeof(a.get(key))!=TYPE_STRING or a[key].to_utf8_buffer().size()>16384:return -1
			bytes+=4+a[key].to_utf8_buffer().size()
	return bytes if bytes<=384*1024 else -1
func _reject(result: Dictionary) -> void:
	_clear();last_result=result.duplicate(true);phase=Phase.Rejected;changed.emit()
func _page() -> void:
	if service==null:_clear();phase=Phase.Unavailable;changed.emit();return
	var intent: Dictionary={"action":C.ManagementAction.NoblesRead,"offset":_pending.size(),"limit":32,"expected_list_revision":_revision,"choices":choices.duplicate(true)}
	var owner:=generation
	ticket=service.submit("nobles",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("nobles",{})
		if typeof(value)!=TYPE_DICTIONARY or result.get("action")!=intent.action or result.get("outcome","")=="unknown":_reject(result);return
		if result.get("status")==C.ManagementStatus.Rejected and value.get("outcome")==C.NoblesOutcome.Stale and _restarts==0 and choices.is_empty():
			_clear();_restarts+=1;_page();return
		if result.get("status")!=C.ManagementStatus.Ok or value.get("outcome")!=C.NoblesOutcome.None or not _valid_page(value,intent):_reject(result);return
		_revision=value.list_revision;_total=value.total;_pending.append_array(value.rows.duplicate(true))
		if _pending.size()<_total:_page();return
		rows=_pending;_pending=[];_seen={};phase=Phase.Ready;last_result={};first=mini(first,maxi(0,rows.size()-1));changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()

func office(row: Dictionary) -> Dictionary:
	return {"entity_id":row.entity_id,"position_id":row.position_id,"assignment_id":row.assignment_id,"draft_slot":row.draft_slot}
func _clear_candidates() -> void:
	candidates=[];candidate_target={};candidate_first=0;_candidate_pending=[];_candidate_seen={}
	_candidate_revision=0;_candidate_total=0;_candidate_bytes=0;_expected_unit=-1
func begin_appointment(target: Dictionary) -> void:
	if phase!=Phase.Ready or choices.size()>=4096:return
	for row in rows:
		if office(row)!=target:continue
		if not row.can_appoint:return
		_retire();_clear_candidates();candidate_target=target.duplicate(true);_expected_unit=row.unit_id
		last_result={};phase=Phase.CandidatesReading;_candidate_page();return
func cancel_appointment() -> void:
	if phase not in [Phase.CandidatesReading,Phase.CandidatesReady]:return
	_retire();_clear_candidates();phase=Phase.Ready;changed.emit()
func seek_candidates(value: int,capacity: int) -> void:
	if phase!=Phase.CandidatesReady:return
	candidate_first=clampi(value,0,maxi(0,candidates.size()-maxi(1,capacity)));changed.emit()
func choose_candidate(unit_id: int) -> void:
	if phase!=Phase.CandidatesReady:return
	var found:=false
	for row in candidates:
		if row.unit_id==unit_id:found=true;break
	if not found:return
	choices.append({"target":candidate_target.duplicate(true),"expected_unit_id":_expected_unit,"unit_id":unit_id})
	_retire();_clear_candidates();rows=[];_pending=[];_seen={};_bytes=0;_total=0
	phase=Phase.Reading;_page()
func _candidate_reject(result: Dictionary) -> void:
	_clear_candidates();last_result=result.duplicate(true);phase=Phase.Ready;changed.emit()
func _valid_candidates(value: Dictionary,intent: Dictionary) -> bool:
	if value.get("target")!=candidate_target or value.get("list_revision")!=_revision or value.get("offset")!=intent.offset:return false
	if not _integer(value.get("candidate_revision"),1,9223372036854775807) or not _integer(value.get("total"),0,1048576) or typeof(value.get("candidates"))!=TYPE_ARRAY:return false
	if _candidate_revision and (value.candidate_revision!=_candidate_revision or value.total!=_candidate_total):return false
	if value.candidates.size()>intent.limit or intent.offset+value.candidates.size()>value.total or (intent.offset<value.total and value.candidates.is_empty()):return false
	var bytes:=0
	for row in value.candidates:
		if typeof(row)!=TYPE_DICTIONARY or not _integer(row.get("unit_id"),-1,2147483647) or not _integer(row.get("value"),-2147483648,2147483647):return false
		if _candidate_seen.has(row.unit_id):return false
		_candidate_seen[row.unit_id]=true;bytes+=64
		for key in ["caption","no_skills"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>16384:return false
			bytes+=row[key].to_utf8_buffer().size()
		if typeof(row.get("skills"))!=TYPE_ARRAY or row.skills.size()>4096:return false
		if row.no_skills.is_empty()!=(row.unit_id<0 or not row.skills.is_empty()):return false
		if row.unit_id<0 and (not row.skills.is_empty() or row.has("appearance")):return false
		var skills: Dictionary={}
		for skill in row.skills:
			if typeof(skill)!=TYPE_DICTIONARY or not _integer(skill.get("id"),0,32767) or not _integer(skill.get("rating"),1,2147483647):return false
			if skills.has(skill.id) or typeof(skill.get("caption"))!=TYPE_STRING or skill.caption.to_utf8_buffer().size()>16384:return false
			skills[skill.id]=true;bytes+=16+skill.caption.to_utf8_buffer().size()
		if row.has("appearance"):
			if not preload("res://scripts/item_sheet_state.gd")._valid_recipe(row.appearance):return false
			bytes+=12+row.appearance.layers.size()*16
			for key in ["tile_pages","palettes"]:
				for name in row.appearance[key]:bytes+=4+name.to_utf8_buffer().size()
	if bytes>384*1024 or _candidate_bytes+bytes>MAX_RETAINED_BYTES:return false
	_candidate_bytes+=bytes;return true
func _candidate_page() -> void:
	if service==null:_candidate_reject({});return
	var intent: Dictionary={"action":C.ManagementAction.NoblesCandidates,"offset":_candidate_pending.size(),"limit":32,"expected_list_revision":_revision,"choices":choices.duplicate(true),"target":candidate_target.duplicate(true),"expected_candidate_revision":_candidate_revision}
	var owner:=generation
	ticket=service.submit("nobles",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("nobles",{})
		if typeof(value)!=TYPE_DICTIONARY or result.get("action")!=intent.action or result.get("outcome","")=="unknown" or result.get("status")!=C.ManagementStatus.Ok or value.get("outcome")!=C.NoblesOutcome.None:
			_candidate_reject(result);return
		if not _valid_candidates(value,intent):_candidate_reject(result);return
		_candidate_revision=value.candidate_revision;_candidate_total=value.total;_candidate_pending.append_array(value.candidates.duplicate(true))
		if _candidate_pending.size()<_candidate_total:_candidate_page();return
		candidates=_candidate_pending;_candidate_pending=[];_candidate_seen={};phase=Phase.CandidatesReady;changed.emit())
	if ticket==0:_candidate_reject({})
	changed.emit()

# User dismissal applies the accumulated native draft. close() is reserved for
# owner teardown/session loss; it must never be used as the product Back action.
func request_dismiss() -> void:
	if phase==Phase.Symbols:symbols.dismiss();return
	if phase in [Phase.CandidatesReading,Phase.CandidatesReady]:cancel_appointment();return
	if phase!=Phase.Ready:return
	if choices.is_empty():close();dismissed.emit();return
	if service==null:last_result={"outcome":"not_sent"};phase=Phase.Rejected;changed.emit();return
	_retire();phase=Phase.Applying;last_result={}
	var intent: Dictionary={"action":C.ManagementAction.NoblesCommit,"offset":0,"limit":32,"expected_list_revision":_revision,"choices":choices.duplicate(true)}
	var owner:=generation
	ticket=service.submit("nobles",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;last_result=result.duplicate(true)
		var value: Variant=result.get("nobles",{})
		if result.get("outcome","")=="not_sent":phase=Phase.Rejected;changed.emit();return
		if result.get("outcome","")=="unknown" or typeof(value)!=TYPE_DICTIONARY or result.get("action")!=intent.action:
			phase=Phase.Unknown;changed.emit();return
		if result.get("status")==C.ManagementStatus.Ok and value.get("outcome")==C.NoblesOutcome.Applied:
			close();dismissed.emit();return
		if result.get("status")==C.ManagementStatus.Rejected and value.get("outcome") in [C.NoblesOutcome.Rejected,C.NoblesOutcome.Stale]:phase=Phase.Rejected
		else:phase=Phase.Unknown
		changed.emit())
	if ticket==0:last_result={"outcome":"not_sent"};phase=Phase.Rejected
	changed.emit()

func set_accounting(target: Dictionary,setting: int) -> void:
	if phase!=Phase.Ready or setting<0 or setting>4 or service==null:return
	var expected: int=-1
	for row in rows:
		if office(row)==target and row.unit_id>=0 and row.get("help",{}).has("accounting"):expected=row.help.accounting.setting;break
	if expected<0:return
	_retire();phase=Phase.Accounting;last_result={}
	var intent: Dictionary={"action":C.ManagementAction.NoblesAccounting,"offset":0,"limit":32,"expected_list_revision":_revision,"choices":choices.duplicate(true),"target":target.duplicate(true),"expected_setting":expected,"setting":setting}
	var owner:=generation
	ticket=service.submit("nobles",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;last_result=result.duplicate(true);var value: Variant=result.get("nobles",{})
		if result.get("outcome","")=="not_sent":phase=Phase.Rejected;changed.emit();return
		if result.get("outcome","")=="unknown" or typeof(value)!=TYPE_DICTIONARY or result.get("action")!=intent.action:
			phase=Phase.Unknown;changed.emit();return
		if result.get("status")==C.ManagementStatus.Ok and value.get("outcome")==C.NoblesOutcome.Applied:
			_pending=[];_seen={};_bytes=0;_total=0;_restarts=0;phase=Phase.Reading;_page();return
		if result.get("status")==C.ManagementStatus.Rejected and value.get("outcome") in [C.NoblesOutcome.Rejected,C.NoblesOutcome.Stale]:phase=Phase.Rejected
		else:phase=Phase.Unknown
		changed.emit())
	if ticket==0:last_result={"outcome":"not_sent"};phase=Phase.Rejected
	changed.emit()
