extends RefCounted
# Staged merchant chooser and session ownership. Only explicit entry consumes a
# catalog token and appraises goods; later reads validate the owned session.
signal changed
signal choice_requested(depot_id: int, token: int)
signal session_opened
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Choosing,Rejected,Unknown,Unavailable,Active,Checking,GoodsReading,Applying,Exchanging}
var service
var phase:=Phase.Closed
var depot_id: int=-1
var title: String=""
var from_text: String=""
var choices: Array=[]
var ticket:=0
var generation:=0
var session: int=0
var revision: int=0
var entry: Dictionary={}
var footer: Dictionary={}
var header: Dictionary={}
var conversation: Dictionary={}
var header_columns: int=102
var _open_ticket:=0
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func close() -> void:
	generation+=1
	if service!=null:
		if _open_ticket!=0:service.retire_trade_open(_open_ticket)
		if ticket!=0 and ticket!=_open_ticket:service.detach(ticket)
		if session>0:service.submit("trade_session",{"action":C.ManagementAction.TradeSessionClose,"session":session},Callable())
	_open_ticket=0;session=0;revision=0;entry={};footer={};header={};conversation={}
	ticket=0;depot_id=-1;title="";from_text="";choices=[];phase=Phase.Closed;changed.emit()
func _session_changed() -> void:close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:return
	depot_id=id
	if service==null:phase=Phase.Unavailable;changed.emit();return
	phase=Phase.Reading
	var owner:=generation
	var intent: Dictionary={"action":C.ManagementAction.TradeCatalogRead,"depot_id":id}
	ticket=service.submit("trade_catalog",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("trade_catalog")
		if result.get("outcome")=="unknown":phase=Phase.Unknown
		elif result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=intent.action or not _valid(value,id):phase=Phase.Rejected
		else:
			title=value.title;from_text=value.from_text;choices=value.choices.duplicate(true);phase=Phase.Ready
		changed.emit()
		# Native skips the chooser when only one eligible merchant remains.
		if phase==Phase.Ready and choices.size()==1:choose(choices[0].token))
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
func choose(token: int) -> void:
	if phase!=Phase.Ready or not choices.any(func(row):return row.token==token):return
	if service==null:phase=Phase.Unavailable;changed.emit();return
	phase=Phase.Choosing
	var owner:=generation
	ticket=service.submit("trade_session",{"action":C.ManagementAction.TradeSessionOpen,"depot_id":depot_id,"choice_token":token},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("trade_session")
		if result.get("outcome")=="unknown":phase=Phase.Unknown
		elif result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=C.ManagementAction.TradeSessionOpen or not _valid_open(value):
			phase=Phase.Rejected;service.retire_trade_open(received);_open_ticket=0
		else:
			_open_ticket=0;session=value.session;revision=value.revision;entry=value.entry.duplicate(true);phase=Phase.Active
		changed.emit()
		if phase==Phase.Active:session_opened.emit())
	_open_ticket=ticket
	if ticket==0:phase=Phase.Unavailable
	changed.emit();choice_requested.emit(depot_id,token)
