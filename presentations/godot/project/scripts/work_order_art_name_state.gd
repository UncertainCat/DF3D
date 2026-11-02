extends RefCounted
# The parent owns transport tickets, epochs and the semantic artwork draft.
signal changed
enum Phase { Closed, Reading, Ready, Editing, Rejected }
var phase:=Phase.Closed
var parent
var active:=false
var component:=0
var query:=PackedByteArray()
var rows: Array=[]
var snapshot: Dictionary={}
var _pending: Array=[]
var _total:=-1
func configure(details) -> void:
	parent=details;parent.changed.connect(_sync)
func open() -> void:
	if parent.phase!=parent.Phase.Ready or parent.art_page()!=6:return
	active=true;component=0;query=PackedByteArray();snapshot={};_read(0)
func close() -> void:
	if parent.ticket!=0:return
	active=false;phase=Phase.Closed;rows=[];snapshot={};changed.emit();parent.draft_navigate(6)
func set_choices(selected: int,filter_bytes: PackedByteArray) -> void:
	if not active or selected<0 or selected>6 or filter_bytes.size()>10:return
	if selected==component and filter_bytes==query:return
	component=selected;query=filter_bytes.duplicate();rows=[]
	if parent.ticket==0:_read(0)
	changed.emit()
func choose(index: int) -> void:
	if index>=0 and index<rows.size():_edit(1,component,rows[index].word,rows[index].part)
func clear_component(target: int) -> void:_edit(0,target)
func random_component(target: int) -> void:
	if not rows.is_empty():_edit(2,target)
func random_whole() -> void:_edit(3,-1)
func _edit(mode: int,target: int,word: int=-1,part: int=-1) -> void:
	if not active or phase!=Phase.Ready or parent.ticket!=0:return
	_read(0,{"action":6,"name_edit":{"mode":mode,"target":target,"displayed":-1 if mode==3 else component,"word":word,"part":part,"query_bytes":PackedByteArray() if mode==3 else query.duplicate()}})
func _read(cursor: int,edit: Dictionary={}) -> void:
	if cursor==0:_pending=[];_total=-1;rows=[]
	phase=Phase.Editing if edit.has("name_edit") else Phase.Reading
	edit.name_query={"component":component,"query_bytes":query.duplicate(),"cursor":cursor}
	parent._read_draft(18,0,edit);changed.emit()
func _sync() -> void:
	if not active:return
	if parent.phase in [parent.Phase.Closed,parent.Phase.Rejected,parent.Phase.Unknown,parent.Phase.Unavailable]:
		active=false;phase=Phase.Closed;rows=[];snapshot={};changed.emit();return
	if parent.phase!=parent.Phase.Ready:return
	if parent.art_page()!=18:active=false;phase=Phase.Closed;changed.emit();return
	var n: Dictionary=parent.snapshot.art.get("name",{})
	if n.get("component",-1)!=component or n.get("query_bytes")!=query:_read(0);return
	if not n.get("choices") is Array or n.get("cursor",-1)!=_pending.size() or (_total!=-1 and n.get("total",-1)!=_total):
		phase=Phase.Rejected;rows=[];changed.emit();return
	_total=n.total;_pending.append_array(n.choices.duplicate(true))
	snapshot={"native_header":n.native_header,"english_header":n.english_header,"value":parent.draft_value.name.duplicate(true)}
	if n.next_cursor>0:_read(n.next_cursor);return
	rows=_pending;_pending=[];phase=Phase.Ready;changed.emit()
