extends RefCounted
# Shared job-backed Details state. Native owns choices, filtering and ordering.
# Material edits carry both displayed revisions; the service owns sent outcomes.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Rejected, Unavailable, Applying, Unknown }
var service
var phase:=Phase.Closed
var building_id:=-1
var job_id:=-1
var unit_id:=-1
var ticket:=0
var generation:=0
var snapshot: Dictionary={}
var rows: Array=[]
var query:=""
var first:=0
var visible_rows:=16
var selected:=-1
var pending: Array=[]
var receipt: Dictionary={}
var art_base:=0
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

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(close)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(close):service.session_changed.disconnect(close)
	service=null
func retire() -> void:
	_cancel_preview()
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	draft_value={"elements":[],"relationships":[]};draft_relation={};draft_relation_caption="";draft_quantity=1;draft_dirty=false;draft_discard=false
	retire();building_id=-1;job_id=-1;unit_id=-1;snapshot={};rows=[];pending=[];receipt={};query="";first=0;selected=-1;phase=Phase.Closed;art_base=0;changed.emit()
func open(building: int,job: int,unit: int=-1) -> void:
	close()
	if building<0 or job<0 or unit < -1:return
	building_id=building;job_id=job;unit_id=unit;read_root()
func has_art() -> bool:return snapshot.has("art")
func art_page() -> int:return int(snapshot.get("art",{}).get("page",-1))
func row_base() -> int:return art_base if has_art() else 0
func read_root() -> void:
	if job_id<0 or phase in [Phase.Applying,Phase.Unknown]:return
	selected=-1;query="";_restart()
func select_option(index: int) -> void:
	if phase!=Phase.Ready or index<0 or index>=snapshot.get("options",[]).size():return
	selected=index;query=""
	if int(snapshot.options[index].kind)==1:_read_art(-1);return
	_restart()
func set_query(value: String) -> void:
	if phase not in [Phase.Reading,Phase.Ready] or selected<0 or value==query or value.to_utf8_buffer().size()>128:return
	query=value
	if has_art():
		if art_page()>=0:_read_art(art_page())
		return
	_restart()
func _restart() -> void:
	retire();rows=[];pending=[];receipt={};first=0;phase=Phase.Reading;_read(0)
func _fail(value: Phase) -> void:
	phase=value;rows=[];pending=[];receipt={};snapshot={};changed.emit()
func _read(cursor: int) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	var intent: Dictionary={"action":C.ManagementAction.JobSettingsRead,"job_id":job_id,"building_id":building_id,"unit_id":unit_id,"option":selected,"query":query,"cursor":cursor}
	ticket=service.submit("job_settings",intent,func(received,result,_sent):
		if generation!=owner or received!=ticket:return
		ticket=0
		var value: Dictionary=result.get("job_settings",{})
		if result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=C.ManagementAction.JobSettingsRead or value.get("job_id")!=job_id or value.get("building_id")!=building_id or value.get("unit_id")!=unit_id:
			_fail(Phase.Rejected);return
		if value.get("revision",0)<=0 or not value.get("options") is Array or not value.get("choices") is Array or value.get("cursor",-1)!=cursor or cursor!=pending.size():
			_fail(Phase.Rejected);return
		var option: int=value.get("selected_option",-2)
		if option < -1 or option>=value.options.size() or (selected>=0 and option!=selected) or (option>=0 and value.get("choices_revision",0)<=0):
			_fail(Phase.Rejected);return
		if cursor>0 and (value.revision!=receipt.revision or value.choices_revision!=receipt.choices_revision or value.total!=receipt.total or option!=receipt.selected_option):
			_fail(Phase.Rejected);return
		pending.append_array(value.choices.duplicate(true));receipt=value.duplicate(true);selected=option
		var next: int=value.get("next_cursor",0)
		if next>0:
			if next!=pending.size() or value.choices.is_empty() or next>=int(value.get("total",-1)):_fail(Phase.Rejected);return
			_read(next);return
		if pending.size()!=int(value.get("total",-1)):_fail(Phase.Rejected);return
		snapshot=receipt;receipt={};rows=pending;pending=[];phase=Phase.Ready
		if option==-1 and snapshot.options.size()==1 and int(snapshot.options[0].kind)==1:
			selected=0;_read_art(-1);return
		changed.emit())
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()
func seek(value: int) -> void:
	if phase!=Phase.Ready:return
	_cancel_preview()
	if has_art():
		if art_page()<0 or art_page() in [6,18]:return
		value=clampi(value,0,maxi(0,int(snapshot.art.total)-visible_rows))
		if value<art_base or mini(value+visible_rows,int(snapshot.art.total))>art_base+rows.size():_read_art(art_page(),value,true);return
		first=value;changed.emit();return
	first=clampi(value,0,maxi(0,rows.size()-1));changed.emit()
