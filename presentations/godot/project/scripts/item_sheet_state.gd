extends RefCounted
# One owned item snapshot. Native inspection supplies text, eligibility and revision.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
const Contents=preload("res://scripts/building_contents_state.gd")
const FIELDS=Contents.FIELDS
const REFRESH_INTERVAL:=0.25
enum Phase { Closed, Reading, Ready, Applying, Rejected, Stale, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var item_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0
var background_refresh:=false
var refresh_remaining:=0.0

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)

func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null

func close() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	background_refresh=false;refresh_remaining=0
	if service!=null and previous!=0:service.detach(previous)
	item_id=-1;snapshot={};phase=Phase.Closed;changed.emit()

func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()

func open(item: int) -> void:
	close()
	if item<0 or item>2147483647:_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	item_id=item;_read()

func open_child(id: int) -> void:
	# Navigation is a read of the selected stable ID. Retire the parent request
	# before opening; a late parent refresh must never replace the child sheet.
	if phase!=Phase.Ready or not snapshot.get("contents",[]).any(func(row):return row.kind==1 and row.id==id):return
	open(id)

func refresh() -> void:
	if item_id<0 or ticket!=0 or phase in [Phase.Closed,Phase.Unavailable]:return
	_read()

func poll(delta: float) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	refresh_remaining-=maxf(0,delta)
	if refresh_remaining<=0:_read(true)

func view_snapshot() -> Dictionary:
	return snapshot.duplicate(true)

func set_flag(operation: int, desired: bool, contents_id: int=-1) -> void:
	if phase!=Phase.Ready or (ticket!=0 and not background_refresh) or not FIELDS.has(operation) or snapshot.is_empty():return
	var selected: Dictionary=snapshot
	if contents_id!=-1:
		if contents_id<0 or contents_id==item_id:return
		var matches: Array=snapshot.get("contents",[]).filter(func(row):return row.kind==1 and row.id==contents_id)
		if matches.is_empty():return
		selected=matches[0]
	if operation==C.FarmOperation.ItemDump and not selected.can_dump:return
	if operation==C.FarmOperation.ItemMelt and not selected.can_melt:return
	# A read has no effects to replay. Explicit edits retire its observer and use
	# the last complete revision; DF still validates that revision before writing.
	if background_refresh:
		generation+=1
		var previous:=ticket;ticket=0;background_refresh=false
		service.detach(previous)
	phase=Phase.Applying
	_send({"action":C.ManagementAction.FarmEdit,"independent_item":true,"item_id":item_id,
		"farm_operation":operation,"item_value":int(desired),"expected_revision":snapshot.revision,"contents_item_id":contents_id})

func _read(background:=false) -> void:
	background_refresh=background
	if not background:snapshot={};phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"independent_item":true,"item_id":item_id})

func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	if not background_refresh:changed.emit()

func _fail(next: Phase) -> void:
	if background_refresh:close();return
	phase=next;snapshot={};changed.emit()

