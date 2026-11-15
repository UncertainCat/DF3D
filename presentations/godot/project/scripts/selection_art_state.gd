extends "res://scripts/job_settings_state.gd"
# Shares local artwork navigation/rendering state, but never creates a proxy job.
# The selected tile receipt is the sole target passed to the semantic service.
var selection_receipt:=0
func close() -> void:
	selection_receipt=0;super.close()
func open_selection(value: int) -> void:
	close()
	if value<=0:return
	selection_receipt=value;selected=0;_read_art(-1)
func read_root() -> void:
	if selection_receipt<=0 or phase in [Phase.Applying,Phase.Unknown]:return
	query="";_read_art(-1)
func _art_intent(page: int,cursor: int,list_revision: int=0,hover: int=-1,columns: int=0) -> Dictionary:
	return {"action":C.ManagementAction.SelectionArtRead,"receipt":selection_receipt,"expected_revision":snapshot.get("revision",0),"art":{"page":page,"query":query,"cursor":cursor,"expected_list_revision":list_revision,"hovered":hover,"preview_columns":columns}}
func _same_target(result: Dictionary,value: Dictionary) -> bool:
	return result.get("status",-1)==C.ManagementStatus.Ok and result.get("action",-1)==C.ManagementAction.SelectionArtRead and value.get("receipt",0)==selection_receipt
func _read_art(page: int,cursor: int=0,keep_list: bool=false,_after_applied: bool=false) -> void:
	if page>=6 or (page==-1 and draft_value.has("name")):_read_draft(page,cursor);return
	if service==null or selection_receipt<=0:_fail(Phase.Unavailable);return
	var revision: int=snapshot.get("revision",0)
	var list_revision: int=snapshot.get("art",{}).get("list_revision",0) if keep_list else 0
	retire();rows=[];first=cursor;art_base=cursor;phase=Phase.Reading
	var owner:=generation
	ticket=service.submit("selection_art",_art_intent(page,cursor,list_revision),func(received,result,_sent):
		if generation!=owner or received!=ticket:return
		ticket=0
		var value: Dictionary=result.get("selection_art",{})
		var art: Dictionary=value.get("art",{})
		if not _same_target(result,value) or value.get("revision",0)<=0 or (revision>0 and value.revision!=revision) or art.get("page",-2)!=page or not art.get("rows") is Array:
			_fail(Phase.Rejected);return
		var count: int=art.rows.size();var total: int=art.get("total",-1)
		if cursor>total or count>total-cursor or (cursor<total and count==0) or art.get("next_cursor",-1)!=(cursor+count if cursor+count<total else 0) or (page>=0 and art.get("list_revision",0)<=0) or (list_revision>0 and art.get("list_revision",0)!=list_revision):
			_fail(Phase.Rejected);return
		snapshot=value.duplicate(true);snapshot.selected_option=0
		rows=art.rows.duplicate(true);phase=Phase.Ready
		if page==-1 and not draft_value.has("name"):_read_draft(6,0,{"action":4},true);return
		changed.emit())
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()
func _apply_art(page: int,subject: int) -> void:
	var intent: Dictionary={"action":C.ManagementAction.SelectionArtApply,"receipt":selection_receipt,"expected_revision":snapshot.revision,"art":{"page":page,"subject":subject,"query":query if page>0 else "","expected_list_revision":snapshot.art.list_revision if page>0 else 0}}
	retire();phase=Phase.Applying
	var owner:=generation
	ticket=service.submit("selection_art",intent,func(received,result,_sent):
		if generation!=owner or received!=ticket:return
		ticket=0
		if result.get("outcome","")=="unknown":_fail(Phase.Unknown);return
		var value: Dictionary=result.get("selection_art",{})
		if result.get("status",-1)==C.ManagementStatus.Ok and result.get("action",-1)==C.ManagementAction.SelectionArtApply and value.get("receipt",0)==selection_receipt and value.get("applied",false):
			close();applied.emit();return
		_fail(Phase.Rejected if result.get("status",-1)==C.ManagementStatus.Rejected else Phase.Unknown))
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()
func hover_art(id: int,columns: int) -> void:
	if phase!=Phase.Ready or not has_art() or art_page() not in [1,2,3,5] or service==null:return
	if id==hovered and (id<0 or columns==preview_columns):return
	_cancel_preview();changed.emit()
	if id<0 or columns<1 or columns>256:return
	var found:=false
	for row in rows:
		if row.id==id:found=true;break
	if not found:return
	hovered=id;preview_columns=columns
	var owner:=generation;var revision: int=snapshot.revision;var list_revision: int=snapshot.art.list_revision;var page:=art_page()
	preview_ticket=service.submit("selection_art",_art_intent(page,art_base,list_revision,id,columns),func(received,result,_sent):
		if owner!=generation or received!=preview_ticket:return
		preview_ticket=0
		var value: Dictionary=result.get("selection_art",{});var art: Dictionary=value.get("art",{})
		if phase!=Phase.Ready or not _same_target(result,value) or value.get("revision",0)!=revision or art.get("page",-2)!=page or art.get("list_revision",0)!=list_revision or art.get("hovered",-1)!=id or not art.get("preview") is Array:return
		preview_lines=art.preview.duplicate();changed.emit())