func fit_visible_rows(count: int) -> void:
	visible_rows=maxi(1,count)
	if phase!=Phase.Ready or not has_art() or art_page()<0 or art_page() in [6,18]:return
	var total: int=snapshot.art.total
	var start:=clampi(first,0,maxi(0,total-visible_rows))
	if start!=first or start<art_base or mini(start+visible_rows,total)>art_base+rows.size():seek(start)
func choose(id: int) -> void:
	if phase!=Phase.Ready or selected<0:return
	var found:=false
	for row: Dictionary in rows:
		if row.id==id:found=true;break
	if not found:return
	if has_art():
		if art_page()==-1:
			if id in [1,2,3,5]:query="";_read_art(id)
			elif id==0:_apply_art(0,-1)
			elif id==6:draft_relation={};draft_discard=false;draft_navigate(6)
		else:_apply_art(art_page(),id)
		return
	if int(snapshot.options[selected].kind)==3 and id==0:
		_apply_art(-1,-1);return
	_submit_edit({"action":C.ManagementAction.JobSettingsApply,"job_id":job_id,"building_id":building_id,"unit_id":unit_id,"expected_revision":snapshot.revision,"option":selected,"expected_choices_revision":snapshot.choices_revision,"choice":id})
func _apply_art(page: int,subject: int) -> void:
	var list_revision: int=snapshot.choices_revision if page==-1 else 0 if page==0 else snapshot.art.list_revision
	_submit_edit({"action":C.ManagementAction.JobSettingsApply,"job_id":job_id,"building_id":building_id,"unit_id":unit_id,"expected_revision":snapshot.revision,"option":selected,"expected_choices_revision":list_revision,"choice":subject,"art_page":page,"query":query if page>0 else ""},page==-1)
func _submit_edit(intent: Dictionary,begin_art: bool=false) -> void:
	retire();phase=Phase.Applying
	var owner:=generation
	ticket=service.submit("job_settings",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		if result.get("outcome","")=="unknown":_fail(Phase.Unknown);return
		var value: Dictionary=result.get("job_settings_edit",{})
		if result.get("action",-1)==C.ManagementAction.JobSettingsApply and result.get("status",-1)==C.ManagementStatus.Ok and value.get("job_id")==job_id and value.get("building_id")==building_id and value.get("unit_id")==unit_id and value.get("outcome",-1)==C.JobSettingsEditOutcome.Applied:
			if begin_art:
				query="";_read_art(-1,0,false,true);return
			close();applied.emit();return
		_fail(Phase.Rejected if result.get("status",-1)==C.ManagementStatus.Rejected else Phase.Unknown))
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()

func _cancel_preview() -> void:
	if service!=null and preview_ticket!=0:service.detach(preview_ticket)
	preview_ticket=0;hovered=-1;preview_columns=0;preview_lines=[]
func _art_intent(page: int,cursor: int,list_revision: int=0,hover: int=-1,columns: int=0) -> Dictionary:
	return {"action":C.ManagementAction.JobSettingsRead,"job_id":job_id,"building_id":building_id,"unit_id":unit_id,"option":selected,"query":query,"cursor":cursor,"art_page":page,"expected_list_revision":list_revision,"hovered":hover,"preview_columns":columns}