func _valid(value: Dictionary) -> bool:
	for key in ["id","item_type","revision","stockpile_categories"]:
		if typeof(value.get(key))!=TYPE_INT:return false
	if value.id!=item_id or value.item_type<0 or value.item_type>92 or value.revision<=0:return false
	for key in ["forbid","dump","melt","hidden","can_dump","can_melt","in_job","in_building"]:
		if typeof(value.get(key))!=TYPE_BOOL:return false
	for key in ["name","weight","description","material_token","subtype_raw"]:
		var limit: int={"name":131072,"weight":128,"description":32768,"material_token":256,"subtype_raw":128}[key]
		if typeof(value.get(key))!=TYPE_STRING or value[key].to_utf8_buffer().size()>limit:return false
	if value.item_type in [13,30] and not value.has("appearance"):return false
	if value.has("uses"):
		if typeof(value.uses)!=TYPE_ARRAY or value.uses.size()>4096:return false
		for row in value.uses:
			if typeof(row)!=TYPE_DICTIONARY or row.size()!=2 or typeof(row.get("caption"))!=TYPE_STRING or row.caption.to_utf8_buffer().size()>16384 or typeof(row.get("reaction"))!=TYPE_INT or row.reaction< -1 or row.reaction>2147483647:return false
	if value.has("contents"):
		if typeof(value.contents)!=TYPE_ARRAY or value.contents.size()>4096:return false
		for row in value.contents:
			if typeof(row)!=TYPE_DICTIONARY:return false
			for key in ["kind","id","item_type","flags"]:
				if typeof(row.get(key))!=TYPE_INT:return false
			if row.id<0 or row.kind not in [1,2] or typeof(row.get("caption"))!=TYPE_STRING or row.caption.to_utf8_buffer().size()>128*1024:return false
			for key in ["can_dump","can_melt"]:
				if typeof(row.get(key))!=TYPE_BOOL:return false
			if row.kind==2:
				if row.item_type!=-1 or row.flags!=0 or row.can_dump or row.can_melt or row.has("appearance"):return false
			elif row.item_type<0 or row.item_type>92 or row.flags<0 or row.flags>0xffffffff or not _valid_appearance(row.get("appearance"),row.item_type):return false
	if value.has("appearance"):
		if not _valid_appearance(value.appearance,value.item_type):return false
		if value.appearance.material_token!=value.material_token or value.appearance.subtype_raw!=value.subtype_raw:return false
	if value.has("stockpile"):
		if value.stockpile_categories<0 or value.stockpile_categories>0x1ffff:return false
	elif value.stockpile_categories!=-1:return false
	if value.has("ammunition_assignment"):
		var a: Variant=value.ammunition_assignment
		if value.item_type!=39 or typeof(a)!=TYPE_DICTIONARY or a.size()!=3:return false
		if typeof(a.get("kind"))!=TYPE_INT or a.kind<0 or a.kind>2 or typeof(a.get("squad_id"))!=TYPE_INT:return false
		if (a.kind==2 and (a.squad_id<0 or a.squad_id>2147483647)) or (a.kind!=2 and a.squad_id!=-1):return false
		if typeof(a.get("caption"))!=TYPE_STRING or a.caption.to_utf8_buffer().size()>1024 or (a.kind==0)!=a.caption.is_empty():return false
	if value.has("owner"):
		var owner=value.owner
		if typeof(owner)!=TYPE_DICTIONARY or owner.size()!=2:return false
		if typeof(owner.get("id"))!=TYPE_INT or owner.id<0 or owner.id>2147483647:return false
		if typeof(owner.get("name"))!=TYPE_STRING or owner.name.to_utf8_buffer().size()>512:return false
	if value.has("carrier"):
		var carrier=value.carrier
		if value.has("holder") or typeof(carrier)!=TYPE_DICTIONARY:return false
		for key in ["kind","id","item_type"]:
			if typeof(carrier.get(key))!=TYPE_INT:return false
		if carrier.id<0 or carrier.id>2147483647 or carrier.kind not in [1,2]:return false
		if carrier.kind==1 and (carrier.item_type<0 or carrier.item_type>92):return false
		if carrier.kind==2 and carrier.item_type!=-1:return false
		if (carrier.kind==1)!=carrier.has("appearance"):return false
		if carrier.has("appearance") and not _valid_appearance(carrier.appearance,carrier.item_type):return false
		if typeof(carrier.get("name"))!=TYPE_STRING or carrier.name.to_utf8_buffer().size()>512:return false
	for forbidden in ["building_id","role","completed","removing"]:
		if value.has(forbidden):return false
	for field in ["holder","stockpile"]:
		if not value.has(field):continue
		var link=value[field]
		if typeof(link)!=TYPE_DICTIONARY:return false
		for key in ["id","type"]:
			if typeof(link.get(key))!=TYPE_INT or link[key]<0 or link[key]>2147483647:return false
		if typeof(link.get("name"))!=TYPE_STRING or link.name.to_utf8_buffer().size()>512:return false
		if field=="stockpile" and link.type!=29:return false
	return true

