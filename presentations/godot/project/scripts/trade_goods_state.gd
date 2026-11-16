extends "res://scripts/trade_catalog_state.gd"
# The catalog/session owner also owns the draft revision. Both visible sides are
# published together; selection and filtering remain native semantic intents.
var pages: Array=[{},{}]
var counter_page: Dictionary={}
var counter_offset:=0
var counter_limit:=16
var offsets: Array[int]=[0,0]
var limits: Array[int]=[16,16]
var _pending_pages: Array=[{},{}]
var _queued_filters: Dictionary={}
var appearances: Dictionary={}
var _inspection
var _appearance_queue: Array=[]
var _appearance_id: int=-1
func configure(source) -> void:
	super.configure(source)
	if not session_opened.is_connected(_load_goods):session_opened.connect(_load_goods)
	if service!=null:
		_inspection=preload("res://scripts/item_sheet_state.gd").new();_inspection.configure(service)
		_inspection.changed.connect(_inspection_changed)
func dispose() -> void:
	super.dispose()
	if _inspection!=null:_inspection.dispose();_inspection=null
func close() -> void:
	pages=[{},{}];counter_page={};counter_offset=0;_pending_pages=[{},{}];offsets=[0,0];_queued_filters={}
	appearances={};_retire_appearance()
	super.close()
func _retire_appearance() -> void:
	_appearance_queue=[];_appearance_id=-1
	if _inspection!=null:_inspection.close()
func item_type(id: int) -> int:
	for page in pages+[counter_page]:
		for row in page.get("rows",[]):
			if not row.group and row.id==id:return row.type
	return -1
func request_appearances(ids: Array) -> void:
	if not goods_ready() or _inspection==null or ids.size()>64:return
	for id in ids:
		if typeof(id)!=TYPE_INT or item_type(id)<0:return
	for id in appearances.keys():
		if item_type(id)<0:appearances.erase(id)
	for id in ids:
		if not appearances.has(id) and id!=_appearance_id and not _appearance_queue.has(id):_appearance_queue.append(id)
	_next_appearance()
func appearance_pending() -> bool:return _appearance_id>=0 or not _appearance_queue.is_empty()
func _next_appearance() -> void:
	if not goods_ready() or _inspection==null or _appearance_id>=0:return
	while not _appearance_queue.is_empty() and item_type(_appearance_queue[0])<0:_appearance_queue.pop_front()
	if _appearance_queue.is_empty():return
	_appearance_id=_appearance_queue.pop_front();_inspection.open(_appearance_id)
func _inspection_changed() -> void:
	if _appearance_id<0 or not goods_ready() or _inspection.phase in [_inspection.Phase.Closed,_inspection.Phase.Reading]:return
	var id:=_appearance_id;_appearance_id=-1
	if item_type(id)>=0:
		appearances[id]={}
		if _inspection.phase==_inspection.Phase.Ready:
			var value: Dictionary=_inspection.snapshot
			if value.id==id and value.item_type==item_type(id) and value.has("appearance"):appearances[id]=value.appearance.duplicate(true)
	changed.emit();_next_appearance()
func goods_ready() -> bool:
	return phase==Phase.Active and not pages[0].is_empty() and not pages[1].is_empty()
func refresh_session() -> void:
	_load_goods()
func read_counter_page(offset: int,limit: int) -> void:
	if not goods_ready() or counter_page.is_empty() or offset<0 or offset>=counter_page.total or limit<1 or limit>64:return
	counter_offset=offset;counter_limit=limit;_load_goods()
func read_page(side: int,offset: int,limit: int) -> void:
	if not goods_ready() or side<0 or side>1 or offset<0 or limit<1 or limit>64:return
	offsets[side]=mini(offset,maxi(0,int(pages[side].total)-1));limits[side]=limit
	_load_goods()
func _load_goods() -> void:
	if phase!=Phase.Active or session<=0 or service==null:return
	_retire_appearance()
	phase=Phase.GoodsReading;_pending_pages=[{},{}];changed.emit()
	if phase==Phase.GoodsReading:_read_side(0,0)
