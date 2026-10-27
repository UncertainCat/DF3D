extends RefCounted
# Local editor ownership. DF supplies every name, choice and mutation outcome.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Loading, Ready, Editing, Rejected, Stale, Unknown, Unavailable }
var phase:=Phase.Closed
var service
var identity: Dictionary={}
var snapshot: Dictionary={}
var component:=0
var query:=PackedByteArray()
var rows: Array=[]
var ticket:=0
var generation:=0
var queue: Array[Dictionary]=[]
var _pending: Array=[]
var _total:=-1

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)

func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null

func close() -> void:
	generation+=1
	var previous:=ticket
	ticket=0;identity={};snapshot={};rows=[];_pending=[];queue.clear();_total=-1
	component=0;query=PackedByteArray();phase=Phase.Closed
	if service!=null and previous!=0:service.detach(previous)
	changed.emit()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func open(target: Dictionary) -> void:
	close()
	for key in ["site_id","id"]:
		if typeof(target.get(key))!=TYPE_INT or target[key]<0 or target[key]>2147483647:
			_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	identity={"site_id":target.site_id,"id":target.id};phase=Phase.Reading
	_send(_intent(C.AreaOperation.LocationNameRead))

func set_choices(selected: int, filter_bytes: PackedByteArray) -> void:
	if phase not in [Phase.Reading,Phase.Loading,Phase.Ready,Phase.Editing] or selected<0 or selected>6 or filter_bytes.size()>10:return
	if selected==component and filter_bytes==query:return
	component=selected;query=filter_bytes.duplicate();rows=[];_pending=[];_total=-1
	if phase in [Phase.Reading,Phase.Editing]:changed.emit();return
	var previous:=ticket;ticket=0
	if previous!=0:service.detach(previous)
	_read_page(0)

func choose(index: int) -> void:
	if index<0 or index>=rows.size():return
	_enqueue(C.LocationNameMode.SelectWord,component,rows[index].word,rows[index].part)

func clear_component(target: int) -> void:
	_enqueue(C.LocationNameMode.Clear,target)

func random_component(target: int) -> void:
	# Native empty-list Random has no effects, including no RNG consumption.
	if rows.is_empty():return
	_enqueue(C.LocationNameMode.RandomComponent,target)

func random_whole() -> void:
	_enqueue(C.LocationNameMode.RandomWhole,-1)

func _enqueue(mode: int, target: int, word: int=-1, part: int=-1) -> void:
	if phase not in [Phase.Ready,Phase.Editing] or (mode!=C.LocationNameMode.RandomWhole and (target<0 or target>6)):return
	queue.append({"mode":mode,"target":target,"displayed":-1 if mode==C.LocationNameMode.RandomWhole else component,
		"word":word,"part":part,"query_bytes":PackedByteArray() if mode==C.LocationNameMode.RandomWhole else query.duplicate()})
	if ticket==0:_next_edit()

func _intent(operation: int) -> Dictionary:
	return {"action":C.ManagementAction.AreaInspect,"operation":operation,"kind":C.AreaKind.Zone,
		"location_site_id":identity.site_id,"location_id":identity.id}

func _next_edit() -> void:
	if queue.is_empty():_read_page(0);return
	var intent:=_intent(C.AreaOperation.LocationNameEdit);intent.action=C.ManagementAction.AreaUpdate
	intent.expected_revision=snapshot.revision;intent.name_edit=queue.pop_front();phase=Phase.Editing
	_send(intent)

func _read_page(cursor: int) -> void:
	if cursor==0:_pending=[];_total=-1;rows=[]
	phase=Phase.Loading
	var intent:=_intent(C.AreaOperation.LocationNameChoices);intent.expected_revision=snapshot.revision
	intent.name_query={"component":component,"query_bytes":query.duplicate(),"cursor":cursor}
	_send(intent)

func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("areas",intent,func(received,result,sent):
		if generation==owner and ticket==received:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()

func _fail(next: Phase) -> void:
	ticket=0;rows=[];snapshot={};_pending=[];queue.clear();_total=-1;phase=next;changed.emit()

func _valid_snapshot(value: Dictionary) -> bool:
	return (value.get("site_id")==identity.site_id and value.get("id")==identity.id
		and typeof(value.get("revision"))==TYPE_INT and value.revision>0
		and value.get("kind") in [1,2,3,4,5] and typeof(value.get("native_header"))==TYPE_STRING
		and typeof(value.get("english_header"))==TYPE_STRING and typeof(value.get("value"))==TYPE_DICTIONARY)

func _receive(result: Dictionary, sent: Dictionary) -> void:
	ticket=0
	var area: Dictionary=result.get("area",{})
	if result.get("outcome","")=="unknown" or area.get("location_edit_outcome")==C.LocationEditOutcome.Unknown:
		_fail(Phase.Unknown);return
	if result.get("status")!=C.ManagementStatus.Ok:
		_fail(Phase.Stale if area.get("location_edit_outcome")==C.LocationEditOutcome.Stale else Phase.Rejected);return
	if result.get("action")!=sent.action or area.get("operation")!=sent.operation:_fail(Phase.Rejected);return
	if sent.operation!=C.AreaOperation.LocationNameChoices:
		var value: Dictionary=area.get("location_name",{})
		if not _valid_snapshot(value):_fail(Phase.Rejected);return
		if sent.operation==C.AreaOperation.LocationNameEdit and area.get("location_edit_outcome")!=C.LocationEditOutcome.Completed:
			_fail(Phase.Rejected);return
		snapshot=value.duplicate(true)
		if sent.operation==C.AreaOperation.LocationNameEdit:
			var owner:=generation;applied.emit()
			if owner!=generation:return
			_next_edit()
		else:_read_page(0)
		return
	var page: Dictionary=area.get("location_name_page",{})
	if page.get("snapshot")!=snapshot or page.get("component")!=component or page.get("query_bytes")!=query:
		_fail(Phase.Rejected);return
	for key in ["cursor","next_cursor","total"]:
		if typeof(page.get(key))!=TYPE_INT:_fail(Phase.Rejected);return
	if typeof(page.get("choices"))!=TYPE_ARRAY or typeof(page.get("truncated"))!=TYPE_BOOL:
		_fail(Phase.Rejected);return
	var batch: Array=page.choices
	var end: int=page.cursor+batch.size()
	if (page.cursor!=_pending.size() or page.cursor!=sent.name_query.cursor or page.total<end or page.total>2147483647
		or batch.size()>128 or page.truncated!=(end<page.total) or page.next_cursor!=(end if page.truncated else 0)
		or (page.truncated and batch.is_empty()) or (_total!=-1 and _total!=page.total)):
		_fail(Phase.Rejected);return
	for row in batch:
		if (typeof(row)!=TYPE_DICTIONARY or typeof(row.get("word"))!=TYPE_INT or row.word<0 or row.word>2147483647
			or typeof(row.get("part"))!=TYPE_INT or row.part<0 or row.part>8
			or typeof(row.get("english"))!=TYPE_STRING or typeof(row.get("translated"))!=TYPE_STRING):
			_fail(Phase.Rejected);return
	_total=page.total;_pending.append_array(batch.duplicate(true))
	if page.truncated:_read_page(page.next_cursor);return
	rows=_pending;_pending=[];phase=Phase.Ready;changed.emit()