func _receive(result: Dictionary, sent: Dictionary) -> void:
	ticket=0;refresh_remaining=REFRESH_INTERVAL
	var owner:=generation
	var editing: bool=sent.action==C.ManagementAction.FarmEdit
	var production: Dictionary=result.get("production",{})
	var state: Dictionary=production.get("independent_item",{})
	var outcome: int=state.get("outcome",C.FarmEditOutcome.None)
	if result.get("outcome","")=="unknown" or outcome==C.FarmEditOutcome.Unknown:_fail(Phase.Unknown);return
	if result.get("status",C.ManagementStatus.Rejected)!=C.ManagementStatus.Ok:
		_fail(Phase.Stale if editing and outcome==C.FarmEditOutcome.Stale else Phase.Rejected);return
	if result.get("action",-1)!=sent.action or production.get("selected_building",-1)!=-1:
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	for field in ["farm","contents","contents_edit","item","item_position"]:
		if production.has(field):_fail(Phase.Unknown if editing else Phase.Rejected);return
	var value: Dictionary=state.get("snapshot",{})
	if not _valid(value):_fail(Phase.Unknown if editing else Phase.Rejected);return
	if editing:
		var target_id: int=sent.get("contents_item_id",-1)
		var actual: bool=value[FIELDS[sent.farm_operation]]
		if target_id>=0:
			var matches: Array=value.get("contents",[]).filter(func(row):return row.kind==1 and row.id==target_id)
			if matches.is_empty():_fail(Phase.Unknown);return
			var masks={C.FarmOperation.ItemForbid:0x80000,C.FarmOperation.ItemDump:0x200000,C.FarmOperation.ItemMelt:0x800000,C.FarmOperation.ItemHidden:0x1000000}
			actual=bool(matches[0].flags&masks[sent.farm_operation])
		else:target_id=item_id
		if outcome!=C.FarmEditOutcome.Completed or state.get("edit",{})!={"item_id":target_id,"farm_operation":sent.farm_operation,"value":sent.item_value} or actual!=bool(sent.item_value):
			_fail(Phase.Unknown);return
	elif outcome!=C.FarmEditOutcome.None or state.has("edit"):_fail(Phase.Rejected);return
	# A confirmed independent receipt already contains a coherent fresh observation.
	var different: bool=not background_refresh or snapshot!=value
	background_refresh=false;snapshot=value.duplicate(true);phase=Phase.Ready
	if different:changed.emit()
	if editing and owner==generation:applied.emit()

static func _valid_appearance(look: Variant,item_type: int) -> bool:
	if typeof(look)!=TYPE_DICTIONARY or look.size()!=5+int(item_type==13)+int(look.has("contents"))+int(look.has("floodgate_open"))+int(look.has("door"))+int(look.has("bucket_liquid"))+int(look.has("cage"))+int(look.has("restraint"))+int(look.has("portrait"))+int(look.has("slab_engraving"))+int(look.has("corpse_selector"))+int(look.has("legwear_selector")):return false
	if look.has("slab_engraving") and (item_type!=87 or typeof(look.slab_engraving)!=TYPE_INT or look.slab_engraving< -1 or look.slab_engraving>26):return false
	if look.has("portrait") and (item_type not in [51,52] or not _valid_recipe(look.portrait)):return false
	if look.has("legwear_selector") and (item_type!=60 or not _valid_recipe(look.legwear_selector)):return false
	if look.has("corpse_selector") and (item_type not in [23,46] or not _valid_recipe(look.corpse_selector)):return false
	if look.has("restraint"):
		var restraint=look.restraint
		if item_type!=10 or typeof(restraint)!=TYPE_DICTIONARY or restraint.size()!=2:return false
		if typeof(restraint.get("rope"))!=TYPE_BOOL or typeof(restraint.get("solid_color"))!=TYPE_STRING or restraint.solid_color.to_utf8_buffer().size()>128:return false
	if look.has("cage"):
		var cage=look.cage
		if item_type!=16 or typeof(cage)!=TYPE_DICTIONARY or cage.size()!=4+int(cage.has("occupant")):return false
		for key in ["material_family","occupant_entity","occupant_id"]:
			if typeof(cage.get(key))!=TYPE_INT:return false
		if typeof(cage.get("solid_color"))!=TYPE_STRING or cage.solid_color.to_utf8_buffer().size()>128:return false
		if cage.material_family<0 or cage.material_family>2 or cage.occupant_entity<0 or cage.occupant_entity>2:return false
		if cage.occupant_id < -1 or cage.occupant_id>2147483647 or (cage.occupant_id!=-1 if cage.occupant_entity==0 else cage.occupant_id<0):return false
		if cage.has("occupant") and (cage.occupant_entity==0 or not _valid_recipe(cage.occupant)):return false
	if look.has("bucket_liquid"):
		var liquid=look.bucket_liquid
		if item_type!=18 or typeof(liquid)!=TYPE_DICTIONARY or liquid.size()!=2:return false
		if typeof(liquid.get("present"))!=TYPE_BOOL or typeof(liquid.get("color_token"))!=TYPE_STRING:return false
		if liquid.color_token.to_utf8_buffer().size()>128 or (not liquid.present and not liquid.color_token.is_empty()):return false
	if look.has("door"):
		var door=look.door
		if item_type!=6 or typeof(door)!=TYPE_DICTIONARY or door.size()!=3:return false
		if typeof(door.get("open"))!=TYPE_BOOL or typeof(door.get("forbidden"))!=TYPE_BOOL or typeof(door.get("wear"))!=TYPE_INT:return false
		if door.wear<0 or door.wear>3:return false
	if look.has("floodgate_open") and (item_type!=7 or typeof(look.floodgate_open)!=TYPE_BOOL):return false
	if look.has("contents") and (item_type not in [17,31,32] or not _valid_contents(look.contents,item_type)):return false
	if item_type==13:
		var instrument=look.get("instrument")
		if typeof(instrument)!=TYPE_DICTIONARY or instrument.size()!=2:return false
		for key in ["family","placed"]:
			if typeof(instrument.get(key))!=TYPE_INT:return false
		if instrument.family<0 or instrument.family>3 or instrument.placed<0 or instrument.placed>1:return false
	elif look.has("instrument"):return false
	for key in ["material_token","subtype_raw","color_token"]:
		if typeof(look.get(key))!=TYPE_STRING or look[key].to_utf8_buffer().size()>(256 if key=="material_token" else 128):return false
	if look.material_token.is_empty():return false
	for key in ["stack","flags"]:
		if typeof(look.get(key))!=TYPE_INT:return false
	return look.stack>=1 and look.stack<=2147483647 and look.flags>=0 and (look.flags&~96)==0