func _read_side(side: int,offset: int) -> void:
	var owner:=generation
	var intent: Dictionary={"action":C.ManagementAction.TradeDraftRead,"session":session,"expected_revision":revision,"side":side,"offset":offset,"limit":limits[side]}
	ticket=service.submit("trade_draft",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("trade_draft")
		if not _receipt(result,value,intent.action,revision) or not _valid_page(value.get("page"),side,offset,limits[side]):
			_fail_goods(result);return
		var page: Dictionary=value.page
		# A collapse/filter may reduce the list. Read its new size before asking
		# for the retained offset, without exposing an intermediate page.
		var target: int=mini(offsets[side],maxi(0,int(page.total)-1))
		if offset!=target:offsets[side]=target;_read_side(side,target);return
		offsets[side]=offset;_pending_pages[side]=page.duplicate(true)
		if side==0:_read_side(1,0)
		else:_read_summary())
	if ticket==0:phase=Phase.Unavailable;changed.emit()
func _read_summary() -> void:
	var owner:=generation
	var intent: Dictionary={"action":C.ManagementAction.TradeSessionRead,"session":session,"expected_revision":revision,"columns":header_columns}
	ticket=service.submit("trade_session",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("trade_session")
		if not _receipt(result,value,intent.action,revision) or not _valid_footer(value.get("footer")) or not _valid_header(value.get("header"),header_columns) or not _valid_conversation(value.get("conversation")):
			_fail_goods(result);return
		if value.conversation.requested_items.is_empty():_publish_goods(value,{})
		else:_read_counter(value.duplicate(true)))
	if ticket==0:phase=Phase.Unavailable;changed.emit()
func _read_counter(summary: Dictionary) -> void:
	var owner:=generation
	counter_offset=mini(counter_offset,maxi(0,summary.conversation.requested_items.size()-1))
	var intent: Dictionary={"action":C.ManagementAction.TradeDraftRead,"session":session,"expected_revision":revision,"side":2,"offset":counter_offset,"limit":counter_limit}
	ticket=service.submit("trade_draft",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("trade_draft")
		if not _receipt(result,value,intent.action,revision) or not _valid_counter(value.get("page"),summary.conversation.requested_items,intent.offset,intent.limit):
			_fail_goods(result);return
		_publish_goods(summary,value.page))
	if ticket==0:phase=Phase.Unavailable;changed.emit()
func _publish_goods(summary: Dictionary,counter: Dictionary) -> void:
	footer=summary.footer.duplicate(true);header=summary.header.duplicate(true);conversation=summary.conversation.duplicate(true)
	counter_page=counter.duplicate(true);pages=_pending_pages;_pending_pages=[{},{}]
	if counter_page.is_empty():counter_offset=0
	phase=Phase.Active;changed.emit();_drain_filter()
func _valid_counter(value: Variant,ids: Array,offset: int,limit: int) -> bool:
	if not _valid_page(value,2,offset,limit) or value.total!=ids.size() or value.query!="":return false
	if typeof(value.get("heading"))!=TYPE_ARRAY or value.heading.size()!=2 or typeof(value.get("dismiss"))!=TYPE_STRING or value.dismiss.is_empty() or value.dismiss.to_utf8_buffer().size()>128:return false
	for line in value.heading:
		if typeof(line)!=TYPE_STRING or line.is_empty() or line.to_utf8_buffer().size()>512:return false
	for i in value.rows.size():
		var row: Dictionary=value.rows[i]
		if row.id!=ids[offset+i] or row.group or row.parent!=-1 or row.flags!=0 or row.expanded or row.expandable:return false
	return true
func exchange() -> void:
	_session_action(C.ManagementAction.TradeSessionExchange)
func offer_gift() -> void:
	_session_action(C.ManagementAction.TradeSessionGift)
func seize() -> void:
	_session_action(C.ManagementAction.TradeSessionSeize)
func dismiss_counteroffer() -> void:
	if counter_page.is_empty() or counter_page.total==0:return
	_session_action(C.ManagementAction.TradeSessionDismiss)
func _session_action(action: int) -> void:
	if not goods_ready() or service==null or not _queued_filters.is_empty() or revision==9223372036854775807:return
	var owner:=generation
	var expected:=revision+1
	var intent: Dictionary={"action":action,"session":session,"expected_revision":revision}
	phase=Phase.Exchanging;_retire_appearance();changed.emit()
	if owner!=generation or phase!=Phase.Exchanging:return
	ticket=service.submit("trade_session",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("trade_session")
		if not _receipt(result,value,intent.action,expected):
			_pending_pages=[{},{}];_queued_filters={}
			var definite: bool=result.get("outcome")!="unknown" and (result.get("status")==C.ManagementStatus.Rejected or (typeof(value)==TYPE_DICTIONARY and value.get("outcome") in [C.TradeSessionOutcome.Rejected,C.TradeSessionOutcome.Retired]))
			phase=Phase.Rejected if definite else Phase.Unknown
			changed.emit();return
		revision=expected;phase=Phase.Active;_load_goods())
	if ticket==0:phase=Phase.Unavailable;changed.emit()
