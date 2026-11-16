extends RefCounted
# Staged merchant chooser and session ownership. Only explicit entry consumes a
# catalog token and appraises goods; later reads validate the owned session.
signal changed
signal choice_requested(depot_id: int, token: int)
signal session_opened
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Choosing,Rejected,Unknown,Unavailable,Active,Checking,GoodsReading,Applying}
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
	_open_ticket=0;session=0;revision=0;entry={};footer={}
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
	ticket=service.submit("trade_session",{"action":C.ManagementAction.TradeSessionRead,"session":session,"expected_revision":revision},func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("trade_session")
		if result.get("outcome")=="unknown":phase=Phase.Unknown
		elif result.get("status")==C.ManagementStatus.Ok and result.get("action")==C.ManagementAction.TradeSessionRead and typeof(value)==TYPE_DICTIONARY and value.get("outcome")==C.TradeSessionOutcome.Available and typeof(value.get("session"))==TYPE_INT and typeof(value.get("revision"))==TYPE_INT and value.session==session and value.revision==revision and not value.has("entry") and _valid_footer(value.get("footer")):
			footer=value.footer.duplicate(true);phase=Phase.Active
		else:phase=Phase.Rejected
		changed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
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