static func _valid_contents(contents: Variant,item_type: int) -> bool:
	if typeof(contents)!=TYPE_DICTIONARY or contents.size()!=(4 if item_type==17 else 2) or typeof(contents.get("container"))!=TYPE_BOOL or typeof(contents.get("entries"))!=TYPE_ARRAY:return false
	if contents.entries.size()>(4096 if item_type==32 else 1) or (item_type!=31 and not contents.container and not contents.entries.is_empty()):return false
	if item_type==17:
		if typeof(contents.get("material_inorganic"))!=TYPE_BOOL or typeof(contents.get("solid_color"))!=TYPE_STRING or contents.solid_color.to_utf8_buffer().size()>128:return false
	for row in contents.entries:
		if typeof(row)!=TYPE_DICTIONARY or row.size()!=(12 if item_type==17 else 10):return false
		if typeof(row.get("item_type"))!=TYPE_INT or row.item_type< -1 or row.item_type>92:return false
		if typeof(row.get("effective_armor_level"))!=TYPE_INT or row.effective_armor_level< -128 or row.effective_armor_level>127:return false
		for key in ["material_token","color_token"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>(256 if key=="material_token" else 128):return false
		if item_type==17:
			for key in ["liquid","subterranean_plant"]:
				if typeof(row.get(key))!=TYPE_BOOL:return false
		for key in ["metal","coal","contains_powder","rolls_sheets","protects_folded_sheets","contains_writing"]:
			if typeof(row.get(key))!=TYPE_BOOL:return false
	return true

static func _valid_recipe(recipe: Variant) -> bool:
	if typeof(recipe)!=TYPE_DICTIONARY or recipe.size()!=3:return false
	var bytes:=12
	for key in ["tile_pages","palettes","layers"]:
		if typeof(recipe.get(key))!=TYPE_ARRAY or recipe[key].size()>256:return false
	if recipe.tile_pages.is_empty() or recipe.layers.is_empty():return false
	for key in ["tile_pages","palettes"]:
		for value in recipe[key]:
			if typeof(value)!=TYPE_STRING or value.is_empty():return false
			var length: int=value.to_utf8_buffer().size()
			if length>(256 if key=="tile_pages" else 512):return false
			bytes+=4+length
	var low=[0,0,0,1,1,0,-32768,-32768,-128,-128]
	var high=[65535,65535,65535,255,255,65535,32767,32767,127,127]
	for layer in recipe.layers:
		if typeof(layer)!=TYPE_ARRAY or layer.size()!=10:return false
		for i in 10:
			if typeof(layer[i])!=TYPE_INT or layer[i]<low[i] or layer[i]>high[i]:return false
		if layer[0]>=recipe.tile_pages.size() or (layer[5]!=65535 and layer[5]>=recipe.palettes.size()):return false
		bytes+=16
	return bytes<=131072