func refresh_session() -> void:
	if phase!=Phase.Active or service==null:return
	phase=Phase.Checking
	var owner:=generation
	ticket=service.submit("trade_session",{"action":C.ManagementAction.TradeSessionRead,"session":session,"expected_revision":revision,"columns":header_columns},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("trade_session")
		if result.get("outcome")=="unknown":phase=Phase.Unknown
		elif result.get("status")==C.ManagementStatus.Ok and result.get("action")==C.ManagementAction.TradeSessionRead and typeof(value)==TYPE_DICTIONARY and value.get("outcome")==C.TradeSessionOutcome.Available and typeof(value.get("session"))==TYPE_INT and typeof(value.get("revision"))==TYPE_INT and value.session==session and value.revision==revision and not value.has("entry") and _valid_footer(value.get("footer")) and _valid_header(value.get("header"),header_columns) and _valid_conversation(value.get("conversation")):
			footer=value.footer.duplicate(true);header=value.header.duplicate(true);conversation=value.conversation.duplicate(true);phase=Phase.Active
		else:phase=Phase.Rejected
		changed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
static func _valid_conversation(value: Variant) -> bool:
	if typeof(value)!=TYPE_DICTIONARY or typeof(value.get("dialogue"))!=TYPE_INT or value.dialogue < -1 or value.dialogue>28 or typeof(value.get("counter_offer"))!=TYPE_BOOL:return false
	if typeof(value.get("requested_items"))!=TYPE_ARRAY or value.requested_items.size()>1048576 or typeof(value.get("announcement"))!=TYPE_ARRAY or value.announcement.size()>2049:return false
	var ids: Dictionary={}
	for id in value.requested_items:
		if typeof(id)!=TYPE_INT or id<0 or id>2147483647 or ids.has(id):return false
		ids[id]=true
	var bytes:=0
	for line in value.announcement:
		if typeof(line)!=TYPE_STRING or line.to_utf8_buffer().size()>8192:return false
		bytes+=line.to_utf8_buffer().size()
	return bytes<=65536
static func _valid_header(value: Variant,columns: int) -> bool:
	if typeof(value)!=TYPE_DICTIONARY or typeof(value.get("columns"))!=TYPE_INT or value.columns!=columns or columns<1 or columns>512:return false
	if typeof(value.get("speaker"))!=TYPE_INT or value.speaker < -1 or value.speaker>2147483647:return false
	for key in ["name","mood"]:
		if typeof(value.get(key))!=TYPE_STRING or value[key].to_utf8_buffer().size()>2048:return false
	for key in ["lines","status"]:
		if typeof(value.get(key))!=TYPE_ARRAY or value[key].size()>(2049 if key=="lines" else 2):return false
		for line in value[key]:
			if typeof(line)!=TYPE_STRING or line.to_utf8_buffer().size()>2048:return false
	for key in ["mood_color","status_color"]:
		if typeof(value.get(key))!=TYPE_INT:return false
	if value.mood_color not in ([-1] if value.mood.is_empty() else [9,10,11,12,13,14,15]) or value.status_color not in ([-1] if value.status.is_empty() else [7,14]):return false
	if value.speaker>=0:
		if typeof(value.get("name_color"))!=TYPE_DICTIONARY or preload("res://scripts/native_name_color.gd").choose(value.name_color,0,0).is_empty():return false
	elif value.has("name_color") or value.has("appearance") or not value.name.is_empty():return false
	return not value.has("appearance") or typeof(value.appearance)==TYPE_DICTIONARY
static func _valid_footer(value: Variant) -> bool:
	if typeof(value)!=TYPE_DICTIONARY or value.size()!=6:return false
	for key in ["merchant_value","fortress_value","profit","capacity"]:
		if typeof(value.get(key))!=TYPE_STRING or value[key].is_empty() or value[key].to_utf8_buffer().size()>2048:return false
	return typeof(value.get("profit_color"))==TYPE_INT and value.profit_color in [2,4,6] and typeof(value.get("capacity_color"))==TYPE_INT and value.capacity_color in [4,7]
func _valid_open(value: Variant) -> bool:
	if typeof(value)!=TYPE_DICTIONARY or value.get("outcome")!=C.TradeSessionOutcome.Available or typeof(value.get("session"))!=TYPE_INT or value.session<=0 or typeof(value.get("revision"))!=TYPE_INT or value.revision!=1 or typeof(value.get("entry"))!=TYPE_DICTIONARY:return false
	var e: Dictionary=value.entry
	for key in ["entity_id","fortress_trader","merchant_trader","dialogue"]:
		if typeof(e.get(key))!=TYPE_INT or e[key]<(-1 if key in ["merchant_trader","dialogue"] else 0) or e[key]>(32767 if key=="dialogue" else 2147483647):return false
	for key in ["unloading","has_speaker"]:
		if typeof(e.get(key))!=TYPE_BOOL:return false
	for key in ["title","speaker","fortress","place"]:
		if typeof(e.get(key))!=TYPE_STRING or e[key].to_utf8_buffer().size()>2048:return false
	return true
func _valid(value: Variant,id: int) -> bool:
	if typeof(value)!=TYPE_DICTIONARY or typeof(value.get("depot_id"))!=TYPE_INT or value.depot_id!=id:return false
	if typeof(value.get("choices"))!=TYPE_ARRAY or value.choices.size()>4096:return false
	var bytes:=0
	for key in ["title","from_text"]:
		if typeof(value.get(key))!=TYPE_STRING or value[key].to_utf8_buffer().size()>2048:return false
		bytes+=value[key].to_utf8_buffer().size()
	var seen: Dictionary={}
	for row in value.choices:
		if typeof(row)!=TYPE_DICTIONARY or typeof(row.get("token"))!=TYPE_INT or row.token<=0 or seen.has(row.token):return false
		if typeof(row.get("entity_id"))!=TYPE_INT or row.entity_id<0 or row.entity_id>2147483647:return false
		seen[row.token]=true
		for key in ["race","name"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>2048:return false
			bytes+=row[key].to_utf8_buffer().size()
	return bytes<=384*1024
