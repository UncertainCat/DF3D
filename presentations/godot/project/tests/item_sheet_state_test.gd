extends "res://tests/building_contents_state_test.gd"
const ItemModel=preload("res://scripts/item_sheet_state.gd")

func setup() -> void:
	if model!=null:model.dispose();service.free()
	world=World.new();service=Service.new();service.configure(world);model=ItemModel.new();model.configure(service)
	applied=0;model.applied.connect(func():applied+=1)

func item(id:=1000) -> Dictionary:
	var value: Dictionary=page().rows[0].duplicate(true)
	value.merge({"stockpile_categories":-1,"id":id,"revision":9007199254740993,
		"weight":"native weight","description":"native description","holder":{"id":968,"type":4,"name":"native holder"}},true)
	value.erase("role");return value

func item_reply(production: Dictionary, status:=C.ManagementStatus.Ok) -> void:
	production={"independent_item":production.duplicate(true)}
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":world.calls[-1].request.action,
		"status":status,"production":production}
	service.poll()

func ready() -> void:
	setup();model.open(1000);service.poll();item_reply({"snapshot":item()})

func completed(wrong_flag:=false) -> void:
	var value:=item();value.hidden=not wrong_flag;value.revision+=1;value.description="fresh native description"
	item_reply({"snapshot":value,"outcome":C.FarmEditOutcome.Completed,
		"edit":{"item_id":1000,"farm_operation":C.FarmOperation.ItemHidden,"value":1}})

