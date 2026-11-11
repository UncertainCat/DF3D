extends RefCounted
# Implements the shared native naming view interface. The symbol owner keeps
# transport lifetime and the opaque token; this object owns only page selection.
signal changed
enum Phase {Closed,Reading,Ready,Editing,Rejected}
var phase:=Phase.Closed
var _owner: WeakRef
var parent:
	get:return _owner.get_ref() if _owner!=null else null
var component:=0
var query:=PackedByteArray()
var rows: Array=[]
var snapshot: Dictionary={}
var revision:=0
var _pending: Array=[]
var _total:=-1
var _bytes:=0
func configure(owner) -> void:_owner=weakref(owner)
func reset() -> void:
	phase=Phase.Closed;component=0;query=PackedByteArray();rows=[];snapshot={};revision=0;_pending=[];_total=-1;_bytes=0;changed.emit()
func open() -> void:reset();_read(0)
func done() -> void:
	if phase in [Phase.Ready,Phase.Rejected] and not parent.busy():parent.continue_step()
func set_choices(selected: int,filter_bytes: PackedByteArray) -> void:
	if parent.phase!=parent.Phase.Naming or parent.busy() or selected<0 or selected>6 or filter_bytes.size()>10:return
	if selected==component and filter_bytes==query:return
	component=selected;query=filter_bytes.duplicate();_read(0)
func choose(index: int) -> void:
	if index>=0 and index<rows.size():_edit(1,component,rows[index].word,rows[index].part)
func clear_component(target: int) -> void:_edit(0,target)
func random_component(target: int) -> void:
	if not rows.is_empty():_edit(2,target)
func random_whole() -> void:_edit(3,-1)
func _edit(mode: int,target: int,word: int=-1,part: int=-1) -> void:
	if phase!=Phase.Ready or parent.busy():return
	var intent: Dictionary=parent.step_intent(parent.C.ManagementAction.NoblesSymbolNameEdit)
	intent.expected_name_revision=revision
	intent.name_edit={"mode":mode,"target":target,"displayed":-1 if mode==3 else component,"word":word,"part":part,"query_bytes":[] if mode==3 else Array(query)}
	phase=Phase.Editing;parent._request(intent,func(result):
		var value: Dictionary=result.get("nobles",{})
		if result.get("status")==parent.C.ManagementStatus.Ok and result.get("action")==intent.action and value.get("outcome")==parent.C.NoblesOutcome.Applied:_read(0);return
		parent.last_result=result.duplicate(true)
		if result.get("outcome","")=="unknown" or value.get("outcome")==parent.C.NoblesOutcome.Unknown:parent.phase=parent.Phase.Unknown
		phase=Phase.Rejected;changed.emit())
func _read(cursor: int) -> void:
	if cursor==0:_pending=[];rows=[];_total=-1;_bytes=0;revision=0
	phase=Phase.Reading
	var intent: Dictionary=parent.step_intent(parent.C.ManagementAction.NoblesSymbolNameRead)
	intent.expected_name_revision=revision;intent.name_query={"component":component,"query_bytes":Array(query),"cursor":cursor}
	parent._request(intent,func(result):
		var value: Dictionary=result.get("nobles",{});var name: Dictionary=value.get("name",{})
		if result.get("status")!=parent.C.ManagementStatus.Ok or result.get("action")!=intent.action or value.get("outcome")!=parent.C.NoblesOutcome.None or value.get("step")!=parent.step or not _valid_page(name,cursor):
			parent.last_result=result.duplicate(true);phase=Phase.Rejected;rows=[];changed.emit();return
		revision=name.revision;_total=name.total;_pending.append_array(name.choices.duplicate(true));snapshot={"native_header":name.native_header,"english_header":name.english_header,"value":name.value.duplicate(true)}
		if name.next_cursor>0:_read(name.next_cursor);return
		rows=_pending;_pending=[];phase=Phase.Ready;changed.emit())
func _valid_page(n: Dictionary,cursor: int) -> bool:
	if n.get("artifact_id")!=parent.step.naming_artifact_id or n.get("component")!=component or n.get("query_bytes")!=Array(query) or n.get("cursor")!=cursor:return false
	if typeof(n.get("revision"))!=TYPE_INT or n.revision<=0 or (revision and n.revision!=revision) or not n.get("choices") is Array or n.choices.size()>128:return false
	if typeof(n.get("total"))!=TYPE_INT or n.total<0 or (_total>=0 and n.total!=_total) or cursor+n.choices.size()>n.total:return false
	var end: int=cursor+n.choices.size()
	if n.get("next_cursor")!=(end if end<n.total else 0) or (end<n.total and n.choices.is_empty()):return false
	if not n.get("value") is Dictionary or not n.value.get("words") is Array or n.value.words.size()!=7:return false
	for key in ["native_header","english_header"]:
		if typeof(n.get(key))!=TYPE_STRING:return false
	for row in n.choices:
		if not row is Dictionary or typeof(row.get("word"))!=TYPE_INT or row.word<0 or typeof(row.get("part"))!=TYPE_INT or row.part<0 or row.part>8:return false
		for key in ["english","translated"]:
			if typeof(row.get(key))!=TYPE_STRING:return false
			_bytes+=row[key].to_utf8_buffer().size()
		_bytes+=64
	return _bytes<=64*1024*1024