func _same_target(result: Dictionary,value: Dictionary) -> bool:
	return result.get("status",-1)==C.ManagementStatus.Ok and result.get("action",-1)==C.ManagementAction.JobSettingsRead and value.get("job_id") == job_id and value.get("building_id") == building_id and value.get("unit_id") == unit_id
func _read_art(page: int,cursor: int=0,keep_list: bool=false,after_applied: bool=false) -> void:
	if not after_applied and (page>=6 or (page==-1 and draft_value.has("name"))):_read_draft(page,cursor);return
	if service==null or selected<0:_fail(Phase.Unavailable);return
	var revision: int=0 if after_applied else snapshot.get("revision",0)
	var list_revision: int=snapshot.get("art",{}).get("list_revision",0) if keep_list else 0
	retire();rows=[];pending=[];receipt={};first=cursor;art_base=cursor;phase=Phase.Reading
	var owner:=generation
	ticket=service.submit("job_settings",_art_intent(page,cursor,list_revision),func(received,result,_sent):
		if generation!=owner or received!=ticket:return
		ticket=0
		var value: Dictionary=result.get("job_settings",{})
		var art: Dictionary=value.get("art",{})
		if not _same_target(result,value) or value.get("revision",0)<=0 or (revision>0 and value.get("revision",0)!=revision) or value.get("selected_option",-1)!=selected or art.get("page",-2)!=page or not art.get("rows") is Array:
			_fail(Phase.Rejected);return
		var count: int=art.rows.size()
		var total: int=art.get("total",-1)
		var next: int=art.get("next_cursor",-1)
		if cursor>total or count>total-cursor or (cursor<total and count==0) or next!=(cursor+count if cursor+count<total else 0) or (page>=0 and art.get("list_revision",0)<=0) or (list_revision>0 and art.get("list_revision",0)!=list_revision):
			_fail(Phase.Rejected);return
		snapshot=value.duplicate(true);rows=art.rows.duplicate(true);phase=Phase.Ready
		if page==-1 and not draft_value.has("name"):
			_read_draft(6,0,{"action":4},true);return
		changed.emit())
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()
func art_back() -> void:
	if phase!=Phase.Ready or ticket!=0 or not has_art() or art_page()<0:return
	if art_page()>6:draft_navigate(6);return
	if art_page()==6 and draft_dirty:
		draft_discard=true;changed.emit();return
	query="";_read_art(-1)
func hover_art(id: int,columns: int) -> void:
	if phase!=Phase.Ready or not has_art() or art_page() not in [1,2,3,5] or service==null:return
	if id==hovered and (id<0 or columns==preview_columns):return
	_cancel_preview();changed.emit()
	if id<0 or columns<1 or columns>1024:return
	var found:=false
	for row in rows:
		if row.id==id:found=true;break
	if not found:return
	hovered=id;preview_columns=columns
	var owner:=generation
	var revision: int=snapshot.revision
	var list_revision: int=snapshot.art.list_revision
	var page: int=art_page()
	preview_ticket=service.submit("job_settings",_art_intent(page,art_base,list_revision,id,columns),func(received,result,_sent):
		if owner!=generation or received!=preview_ticket:return
		preview_ticket=0
		var value: Dictionary=result.get("job_settings",{})
		var art: Dictionary=value.get("art",{})
		if phase!=Phase.Ready or not has_art() or not _same_target(result,value) or value.get("revision",0)!=revision or value.get("selected_option",-1)!=selected or art.get("page",-2)!=page or art.get("list_revision",0)!=list_revision or art.get("hovered",-1)!=id or not art.get("preview") is Array:return
		preview_lines=art.preview.duplicate();changed.emit())

func draft_navigate(page: int) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	query="";first=0;art_base=0;draft_quantity=1;rows=[];_read_draft(page)
func discard_draft() -> void:
	if phase!=Phase.Ready or ticket!=0:return
	draft_value.elements=[];draft_value.relationships=[];draft_relation={};draft_dirty=false;draft_discard=false
	art_back()