func run() -> void:
	setup();model.item_id=1000
	var uses_item:=item();uses_item.uses=[]
	check(model._valid(uses_item),"Known empty Uses rejected")
	uses_item.uses=[{"caption":"Native reaction","reaction":84}]
	check(model._valid(uses_item),"Native Uses row rejected")
	uses_item.uses[0].reaction=-2
	check(not model._valid(uses_item),"Invalid Uses reaction accepted")
	for mode in 6:
		setup();model.open(1000);service.poll();var restraint_item:=item();restraint_item.item_type=10;restraint_item.material_token="INORGANIC:SILVER"
		restraint_item.appearance={"material_token":"INORGANIC:SILVER","subtype_raw":"","color_token":"","stack":1,"flags":0}
		if mode>0:restraint_item.appearance.restraint={"rope":mode!=1,"solid_color":"SILVER"}
		if mode==3:restraint_item.appearance.restraint.rope=1
		if mode==4:restraint_item.item_type=16
		if mode==5:restraint_item.appearance.restraint.solid_color=42
		item_reply({"snapshot":restraint_item});check((model.phase==ItemModel.Phase.Ready)==(mode<3),"Restraint facts validation differs")
	for mode in 6:
		setup();model.open(1000);service.poll();var cage_item:=item();cage_item.item_type=16;cage_item.material_token="INORGANIC:COPPER"
		cage_item.appearance={"material_token":"INORGANIC:COPPER","subtype_raw":"","color_token":"","stack":1,"flags":0}
		if mode>0:cage_item.appearance.cage={"material_family":0,"solid_color":"COPPER","occupant_entity":0 if mode==1 else 1,"occupant_id":-1 if mode==1 else 6960}
		if mode==3:cage_item.appearance.cage.occupant_id=-1
		if mode==4:cage_item.appearance.cage.material_family=3
		if mode==5:cage_item.appearance.cage.solid_color=42
		item_reply({"snapshot":cage_item});check((model.phase==ItemModel.Phase.Ready)==(mode<3),"Cage facts validation differs")
	for fault in 3:
		setup();model.open(1000);service.poll();var parent_flags:=item()
		parent_flags.contents=[{"kind":1,"id":71,"item_type":0,"caption":"bar","flags":0,"can_dump":true,"can_melt":true,"appearance":{"material_token":"INORGANIC:IRON","subtype_raw":"","color_token":"","stack":1,"flags":0}}]
		item_reply({"snapshot":parent_flags});var calls: int=world.calls.size()
		model.set_flag(C.FarmOperation.ItemHidden,true,99);service.poll();check(world.calls.size()==calls,"Nonmember child edit sent")
		model.set_flag(C.FarmOperation.ItemHidden,true,71);service.poll()
		check(world.calls[-1].request.item_id==1000 and world.calls[-1].request.contents_item_id==71 and world.calls[-1].request.expected_revision==parent_flags.revision,"Child edit lost parent authority")
		parent_flags.revision+=1
		if fault!=1:parent_flags.contents[0].flags=0x1000000
		item_reply({"snapshot":parent_flags,"outcome":C.FarmEditOutcome.Completed,"edit":{"item_id":1000 if fault==2 else 71,"farm_operation":C.FarmOperation.ItemHidden,"value":1}})
		check(model.phase==(ItemModel.Phase.Ready if fault==0 else ItemModel.Phase.Unknown),"Child receipt was not verified against selected row")
	setup();model.open(1000);service.poll();var parent:=item()
	parent.contents=[{"kind":1,"id":71,"item_type":0,"caption":"native bar","flags":0,"can_dump":true,"can_melt":true,"appearance":{"material_token":"INORGANIC:IRON","subtype_raw":"","color_token":"","stack":1,"flags":0}}]
	item_reply({"snapshot":parent});check(model.phase==ItemModel.Phase.Ready,"Parent contents unavailable")
	model.open_child(999);check(model.item_id==1000,"Non-member child opened")
	var previous_generation: int=model.generation
	model.open_child(71);service.poll()
	check(model.item_id==71 and model.phase==ItemModel.Phase.Reading and model.snapshot.is_empty() and model.generation>previous_generation,"Child navigation retained parent authority")
	var child:=item();child.id=71;item_reply({"snapshot":child})
	check(model.phase==ItemModel.Phase.Ready and model.snapshot.id==71,"Child read did not settle")
	for mode in 3:
		setup();model.open(1000);service.poll();var contents_value:=item()
		if mode>0:contents_value.contents=[]
		if mode==2:contents_value.contents=[{"kind":2,"id":7,"item_type":-1,"caption":"native creature","flags":0,"can_dump":false,"can_melt":false}]
		item_reply({"snapshot":contents_value});check(model.phase==ItemModel.Phase.Ready,"Contents observation rejected")
		check(model.snapshot.has("contents")==bool(mode),"Unknown contents became empty")
		if mode==2:
			var isolated: Dictionary=model.view_snapshot();isolated.contents[0].caption="changed"
			check(model.snapshot.contents[0].caption=="native creature","Contents row aliases presentation")
	for fault in 4:
		setup();model.open(1000);service.poll();var contents_value:=item()
		contents_value.contents=[{"kind":2,"id":7,"item_type":-1,"caption":"native creature","flags":0,"can_dump":false,"can_melt":false}]
		match fault:
			0:contents_value.contents[0].id=-1
			1:contents_value.contents[0].kind=1
			2:contents_value.contents[0].can_dump=true
			3:contents_value.contents[0].item_type=0
		item_reply({"snapshot":contents_value});check(model.phase==ItemModel.Phase.Rejected,"Malformed contents accepted")
	var entry={"item_type":39,"material_token":"INORGANIC:COPPER","color_token":"COPPER","effective_armor_level":0,"metal":true,"coal":false,"contains_powder":false,"rolls_sheets":false,"protects_folded_sheets":false,"contains_writing":false}
	var look={"material_token":"PLANT:OAK:WOOD","subtype_raw":"","color_token":"BROWN","stack":1,"flags":0,"contents":{"container":true,"entries":[entry]}}
	check(ItemModel._valid_appearance(look,32),"complete bin facts accepted")
	for fault in 5:
		var bad: Dictionary=look.duplicate(true)
		if fault==0:bad.contents.container=false
		if fault==1:bad.contents.entries[0].item_type=93
		if fault==2:bad.contents.entries[0].metal=1
		if fault==3:bad.contents.entries[0].color_token="x".repeat(129)
		if fault==4:bad.contents.entries[0].unexpected=true
		check(not ItemModel._valid_appearance(bad,32),"invalid bin facts rejected")
	check(not ItemModel._valid_appearance(look,17),"contents cannot be attached to another family")
	for fault in 5:
		setup();model.open(1000);service.poll();var value:=item();value.item_type=39
		value.ammunition_assignment={"kind":1,"squad_id":-1,"caption":"native assignment"}
		if fault==1:value.item_type=53
		if fault==2:value.ammunition_assignment.kind=3
		if fault==3:value.ammunition_assignment.squad_id=120
		if fault==4:value.ammunition_assignment.caption=""
		item_reply({"snapshot":value})
		check(model.phase==(ItemModel.Phase.Ready if fault==0 else ItemModel.Phase.Rejected),"Ammunition assignment validation differs")
	for fault in 5:
		setup();model.open(1000);service.poll();var owned:=item()
		owned.owner={"id":988,"name":"native owner"}
		match fault:
			1:owned.owner.id=-1
			2:owned.owner.name="x".repeat(513)
			3:owned.owner.id="988"
			4:owned.owner.extra=true
		item_reply({"snapshot":owned})
		check(model.phase==(ItemModel.Phase.Ready if fault==0 else ItemModel.Phase.Rejected),"Owner validation differs: "+str(fault))
		if fault==0:
			var isolated: Dictionary=model.view_snapshot();isolated.owner.name="changed"
			check(model.snapshot.owner.name=="native owner","Owner snapshot is not isolated")
	ready();var original: Dictionary=model.view_snapshot();var calls_before: int=world.calls.size()
	model.poll(ItemModel.REFRESH_INTERVAL*0.5);service.poll()
	check(world.calls.size()==calls_before,"background refresh waits after receipt")
	model.poll(ItemModel.REFRESH_INTERVAL);service.poll()
	check(model.background_refresh and model.phase==ItemModel.Phase.Ready and model.snapshot==original,"background read retains visible authority")
	model.poll(100);service.poll();check(world.calls.size()==calls_before+1,"only one refresh in flight")
	item_reply({},C.ManagementStatus.Rejected)
	check(model.phase==ItemModel.Phase.Closed and model.item_id==-1 and model.snapshot.is_empty(),"missing refreshed item retires sheet")
	model.poll(100);service.poll();check(world.calls.size()==calls_before+1,"retired target never automatically retries")
	for sent in [false,true]:
		ready();model.poll(1)
		var old_ticket: int=model.ticket
		if sent:service.poll()
		model.set_flag(C.FarmOperation.ItemHidden,true)
		check(model.phase==ItemModel.Phase.Applying and not model.background_refresh and model.ticket!=old_ticket,"explicit edit preempts refresh")
		if sent:item_reply({"snapshot":item()})
		else:service.poll()
		check(world.calls[-1].request.action==C.ManagementAction.FarmEdit and not model.snapshot.hidden,"late refresh cannot replace pending edit")
		completed()
		check(model.snapshot.hidden and applied==1,"preempting edit completes with fresh snapshot")
	ready();check(model.phase==ItemModel.Phase.Ready,"item snapshot ready")
	check(world.calls[0].request=={"action":C.ManagementAction.ProductionInspect,"independent_item":true,"item_id":1000},"inspection has no paging or revision precondition")
	var copy: Dictionary=model.view_snapshot();copy.holder.name="changed"
	check(model.view_snapshot().holder.name=="native holder","nested holder is owned")
	for fault in 12:
		setup();model.open(1000);service.poll();var value:=item()
		match fault:
			0:value.id=1001
			1:value.building_id=969
			2:value.revision=0
			3:value.can_dump=1
			4:value.description="x".repeat(32769)
			5:value.weight="x".repeat(129)
			6:value.holder.id=-1
			7:value.holder.name="x".repeat(513)
			8:value.item_type=93
			9:value.erase("name")
			10:value.material_token="x".repeat(257)
			11:value.stockpile={"id":121,"type":4,"name":"bad type"}
		item_reply({"snapshot":value});check(model.phase==ItemModel.Phase.Rejected and model.snapshot.is_empty(),"invalid item rejected: "+str(fault))
	setup();model.open(1000);service.poll();var absent:=item();absent.erase("holder");item_reply({"snapshot":absent})
	check(model.phase==ItemModel.Phase.Ready and not model.snapshot.has("holder"),"absent holder stays absent")
	ready();var count: int=world.calls.size();model.set_flag(C.FarmOperation.ItemMelt,true);service.poll()
	check(world.calls.size()==count,"native melt eligibility respected")
	model.set_flag(C.FarmOperation.ItemHidden,true);model.set_flag(C.FarmOperation.ItemForbid,true);service.poll()
	check(world.calls.size()==count+1 and world.calls[-1].request.expected_revision==9007199254740993 and not model.snapshot.hidden,"single exact revision edit, no optimistic flag")
	completed();check(applied==1 and model.phase==ItemModel.Phase.Ready and model.snapshot.hidden and model.snapshot.description=="fresh native description","confirmed receipt adopts coherent native snapshot")
	check(world.calls.size()==count+1,"confirmed receipt needs no redundant read")
	model.poll(1);service.poll();var transferred:=item();transferred.erase("holder");transferred.stockpile={"id":121,"type":29,"name":"native stockpile"};transferred.revision+=2;transferred.stockpile_categories=1
	item_reply({"snapshot":transferred})
	check(model.phase==ItemModel.Phase.Ready and not model.snapshot.has("holder") and model.snapshot.stockpile.id==121,"same item survives transfer and replaces relationship authority")
	model.set_flag(C.FarmOperation.ItemHidden,true);service.poll()
	check(not world.calls[-1].request.has("building_id") and world.calls[-1].request.expected_revision==transferred.revision,"transferred item edit uses only current item authority")

	for fault in range(7):
		ready();model.poll(1);service.poll();var box:=item();box.item_type=30
		box.appearance={"material_token":box.material_token,"subtype_raw":box.subtype_raw,"color_token":"RED","stack":1,"flags":0}
		match fault:
			1:box.erase("appearance")
			2:box.appearance.material_token="mismatch"
			3:box.appearance.stack=0
			4:box.appearance.flags=1
			5:box.appearance.color_token="x".repeat(129)
			6:box.appearance.stack="1"
		item_reply({"snapshot":box})
		check((model.phase==ItemModel.Phase.Ready)==(fault==0),"BOX appearance authority: "+str(fault))

	for family in range(-1,5):
		for placed in range(-1,3):
			ready();model.poll(1);service.poll();var instrument:=item();instrument.item_type=13
			instrument.appearance={"material_token":instrument.material_token,"subtype_raw":instrument.subtype_raw,"color_token":"","stack":1,"flags":0,"instrument":{"family":family,"placed":placed}}
			item_reply({"snapshot":instrument})
			check((model.phase==ItemModel.Phase.Ready)==(family>=0 and family<=3 and placed>=0 and placed<=1),"Instrument definition authority")

	for kind in [1,2]:
		ready();model.poll(1);service.poll()
		var carried:=item();carried.erase("holder");carried.carrier={"kind":kind,"id":988,"item_type":30 if kind==1 else -1,"name":"native carrier"};carried.revision+=kind
		if kind==1:carried.carrier.appearance={"material_token":"WOOD","subtype_raw":"","color_token":"","stack":1,"flags":0}
		item_reply({"snapshot":carried})
		check(model.phase==ItemModel.Phase.Ready and model.snapshot.carrier.kind==kind,"carrier replaces item relationship authority")
		model.set_flag(C.FarmOperation.ItemHidden,true);service.poll()
		check(world.calls[-1].request.expected_revision==carried.revision,"carrier edit uses refreshed revision")
		for fault in ["kind","id","item_type","name","holder"]:
			ready();model.poll(1);service.poll();var invalid: Dictionary=carried.duplicate(true)
			if fault=="holder":invalid.holder={"id":1,"type":4,"name":"farm"}
			elif fault=="name":invalid.carrier.name="x".repeat(513)
			else:invalid.carrier[fault]=0 if fault=="kind" else -1 if fault=="id" or kind==1 else 0
			item_reply({"snapshot":invalid});check(model.snapshot.is_empty(),"invalid carrier grants no authority")

	for outcome in [2,3,4]:
		ready();model.set_flag(C.FarmOperation.ItemHidden,true);service.poll();count=world.calls.size()
		item_reply({"outcome":outcome},C.ManagementStatus.Rejected);model.set_flag(C.FarmOperation.ItemHidden,true);service.poll()
		check(model.phase==(ItemModel.Phase.Unknown if outcome==4 else ItemModel.Phase.Stale if outcome==3 else ItemModel.Phase.Rejected) and model.snapshot.is_empty() and world.calls.size()==count,"failed edit clears authority without replay")
		model.refresh();service.poll();item_reply({"snapshot":item()});check(model.phase==ItemModel.Phase.Ready,"explicit inspection recovers failed edit")
	ready();model.set_flag(C.FarmOperation.ItemHidden,true);service.poll();completed(true)
	check(model.phase==ItemModel.Phase.Unknown and applied==0,"inconsistent receipt cannot confirm edit")
	for editing in [false,true]:
		for sent in [false,true]:
			ready()
			if editing:model.set_flag(C.FarmOperation.ItemHidden,true)
			else:model.refresh()
			var pending: int=model.ticket
			if sent:service.poll()
			count=world.calls.size();model.close();service.poll()
			if sent:
				if editing:completed()
				else:item_reply({"snapshot":item()})
			else:check(service.result(pending).outcome=="not_sent","queued request cancelled")
			check(model.phase==ItemModel.Phase.Closed and model.snapshot.is_empty() and applied==0 and world.calls.size()==count,"close retires read/edit and suppresses follow-up")
	ready();model.refresh();service.poll();model.open(1001);item_reply({"snapshot":item()})
	check(model.item_id==1001 and model.snapshot.is_empty(),"late read cannot replace new target")
	item_reply({"snapshot":item(1001)});check(model.snapshot.id==1001,"replacement owns fresh snapshot")
	for sent in [false,true]:
		ready();model.set_flag(C.FarmOperation.ItemHidden,true);var pending: int=model.ticket
		if sent:service.poll()
		count=world.calls.size();world.state.world_epoch=6;service.poll()
		check(model.phase==ItemModel.Phase.Unavailable and model.item_id==-1 and model.snapshot.is_empty() and model.ticket==0,"epoch retires item ownership")
		check(service.result(pending).outcome==("unknown" if sent else "not_sent") and world.calls.size()==count,"epoch never replays edit")
	ready();model.set_flag(C.FarmOperation.ItemHidden,true);service.poll()
	model.changed.connect(func():
		if model.phase==ItemModel.Phase.Ready:model.close())
	completed();service.poll();check(model.phase==ItemModel.Phase.Closed and applied==0,"close during completion notification retires follow-up")
	model.dispose();service.free()
	if failures==0:print("ITEM_SHEET_STATE_PASS")
	quit(0 if failures==0 else 1)
