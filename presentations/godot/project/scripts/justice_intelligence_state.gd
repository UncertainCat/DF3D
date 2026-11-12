extends RefCounted
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Rejected,Unavailable}
var service
var mode:=0
var graph_selected:=0
var graph_scroll:=0
var selected_node: int=-1
func select_mode(value: int) -> void:
	if value<0 or value>3 or value==mode:return
	if value==0:
		if phase!=Phase.Ready or rows.is_empty():return
	elif graph.phase!=graph.Phase.Ready or graph.graph[["actors","organizations","plots"][value-1]].is_empty():return
	mode=value;graph_selected=0;graph_scroll=0;selected_node=-1;changed.emit()
func select_graph_row(index: int) -> void:
	if mode==0 or graph.phase!=graph.Phase.Ready:return
	if index<0 or index>=graph.graph[["actors","organizations","plots"][mode-1]].size():return
	graph_selected=index;selected_node=-1;changed.emit()
var graph=preload("res://scripts/justice_graph_state.gd").new()
func _init() -> void:graph.changed.connect(_graph_changed)
func _graph_changed() -> void:changed.emit()
var phase:=Phase.Closed
var rows: Array=[]
var lines: Array=[]
var selected: int=-1
var columns:=112
var first:=0
var revision:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
var _pending: Array=[]
var _total:=0
func configure(source) -> void:
	dispose();service=source
	graph.configure(source)
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	graph.dispose()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _retire() -> void:
	generation+=1;var old:=ticket;ticket=0
	if service!=null and old!=0:service.detach(old)
	_pending=[]
func close() -> void:
	graph.close()
	mode=0;graph_selected=0;graph_scroll=0;selected_node=-1
	_retire();rows=[];lines=[];selected=-1;first=0;revision=0;phase=Phase.Closed;last_result={};changed.emit()
func _session_changed() -> void:close();phase=Phase.Unavailable;changed.emit()
func open() -> void:close();phase=Phase.Reading;graph.open();_page()
func select_report(index: int) -> void:
	if phase!=Phase.Ready or not rows.any(func(row):return row.index==index):return
	_retire();selected=index;lines=[];first=0;phase=Phase.Reading;_page()
func resize_columns(value: int) -> void:
	value=clampi(value,1,512)
	if columns==value:return
	columns=value
	if selected>=0 and phase in [Phase.Reading,Phase.Ready]:
		_retire();lines=[];first=0;phase=Phase.Reading;_page()
func seek(value: int,capacity: int) -> void:
	if phase!=Phase.Ready:return
	first=clampi(value,0,maxi(0,(rows.size() if selected<0 else lines.size())-maxi(1,capacity)));changed.emit()
func _fail(result: Dictionary) -> void:
	_pending=[];lines=[];last_result=result.duplicate(true);phase=Phase.Rejected;changed.emit()
func _page() -> void:
	if service==null:phase=Phase.Unavailable;changed.emit();return
	var intent:={"action":C.ManagementAction.JusticeIntelligenceRead,"tab":5,"offset":_pending.size(),"limit":32,"expected_list_revision":revision,"report_index":selected,"text_columns":0 if selected<0 else columns}
	var owner:=generation
	ticket=service.submit("justice",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("justice",{})
		if result.get("action")!=intent.action or result.get("status")!=C.ManagementStatus.Ok or result.get("outcome","")=="unknown" or typeof(value)!=TYPE_DICTIONARY:_fail(result);return
		if value.get("outcome")!=C.JusticeOutcome.None or value.get("tab")!=5 or typeof(value.get("list_revision"))!=TYPE_INT or value.list_revision<=0 or (revision!=0 and value.list_revision!=revision) or typeof(value.get("total"))!=TYPE_INT or value.total<0 or value.total>1048576 or value.get("offset")!=intent.offset:_fail(result);return
		var page: Variant=value.get("intelligence",{})
		if typeof(page)!=TYPE_DICTIONARY or page.get("report_index")!=selected or page.get("text_columns")!=intent.text_columns:_fail(result);return
		var entries: Variant=page.get("reports" if selected<0 else "lines")
		if typeof(entries)!=TYPE_ARRAY or entries.size()>intent.limit or intent.offset+entries.size()>value.total or (intent.offset<value.total and entries.is_empty()) or (intent.offset>0 and value.total!=_total):_fail(result);return
		for i in entries.size():
			if selected<0:
				var row: Variant=entries[i]
				if typeof(row)!=TYPE_DICTIONARY or row.get("index")!=intent.offset+i or typeof(row.get("title"))!=TYPE_STRING or typeof(row.get("officer"))!=TYPE_STRING or typeof(row.get("viewed"))!=TYPE_BOOL:_fail(result);return
			elif typeof(entries[i])!=TYPE_STRING:_fail(result);return
		revision=value.list_revision;_total=value.total;_pending.append_array(entries.duplicate(true))
		if _pending.size()<_total:_page();return
		if selected<0:rows=_pending
		else:lines=_pending
		_pending=[];phase=Phase.Ready;changed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