func _read_draft(page: int,cursor: int=0,edit: Dictionary={},return_root: bool=false) -> void:
	if service==null or selection_receipt<=0 or phase in [Phase.Closed,Phase.Unknown,Phase.Unavailable,Phase.Rejected]:return
	var action: int=edit.get("action",0)
	var writing: bool=action in [4,5] or (action==6 and int(edit.get("name_edit",{}).get("mode",0))>=2)
	var revision: int=snapshot.get("revision",0)
	var draft: Dictionary={"value":draft_value.duplicate(true),"columns":draft_columns};draft.merge(edit)
	if page in [15,16] and not draft.has("relationship"):draft.relationship=draft_relation.duplicate(true)
	var art: Dictionary={"page":page,"query":query,"cursor":cursor,"draft":draft}
	if cursor>0:art.expected_list_revision=snapshot.art.list_revision
	var intent: Dictionary={"action":C.ManagementAction.SelectionArtApply if writing else C.ManagementAction.SelectionArtRead,"receipt":selection_receipt,"expected_revision":revision,"art":art}
	retire();first=cursor;art_base=cursor;rows=[];phase=Phase.Applying if writing else Phase.Reading
	var owner:=generation
	ticket=service.submit("selection_art",intent,func(received,result,sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var failure:=Phase.Unknown if writing else Phase.Rejected
		if result.get("outcome","")=="unknown":_fail(Phase.Unknown);return
		var value: Dictionary=result.get("selection_art",{})
		if result.get("action",-1)!=sent.action or result.get("status",-1)!=C.ManagementStatus.Ok:
			_fail(Phase.Rejected if result.get("status",-1)==C.ManagementStatus.Rejected else failure);return
		if value.get("receipt",0)!=selection_receipt or value.get("applied",false)!=writing:_fail(failure);return
		if action==5:close();applied.emit();return
		var observed: Dictionary=value.get("art",{})
		var expected_page:=6 if action in [1,2,4] else page
		if action==3:expected_page=6 if observed.get("draft",{}).get("elements",[]).is_empty() else 17
		if value.get("revision",0)!=revision or observed.get("page",-2)!=expected_page or not observed.get("rows") is Array or not observed.get("draft") is Dictionary or not observed.get("draft_description") is Array:_fail(failure);return
		var count: int=observed.rows.size();var total: int=observed.get("total",-1)
		if cursor>total or count>total-cursor or (cursor<total and count==0) or observed.get("next_cursor",-1)!=(cursor+count if cursor+count<total else 0) or (expected_page>=0 and observed.get("list_revision",0)<=0) or (cursor>0 and observed.get("list_revision",0)!=sent.art.expected_list_revision):_fail(failure);return
		draft_formatted_columns=int(sent.art.draft.columns)
		snapshot=value.duplicate(true);snapshot.selected_option=0;draft_value=observed.draft.duplicate(true);rows=observed.rows.duplicate(true);phase=Phase.Ready
		if action in [1,2,3]:draft_dirty=true
		if return_root:query="";_read_draft(-1);return
		changed.emit())
	if ticket==0:_fail(Phase.Unavailable)
	else:changed.emit()