func commit_draft() -> void:
	if phase!=Phase.Ready or ticket!=0 or art_page()!=6 or draft_value.elements.is_empty() or not draft_value.has("name"):return
	query="";first=0;art_base=0;_read_draft(6,0,{"action":5})
func choose_draft(row: Dictionary) -> void:
	if phase!=Phase.Ready or ticket!=0 or not rows.has(row):return
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

func _read_draft(page: int,cursor: int=0,edit: Dictionary={},return_root: bool=false) -> void:
	if service==null or selected<0 or phase in [Phase.Closed,Phase.Unknown,Phase.Unavailable,Phase.Rejected]:return
	var action: int=edit.get("action",0)
	var writing: bool=action in [4,5] or (action==6 and int(edit.get("name_edit",{}).get("mode",0))>=2)
	var revision: int=snapshot.get("revision",0)
	var draft: Dictionary={"value":draft_value.duplicate(true),"columns":draft_columns}
	draft.merge(edit)
	if page in [15,16] and not draft.has("relationship"):draft.relationship=draft_relation.duplicate(true)
	var art: Dictionary={"page":page,"query":query,"cursor":cursor,"draft":draft}
	if cursor>0:art.expected_list_revision=snapshot.art.list_revision
	var intent: Dictionary={"action":C.ManagementAction.JobSettingsApply if writing else C.ManagementAction.JobSettingsRead,"job_id":job_id,"building_id":building_id,"unit_id":unit_id,"option":selected,"expected_revision":revision,"art":art}
	retire();first=cursor;art_base=cursor;rows=[];phase=Phase.Applying if writing else Phase.Reading
	var owner:=generation
	ticket=service.submit("job_settings",intent,func(received,result,sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var failure:=Phase.Unknown if writing else Phase.Rejected
		var receipt_value: Dictionary=result.get("job_settings_edit",{})
		if result.get("outcome","")=="unknown" or receipt_value.get("outcome",-1)==C.JobSettingsEditOutcome.Unknown:_fail(Phase.Unknown);return
		if result.get("action",-1)!=sent.action or result.get("status",-1)!=C.ManagementStatus.Ok:
			_fail(Phase.Rejected if result.get("status",-1)==C.ManagementStatus.Rejected else failure);return
		if writing and (receipt_value.get("job_id")!=job_id or receipt_value.get("building_id")!=building_id or receipt_value.get("unit_id")!=unit_id or receipt_value.get("outcome",-1)!=C.JobSettingsEditOutcome.Applied):_fail(Phase.Unknown);return
		if action==5:close();applied.emit();return
		var value: Dictionary=result.get("job_settings",{})
		var observed: Dictionary=value.get("art",{})
		var expected_page:=6 if action in [1,2,4] else page
		if action==3:expected_page=6 if observed.get("draft",{}).get("elements",[]).is_empty() else 17
		if value.get("job_id")!=job_id or value.get("building_id")!=building_id or value.get("unit_id")!=unit_id or value.get("revision",0)!=revision or value.get("selected_option",-1)!=selected or observed.get("page",-2)!=expected_page or not observed.get("rows") is Array or not observed.get("draft") is Dictionary or not observed.get("draft_description") is Array:_fail(failure);return
		var count: int=observed.rows.size();var total: int=observed.get("total",-1)
		if cursor>total or count>total-cursor or (cursor<total and count==0) or observed.get("next_cursor",-1)!=(cursor+count if cursor+count<total else 0) or (expected_page>=0 and observed.get("list_revision",0)<=0) or (cursor>0 and observed.get("list_revision",0)!=sent.art.expected_list_revision):_fail(failure);return
		snapshot=value.duplicate(true);draft_value=observed.draft.duplicate(true);rows=observed.rows.duplicate(true);phase=Phase.Ready
		if action in [1,2,3]:draft_dirty=true
		if return_root:query="";_read_draft(-1);return
		changed.emit())
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()
