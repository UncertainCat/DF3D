extends RefCounted
signal changed
const C=preload("res://scripts/management_contract.gd")
const KEYS=["actors","organizations","plots","nodes"]
const COUNTS=["actor_count","organization_count","plot_count","node_count"]
enum Phase {Closed,Reading,Ready,Rejected,Unavailable}
var service
var phase:=Phase.Closed
var graph: Dictionary={}
var revision:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
var _pending: Dictionary={}
var _counts: Array=[]
var _kind:=1
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func close() -> void:
	generation+=1;var old:=ticket;ticket=0
	if service!=null and old!=0:service.detach(old)
	graph={};_pending={};_counts=[];revision=0;_kind=1;last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:close();phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();phase=Phase.Reading
	for key in KEYS:_pending[key]=[]
	_page()
func _fail(result: Dictionary) -> void:
	_pending={};graph={};last_result=result.duplicate(true);phase=Phase.Rejected;changed.emit()
func _links_valid() -> bool:
	var first:=0
	for org_index in _pending.organizations.size():
		var org: Dictionary=_pending.organizations[org_index]
		if org.first_node!=first or org.node_count<0 or first+org.node_count>_pending.nodes.size():return false
		for i in org.node_count:
			var node: Dictionary=_pending.nodes[first+i]
			if node.organization!=org_index or node.parent< -1 or (node.parent!=-1 and (node.parent<first or node.parent>=first+org.node_count)):return false
		first+=org.node_count
	return first==_pending.nodes.size()
func _page() -> void:
	if service==null:phase=Phase.Unavailable;changed.emit();return
	var key: String=KEYS[_kind-1]
	var intent:={"action":C.ManagementAction.JusticeIntelligenceGraphRead,"tab":5,"offset":_pending[key].size(),"limit":32,"expected_list_revision":revision,"graph_kind":_kind}
	var owner:=generation
	ticket=service.submit("justice",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("justice",{})
		if result.get("action")!=intent.action or result.get("status")!=C.ManagementStatus.Ok or result.get("outcome","")=="unknown" or typeof(value)!=TYPE_DICTIONARY:_fail(result);return
		if value.get("outcome")!=C.JusticeOutcome.None or value.get("tab")!=5 or typeof(value.get("list_revision"))!=TYPE_INT or value.list_revision<=0 or (revision!=0 and value.list_revision!=revision) or value.get("offset")!=intent.offset:_fail(result);return
		var page: Variant=value.get("graph",{})
		if typeof(page)!=TYPE_DICTIONARY or page.get("kind")!=_kind:_fail(result);return
		var counts: Array=[]
		for name in COUNTS:
			var count: Variant=page.get(name)
			if typeof(count)!=TYPE_INT or count<0 or count>65536:_fail(result);return
			counts.append(count)
		if not _counts.is_empty() and counts!=_counts:_fail(result);return
		for i in KEYS.size():
			if typeof(page.get(KEYS[i]))!=TYPE_ARRAY or (i!=_kind-1 and not page[KEYS[i]].is_empty()):_fail(result);return
		var entries: Array=page[key]
		if value.get("total")!=counts[_kind-1] or entries.size()>intent.limit or intent.offset+entries.size()>value.total or (intent.offset<value.total and entries.is_empty()):_fail(result);return
		for row in entries:
			if typeof(row)!=TYPE_DICTIONARY:_fail(result);return
		revision=value.list_revision;_counts=counts;_pending[key].append_array(entries.duplicate(true))
		if _pending[key].size()<value.total:_page();return
		if _kind<4:_kind+=1;_page();return
		if not _links_valid():_fail(result);return
		graph=_pending;_pending={};phase=Phase.Ready;changed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
