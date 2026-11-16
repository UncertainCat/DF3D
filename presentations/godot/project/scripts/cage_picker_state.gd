extends RefCounted
# Each instance owns one cage surface. Parent and picker instances share request
# retirement/outcome handling, never their revisions, rows or pending edits.
signal changed
signal facts_changed
signal applied
const C=preload("res://scripts/management_contract.gd")
const Art=preload("res://scripts/original_ui.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Stale, Unknown, Unavailable }
var phase:=Phase.Closed
var service
var parent_body:=false
var building_id: int=-1
var snapshot: Dictionary={}
var rows: Array=[]
var ticket:=0
var generation:=0
var revision:=0
var receipt:=0
var cursor:=0
var query: String=""
var query_bytes:=PackedByteArray()
var sort:=2
var descending:=false
var directions: Array=[false,false,false,false]
var search_delay: float=-1
# Presentation adapter fields, never used as zone request inputs.
var area: Dictionary={}
var kind:=2
var failed:=false
var mutating:=false
var squad_first:=0
var squad_mask:=0

func configure(source,occupants: bool=false) -> void:
	dispose();parent_body=occupants;service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _retire() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	_retire();building_id=-1;area={};snapshot={};rows=[];revision=0;cursor=0
	query="";query_bytes=PackedByteArray();sort=0 if parent_body else 2;descending=false;directions=[false,false,false,false]
	search_delay=-1;failed=false;mutating=false;phase=Phase.Closed;receipt+=1;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647 or service==null:phase=Phase.Unavailable;changed.emit();return
	building_id=id;area={"id":id};_restart()
func busy() -> bool:return phase!=Phase.Ready or ticket!=0 or search_delay>=0
func can_remove_owner() -> bool:return false
func assign_owner(_id: int) -> void:pass
func toggle_squad(_id: int,_bit: int) -> void:pass
func sort_direction(value: int) -> bool:return bool(directions[value]) if value in [1,2,3] else false
func order(value: int) -> void:
	if parent_body or busy() or value not in [1,2,3]:return
	if sort==value:directions[value]=not directions[value]
	sort=value;descending=directions[value];_restart()
func queue_owner_search(value: PackedByteArray) -> void:
	if parent_body or failed or mutating or building_id<0:return
	_retire();query_bytes=value.duplicate();query=""
	# Preserve the native SDL byte textbox, including a partially deleted UTF-8
	# sequence. Wire text uses DF2UTF glyph representation; UTF2DF restores bytes.
	for byte in query_bytes:query+=String.chr(byte if byte<128 else Art.CP437_HIGH[byte-128])
	search_delay=0.15;phase=Phase.Reading;changed.emit()
func tick(delta: float) -> void:
	if search_delay<0:return
	search_delay-=delta
	if search_delay<=0:search_delay=-1;_restart()
func _restart() -> void:
	_retire();rows=[];snapshot={};revision=0;cursor=0;receipt+=1;failed=false;mutating=false
	phase=Phase.Reading;_read(0)
func more() -> void:
	if cursor>0 and ticket==0 and not failed:_read(cursor)
func _read(offset: int) -> void:
	if building_id<0:return
	var intent={"action":C.ManagementAction.ProductionInspect,"building_id":building_id,"cage_operation":2 if parent_body else 0,
		"cage_sort":sort,"cage_descending":descending,"query":query,"cursor":offset}
	if offset>0:intent.expected_revision=revision
	_send(intent)
func toggle_animal(entity: int,id: int) -> void:
	if busy() or snapshot.get("removing",true):return
	if parent_body and snapshot.get("justice_restraint",true):return
	for row in rows:
		if row.id!=id or row.entity!=entity:continue
		if parent_body and (not row.get("resolved",false) or id<0):return
		mutating=true;phase=Phase.Applying
		_send({"action":C.ManagementAction.ProductionQueue,"building_id":building_id,"cage_operation":3 if parent_body else 1,
			"cage_sort":sort,"cage_descending":descending,"query":query,"expected_revision":revision,
			"cage_candidate_id":id,"cage_entity":entity,"cage_assigned":not row.assigned})
		return
func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()
func _fail(value: Phase) -> void:
	phase=value;failed=true;mutating=false;cursor=0;snapshot={};revision=0;changed.emit()
func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var edit: bool=(sent.cage_operation&1)!=0
	var page: Dictionary=result.get("production",{}).get("cage",{})
	var row_key: String="occupants" if parent_body else "rows"
	var outcome: int=page.get("outcome",C.FarmEditOutcome.None)
	if result.get("outcome","")=="unknown" or outcome==C.FarmEditOutcome.Unknown:_fail(Phase.Unknown);return
	if result.get("status")!=C.ManagementStatus.Ok:
		_fail(Phase.Stale if outcome==C.FarmEditOutcome.Stale else Phase.Rejected);return
	var offset: int=sent.get("cursor",0)
	if result.get("action")!=sent.action or page.get("building_id")!=building_id or page.get("operation")!=sent.cage_operation or page.get("query")!=query or page.get("sort")!=sort or page.get("descending")!=descending or page.get("columns")!=27 or page.get("revision",0)<=0 or page.get("cursor")!=offset or not page.get(row_key) is Array or outcome!=(C.FarmEditOutcome.Completed if edit else C.FarmEditOutcome.None):
		_fail(Phase.Unknown if edit else Phase.Rejected);return
	if parent_body and (not page.get("justice_restraint") is bool or not page.get("rows",[1]).is_empty()):_fail(Phase.Unknown if edit else Phase.Rejected);return
	if edit and (page.get("candidate_id")!=sent.cage_candidate_id or page.get("entity")!=sent.cage_entity or page.get("assigned")!=sent.cage_assigned):_fail(Phase.Unknown);return
	if offset>0 and (offset!=rows.size() or page.revision!=revision or page.total!=snapshot.total):_fail(Phase.Stale);return
	if offset==0:rows=[]
	var identities: Dictionary={}
	for row in rows:identities[Vector2i(row.id,row.entity)]=true
	for row in page[row_key]:
		var identity:=Vector2i(row.id,row.entity)
		if not parent_body and identities.has(identity):_fail(Phase.Unknown if edit else Phase.Rejected);return
		identities[identity]=true;rows.append(row)
	if rows.size()>4096 or rows.size()>page.total or (page.next_cursor!=0 and page.next_cursor!=rows.size()) or (page.next_cursor==0 and rows.size()!=page.total):_fail(Phase.Unknown if edit else Phase.Rejected);return
	snapshot=page.duplicate();revision=page.revision;cursor=page.next_cursor;mutating=false
	phase=Phase.Reading if cursor>0 else Phase.Ready;changed.emit()
	if edit:applied.emit()
	if cursor>0:call_deferred("more")
