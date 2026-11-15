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
		rows=art.rows.duplicate(true);phase=Phase.Ready;changed.emit())
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
func _read_draft(_page: int,_cursor: int=0,_edit: Dictionary={},_return_root: bool=false) -> void:
	# The transport rejects drafts until engraving-specific installation is
	# qualified. Keep this staged owner out of ordinary map routing meanwhile.
	_fail(Phase.Rejected)
