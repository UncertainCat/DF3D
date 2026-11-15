extends RefCounted
# Read-only native link pages; selection and scrolling belong to the viewer.
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Rejected, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0
var refresh_age:=0.0
var visible_rows:=1

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _retire() -> void:
	generation+=1
	var previous:=ticket;ticket=0;refresh_age=0.0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	_retire();building_id=-1;snapshot={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	building_id=id;_read(0,0,false)
func rows() -> Array:return snapshot.get("rows",[]).duplicate(true)
func seek(cursor: int) -> void:
	if phase not in [Phase.Ready,Phase.Reading] or snapshot.is_empty() or cursor<0 or cursor>=snapshot.total:return
	_retire()
	if cursor==snapshot.cursor:phase=Phase.Ready;changed.emit();return
	_read(cursor,int(snapshot.revision),false)
func poll_refresh(delta: float) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	refresh_age+=maxf(0,delta)
	if refresh_age>=0.5:_read(0,0,true)
func _fail(next: Phase) -> void:
	_retire();snapshot={};phase=next;changed.emit()

static func valid_page(page: Dictionary,id: int) -> bool:
	for key in ["building_id","revision","cursor","next_cursor","total"]:
		if typeof(page.get(key))!=TYPE_INT:return false
	if page.building_id!=id or page.revision<=0 or page.total<0 or page.total>32767 or page.cursor<0 or page.cursor>page.total:return false
	if typeof(page.get("tabs"))!=TYPE_BOOL or typeof(page.get("rows"))!=TYPE_ARRAY:return false
	if not page.tabs and page.total!=0:return false
	if page.rows.size()>64 or page.rows.size()>page.total-page.cursor:return false
	var end: int=page.cursor+page.rows.size()
	if end<page.total:
		if page.rows.is_empty() or page.next_cursor!=end:return false
	elif page.next_cursor!=0:return false
	if page.total>0 and page.cursor==page.total:return false
	for row in page.rows:
		if typeof(row)!=TYPE_DICTIONARY:return false
		for key in ["id","item_id","type","reference_type","x","y","z"]:
			if typeof(row.get(key))!=TYPE_INT or row[key]<0:return false
		if row.type>54 or row.reference_type not in [32,33] or typeof(row.get("name"))!=TYPE_STRING:return false
	return true

func _read(cursor: int,revision: int,background: bool,base: Dictionary={}) -> void:
	var owner:=generation
	refresh_age=0.0
	if not background:phase=Phase.Reading
	var intent={"action":C.ManagementAction.ProductionInspect,"building_links":true,"building_id":building_id,"cursor":cursor,"expected_revision":revision}
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var page: Dictionary=result.get("production",{}).get("building_links",{})
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=sent.action or result.get("outcome","")=="unknown" or not valid_page(page,building_id) or page.cursor!=sent.cursor or (sent.expected_revision>0 and page.revision!=sent.expected_revision):
			_fail(Phase.Rejected);return
		var previous: Dictionary=base if not base.is_empty() else snapshot
		if sent.expected_revision>0 and not previous.is_empty() and (page.total!=previous.total or page.tabs!=previous.tabs):_fail(Phase.Rejected);return
		if background and base.is_empty() and not snapshot.is_empty():
			if page.revision==snapshot.revision:return
			var wanted:=mini(int(snapshot.cursor),maxi(0,int(page.total)-maxi(1,visible_rows)))
			if wanted>0:_read(wanted,page.revision,true,page);return
		snapshot=page.duplicate(true);phase=Phase.Ready;changed.emit())
	if ticket==0:_fail(Phase.Unavailable)
	elif not background:changed.emit()