func toggle_row(side: int,index: int,expand: bool=false) -> void:
	if not goods_ready() or side<0 or side>1 or index<0 or index>=pages[side].rows.size():return
	var row: Dictionary=pages[side].rows[index]
	if row.group:
		_apply(side,C.TradeDraftOperation.ExpandGroup if expand else C.TradeDraftOperation.Group,{"type":row.type,"subtype":row.subtype})
	elif expand:
		if not row.expandable:return
		_apply(side,C.TradeDraftOperation.ExpandContainer,{"item":row.id})
	else:_apply(side,C.TradeDraftOperation.Item,{"item":row.id})
func mark_all(side: int,selected: bool) -> void:
	_apply(side,C.TradeDraftOperation.MarkAll if selected else C.TradeDraftOperation.UnmarkAll,{})
func set_filter(side: int,query: String) -> void:
	if side<0 or side>1 or query.to_utf8_buffer().size()>256 or phase not in [Phase.Active,Phase.Applying,Phase.GoodsReading]:return
	_queued_filters[side]=query;_drain_filter()
func _drain_filter() -> void:
	if not goods_ready():return
	for side in range(2):
		if not _queued_filters.has(side):continue
		var query: String=_queued_filters[side];_queued_filters.erase(side)
		if query==pages[side].query:continue
		_apply(side,C.TradeDraftOperation.Filter,{"query":query});return
func _apply(side: int,operation: int,arguments: Dictionary) -> void:
	if not goods_ready() or side<0 or side>1 or revision==9223372036854775807:return
	var owner:=generation
	var expected:=revision+1
	var intent: Dictionary={"action":C.ManagementAction.TradeDraftApply,"session":session,"expected_revision":revision,"side":side,"operation":operation}
	intent.merge(arguments);phase=Phase.Applying;changed.emit()
	_retire_appearance()
	if generation!=owner or phase!=Phase.Applying:return
	ticket=service.submit("trade_draft",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("trade_draft")
		if not _receipt(result,value,intent.action,expected) or value.has("page"):_fail_goods(result);return
		revision=expected;phase=Phase.Active;_load_goods())
	if ticket==0:phase=Phase.Unavailable;changed.emit()
func _receipt(result: Dictionary,value: Variant,action: int,expected: int) -> bool:
	return result.get("outcome")!="unknown" and result.get("status")==C.ManagementStatus.Ok and result.get("action")==action and typeof(value)==TYPE_DICTIONARY and value.get("outcome")==C.TradeSessionOutcome.Available and typeof(value.get("session"))==TYPE_INT and value.session==session and typeof(value.get("revision"))==TYPE_INT and value.revision==expected
func _fail_goods(result: Dictionary) -> void:
	_pending_pages=[{},{}];_queued_filters={}
	phase=Phase.Unknown if result.get("outcome")=="unknown" else Phase.Rejected
	changed.emit()
func _valid_page(value: Variant,side: int,offset: int,limit: int) -> bool:
	if typeof(value)!=TYPE_DICTIONARY:return false
	for key in ["side","offset","total"]:
		if typeof(value.get(key))!=TYPE_INT:return false
	if value.side!=side or value.offset!=offset or value.total<offset or value.total>4294967295 or typeof(value.get("query"))!=TYPE_STRING or value.query.to_utf8_buffer().size()>1024 or typeof(value.get("rows"))!=TYPE_ARRAY or value.rows.size()!=mini(limit,value.total-offset):return false
	# The adapter validates row semantics. Guard dictionary ownership/types here
	# as well, since stale or malformed replies must never become active controls.
	for row in value.rows:
		if typeof(row)!=TYPE_DICTIONARY:return false
		for key in ["group","expanded","expandable"]:
			if typeof(row.get(key))!=TYPE_BOOL:return false
		for key in ["id","parent","type","subtype","amount","flags","value","appraisal","disposition","contained_count"]:
			if typeof(row.get(key))!=TYPE_INT:return false
		for key in ["caption","value_caption","weight_caption","contents_caption"]:
			if typeof(row.get(key))!=TYPE_STRING:return false
	return true
