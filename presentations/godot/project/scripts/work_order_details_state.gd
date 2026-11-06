extends RefCounted
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var order_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0
var first:=0
var rows: Array=[]
var query:=""
var dye_target: int=-1
var dye_filter_applied:=false
var art_base:=0
var visible_rows:=16
var preview_ticket:=0
var hovered: int=-1
var preview_columns:=0
var preview_lines: Array=[]
var draft_value: Dictionary={"elements":[],"relationships":[]}
var draft_relation: Dictionary={}
var draft_relation_caption:=""
var draft_quantity:=1
var draft_dirty:=false
var draft_discard:=false
var draft_columns:=118
func _cancel_preview() -> void:
	if service!=null and preview_ticket!=0:service.detach(preview_ticket)
	preview_ticket=0;hovered=-1;preview_columns=0;preview_lines=[]
func hover_art(id: int,columns: int) -> void:
	if phase!=Phase.Ready or not has_art() or art_page() not in [1,2,3,5] or service==null:return
	if id==hovered and (id<0 or columns==preview_columns):return
	_cancel_preview();hovered=id;preview_columns=columns;changed.emit()
	if id<0:return
	var found:=false
	for row in rows:
		if row.id==id:found=true;break
	if not found:return
	var owner:=generation
	var revision: int=snapshot.revision
	var list_revision: int=snapshot.art.list_revision
	var current_query:=query
	var preview_page: int=art_page()
	var intent: Dictionary={"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"expected_revision":revision,"details":{"option":snapshot.selected_option,"art":{"page":preview_page,"query":query,"cursor":art_base,"expected_list_revision":list_revision,"hovered":id,"preview_columns":columns}}}
	preview_ticket=service.submit("work_orders",intent,func(received,result,_sent):
		if owner!=generation or received!=preview_ticket:return
		preview_ticket=0
		if phase!=Phase.Ready or not has_art() or art_page()!=preview_page or snapshot.revision!=revision or snapshot.art.list_revision!=list_revision or query!=current_query or hovered!=id:return
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.WorkOrderInspect:return
		var details: Dictionary=result.get("work_order",{}).get("details",{})
		var art: Dictionary=details.get("art",{})
		if details.get("id",-1)!=order_id or details.get("revision",0)!=revision or art.get("page",-1)!=preview_page or art.get("list_revision",0)!=list_revision or art.get("hovered",-1)!=id or not art.get("preview") is Array:return
		preview_lines=art.preview.duplicate();changed.emit())
func has_art() -> bool:return snapshot.has("art")
func art_page() -> int:return int(snapshot.get("art",{}).get("page",-1))
func row_base() -> int:return art_base if has_art() else 0
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(close)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(close):service.session_changed.disconnect(close)
	service=null
func close() -> void:
	_cancel_preview()
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	building_id=-1;order_id=-1;snapshot={};rows=[];first=0;art_base=0;query="";phase=Phase.Closed;changed.emit()
	dye_target=-1;dye_filter_applied=false
	draft_value={"elements":[],"relationships":[]};draft_relation={};draft_dirty=false;draft_discard=false;draft_quantity=1
func open(building: int,order: int) -> void:
	close()
	if (building<0 and building!=-2) or order<0:return
	building_id=building;order_id=order;read_root()
func read_root() -> void:
	if ticket!=0:return
	dye_target=-1;dye_filter_applied=false
	first=0;rows=[];query="";phase=Phase.Reading
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"details":{}})
func select_option(index: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or index<0 or index>=snapshot.get("options",[]).size():return
	if snapshot.options[index].kind==1:_enter_art(index);return
	dye_target=-1;dye_filter_applied=false
	first=0;rows=[];query="";phase=Phase.Reading
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":index}})
func set_query(value: String) -> void:
	if phase not in [Phase.Ready,Phase.Reading] or snapshot.get("selected_option",-1)<0 or value==query:return
	query=value;first=0;art_base=0;rows=[]
	if not has_art() and snapshot.options[snapshot.selected_option].kind in [4,5]:dye_filter_applied=true
	if ticket==0:
		if has_art():_read_art(art_page())
		else:_read_choices()
	changed.emit()
func _read_choices(cursor:=0) -> void:
	phase=Phase.Reading
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":snapshot.selected_option,"query":query,"cursor":cursor,"expected_choices_revision":snapshot.choices_revision,"dye_target":dye_target,"dye_filter_applied":dye_filter_applied}})
func open_dye_target(target: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or has_art() or snapshot.options[snapshot.selected_option].kind not in [4,5]:return
	dye_target=target;dye_filter_applied=false;query="";first=0;rows=[];phase=Phase.Reading
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":snapshot.selected_option,"dye_target":target}})
func seek(value: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or snapshot.get("selected_option",-1)<0:return
	_cancel_preview()
	if has_art():
		if art_page()<0:return
		value=clampi(value,0,maxi(0,int(snapshot.art.total)-visible_rows))
		if value<art_base or mini(value+visible_rows,int(snapshot.art.total))>art_base+rows.size():_read_art(art_page(),value);return
		first=value;changed.emit();return
	first=clampi(value,0,maxi(0,rows.size()-1));changed.emit()
func fit_visible_rows(count: int) -> void:
	visible_rows=maxi(1,count)
	if phase!=Phase.Ready or ticket!=0 or not has_art() or art_page()<0 or art_page() in [6,18]:return
	var total: int=snapshot.art.total
	var start:=clampi(first,0,maxi(0,total-visible_rows))
	# A wider viewport can expose rows before the cached tail page. Re-read
	# through the ordinary revision-checked path instead of moving only the thumb.
	if start!=first or start<art_base or mini(start+visible_rows,total)>art_base+rows.size():seek(start)
func choose(id: int) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	var chosen: Dictionary={}
	for row in rows:
		if row.id==id:chosen=row;break
	if chosen.is_empty():return
	if has_art():
		if art_page()==-1:
			query="";first=0;art_base=0;rows=[]
			if id==0:_write_art(0,-1)
			elif id==6:
				draft_relation={};draft_discard=false;_read_draft(6)
			else:_read_art(id)
		else:_write_art(art_page(),id)
		return
	if snapshot.options[snapshot.selected_option].kind==3 and id==0:_enter_art(snapshot.selected_option);return
	if chosen.get("opens_menu",false):open_dye_target(int(chosen.dye_color));return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.WorkOrderUpdate,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":snapshot.selected_option,"choice":id,"expected_choices_revision":snapshot.choices_revision,"dye_target":dye_target}})
func _enter_art(option: int) -> void:
	first=0;art_base=0;rows=[];query="";phase=Phase.Applying
	draft_value={"elements":[],"relationships":[]};draft_dirty=false;draft_discard=false
	_send({"action":C.ManagementAction.WorkOrderUpdate,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":option,"art":{}}})
func _write_art(page: int,subject: int) -> void:
	phase=Phase.Applying
	var art: Dictionary={"page":page,"subject":subject}
	if page>0:art.merge({"query":query,"expected_list_revision":snapshot.art.list_revision})
	_send({"action":C.ManagementAction.WorkOrderUpdate,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":snapshot.selected_option,"art":art}})
func _read_art(page: int,cursor:=0) -> void:
	if page>=6 or (page==-1 and draft_value.has("name")):_read_draft(page,cursor);return
	phase=Phase.Reading
	var art: Dictionary={"page":page,"query":query,"cursor":cursor}
	if cursor>0:art.expected_list_revision=snapshot.art.list_revision
	_send({"action":C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":snapshot.selected_option,"art":art}})
func art_back() -> void:
	if ticket!=0 or not has_art() or art_page()<0:return
	if art_page()>6:draft_navigate(6);return
	if art_page()==6 and draft_dirty:
		draft_discard=true;changed.emit();return
	query="";first=0;art_base=0;rows=[];_read_art(-1)
func draft_navigate(page: int) -> void:
	if ticket!=0:return
	query="";first=0;art_base=0;draft_quantity=1;rows=[];_read_draft(page)
func discard_draft() -> void:
	if ticket!=0:return
	draft_value.elements=[];draft_value.relationships=[];draft_relation={};draft_dirty=false;draft_discard=false
	art_back()
func _read_draft(page: int,cursor:=0,edit: Dictionary={}) -> void:
	var action: int=edit.get("action",0)
	var writing: bool=action in [4,5] or (action==6 and int(edit.get("name_edit",{}).get("mode",0))>=2)
	phase=Phase.Applying if writing else Phase.Reading
	var draft: Dictionary={"value":draft_value.duplicate(true),"columns":draft_columns}
	draft.merge(edit)
	if page in [15,16] and not draft.has("relationship"):draft.relationship=draft_relation.duplicate(true)
	var art: Dictionary={"page":page,"query":query,"cursor":cursor,"draft":draft}
	if cursor>0:art.expected_list_revision=snapshot.art.list_revision
	_send({"action":C.ManagementAction.WorkOrderUpdate if writing else C.ManagementAction.WorkOrderInspect,"workshop_id":building_id,"id":order_id,"expected_revision":snapshot.revision,"details":{"option":snapshot.selected_option,"art":art}})
func commit_draft() -> void:
	if phase!=Phase.Ready or ticket!=0 or art_page()!=6 or draft_value.elements.is_empty() or not draft_value.has("name"):return
	query="";first=0;art_base=0;_read_draft(6,0,{"action":5})
func choose_draft(row: Dictionary) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	var page:=art_page()
	query="";first=0;art_base=0
	if page==6:draft_navigate(row.id)
	elif page>=7 and page<=13:
		_read_draft(page,0,{"action":1,"element":{"kind":page,"id":row.id,"secondary":row.get("secondary",-1),"quantity":draft_quantity}})
	elif page==14:
		draft_relation={"verb":row.id,"transitive":row.secondary==1,"actor":-1,"target":-1};draft_relation_caption=row.caption;_read_draft(15)
	elif page==15:
		draft_relation.actor=row.id
		if draft_relation.transitive:_read_draft(16)
		else:_read_draft(6,0,{"action":2,"relationship":draft_relation})
	elif page==16:
		draft_relation.target=row.id;_read_draft(6,0,{"action":2,"relationship":draft_relation})
	elif page==17:_read_draft(17,0,{"action":3,"delete_index":row.id})
func _fail(next: Phase) -> void:
	snapshot={};rows=[];phase=next;changed.emit()
func _send(intent: Dictionary) -> void:
	_cancel_preview()
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	ticket=service.submit("work_orders",intent,func(received,result,sent):
		if generation==owner and ticket==received:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()
func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var writing: bool=sent.action==C.ManagementAction.WorkOrderUpdate
	var failure:=Phase.Unknown if writing else Phase.Rejected
	if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=sent.action or result.get("outcome","")=="unknown":_fail(failure);return
	var value: Dictionary=result.get("work_order",{}).get("details",{})
	var entering: bool=writing and sent.details.has("art") and sent.details.art.get("page",-1)==-1
	var naming: bool=writing and sent.details.get("art",{}).get("draft",{}).get("action",0) in [4,6]
	var selected: int=-1 if writing and not entering and not naming else sent.details.get("option",-1)
	if value.get("id",-1)!=order_id or value.get("revision",0)<=0 or value.get("selected_option",-2)!=selected or not value.get("options") is Array:_fail(failure);return
	if value.get("dye_target",-1)!=(-1 if writing else sent.details.get("dye_target",-1)):_fail(failure);return
	if value.has("art"):
		if not sent.details.has("art"):_fail(failure);return
		var art: Dictionary=value.art
		var page: int=sent.details.art.get("page",-1)
		var cursor: int=sent.details.art.get("cursor",0)
		var draft_action: int=sent.details.art.get("draft",{}).get("action",0)
		if draft_action in [1,2,4]:page=6
		elif draft_action==3:
			page=6 if art.get("draft",{}).get("elements",[]).is_empty() else 17
		if art.get("page",-2)!=page or not art.get("rows") is Array or art.get("total",-1)<cursor+art.rows.size():_fail(failure);return
		if page>=0 and art.get("list_revision",0)<=0:_fail(failure);return
		if cursor>0 and (value.revision!=snapshot.revision or art.list_revision!=sent.details.art.expected_list_revision):_fail(failure);return
		snapshot=value.duplicate(true)
		if page>=6 or art.has("draft"):
			if not art.get("draft") is Dictionary or not art.get("draft_description") is Array:_fail(failure);return
			draft_value=art.draft.duplicate(true)
			if draft_action in [1,2,3]:draft_dirty=true
		if sent.details.art.get("query","")!=query:rows=[];_read_art(page);return
		rows=art.rows.duplicate(true);art_base=cursor;first=cursor;phase=Phase.Ready;changed.emit();return
	if sent.details.has("art") and (not writing or entering or naming):_fail(failure);return
	if selected>=0:
		if sent.details.get("query","")!=query:
			snapshot=value.duplicate(true);rows=[];_read_choices();return
		var cursor: int=sent.details.get("cursor",0)
		if not value.get("choices") is Array or value.get("choices_revision",0)<=0 or cursor!=rows.size():_fail(failure);return
		if cursor>0 and (value.revision!=snapshot.revision or value.choices_revision!=snapshot.choices_revision):_fail(failure);return
		rows.append_array(value.choices.duplicate(true))
		if rows.size()>value.get("total",-1):_fail(failure);return
		snapshot=value.duplicate(true)
		var next: int=value.get("next_cursor",0)
		if next>0:
			if next!=rows.size() or value.choices.is_empty():_fail(failure);return
			_read_choices(next);return
		if rows.size()!=value.total:_fail(failure);return
	else:
		rows=[];first=0;snapshot=value.duplicate(true)
	phase=Phase.Ready
	if writing:applied.emit()
	changed.emit()
