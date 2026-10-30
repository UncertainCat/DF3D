extends "res://tests/building_contents_state_test.gd"
const ItemModel=preload("res://scripts/item_sheet_state.gd")

func setup() -> void:
	if model!=null:model.dispose();service.free()
	world=World.new();service=Service.new();service.configure(world);model=ItemModel.new();model.configure(service)
	applied=0;model.applied.connect(func():applied+=1)

func item(id:=1000) -> Dictionary:
	var value: Dictionary=page().rows[0].duplicate(true)
	value.merge({"id":id,"building_id":968,"revision":9007199254740993,"completed":true,"removing":false,
		"weight":"native weight","description":"native description","holder":{"id":968,"type":4,"name":"native holder"}},true)
	return value

func item_reply(production: Dictionary, status:=C.ManagementStatus.Ok) -> void:
	production=production.duplicate(true);production.selected_building=968
	world.state={"world_epoch":5,"revision":world.calls.size()+1,"request_seq":world.calls.size(),"action":world.calls[-1].request.action,
		"status":status,"production":production}
	service.poll()

func ready() -> void:
	setup();model.open(968,1000);service.poll();item_reply({"item":item()})

func completed(wrong_flag:=false) -> void:
	var value:=page(0,9007199254740994);value.rows[0].hidden=not wrong_flag
	item_reply({"contents":value,"farm_edit_outcome":C.FarmEditOutcome.Completed,
		"contents_edit":{"item_id":1000,"farm_operation":C.FarmOperation.ItemHidden,"value":1}})

func run() -> void:
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
		if sent:item_reply({"item":item()})
		else:service.poll()
		check(world.calls[-1].request.action==C.ManagementAction.FarmEdit and not model.snapshot.hidden,"late refresh cannot replace pending edit")
		completed();var edited:=item();edited.hidden=true;item_reply({"item":edited})
		check(model.snapshot.hidden and applied==1,"preempting edit completes with fresh snapshot")
	ready();check(model.phase==ItemModel.Phase.Ready,"item snapshot ready")
	check(world.calls[0].request=={"action":C.ManagementAction.ProductionInspect,"building_id":968,"item_id":1000},"inspection has no paging or revision precondition")
	var copy: Dictionary=model.view_snapshot();copy.holder.name="changed"
	check(model.view_snapshot().holder.name=="native holder","nested holder is owned")
	for fault in 12:
		setup();model.open(968,1000);service.poll();var value:=item()
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
			11:value.role=-1
		item_reply({"item":value});check(model.phase==ItemModel.Phase.Rejected and model.snapshot.is_empty(),"invalid item rejected: "+str(fault))
	setup();model.open(968,1000);service.poll();var absent:=item();absent.erase("holder");item_reply({"item":absent})
	check(model.phase==ItemModel.Phase.Ready and not model.snapshot.has("holder"),"absent holder stays absent")
	ready();var count: int=world.calls.size();model.set_flag(C.FarmOperation.ItemMelt,true);service.poll()
	check(world.calls.size()==count,"native melt eligibility respected")
	model.set_flag(C.FarmOperation.ItemHidden,true);model.set_flag(C.FarmOperation.ItemForbid,true);service.poll()
	check(world.calls.size()==count+1 and world.calls[-1].request.expected_revision==9007199254740993 and not model.snapshot.hidden,"single exact revision edit, no optimistic flag")
	completed();check(applied==1 and model.phase==ItemModel.Phase.Reading and model.snapshot.is_empty(),"confirmed edit requires fresh item inspection")
	check(world.calls[-1].request.action==C.ManagementAction.ProductionInspect and not world.calls[-1].request.has("expected_revision"),"completion issues only fresh read")
	var refreshed:=item();refreshed.hidden=true;refreshed.description="fresh native description";refreshed.revision+=1
	item_reply({"item":refreshed});check(model.phase==ItemModel.Phase.Ready and model.snapshot==refreshed,"new text and flags arrive coherently")
	for outcome in [2,3,4]:
		ready();model.set_flag(C.FarmOperation.ItemHidden,true);service.poll();count=world.calls.size()
		item_reply({"farm_edit_outcome":outcome},C.ManagementStatus.Rejected);model.set_flag(C.FarmOperation.ItemHidden,true);service.poll()
		check(model.phase==(ItemModel.Phase.Unknown if outcome==4 else ItemModel.Phase.Stale if outcome==3 else ItemModel.Phase.Rejected) and model.snapshot.is_empty() and world.calls.size()==count,"failed edit clears authority without replay")
		model.refresh();service.poll();item_reply({"item":item()});check(model.phase==ItemModel.Phase.Ready,"explicit inspection recovers failed edit")
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
				else:item_reply({"item":item()})
			else:check(service.result(pending).outcome=="not_sent","queued request cancelled")
			check(model.phase==ItemModel.Phase.Closed and model.snapshot.is_empty() and applied==0 and world.calls.size()==count,"close retires read/edit and suppresses follow-up")
	ready();model.refresh();service.poll();model.open(968,1001);item_reply({"item":item()})
	check(model.item_id==1001 and model.snapshot.is_empty(),"late read cannot replace new target")
	item_reply({"item":item(1001)});check(model.snapshot.id==1001,"replacement owns fresh snapshot")
	for sent in [false,true]:
		ready();model.set_flag(C.FarmOperation.ItemHidden,true);var pending: int=model.ticket
		if sent:service.poll()
		count=world.calls.size();world.state.world_epoch=6;service.poll()
		check(model.phase==ItemModel.Phase.Unavailable and model.item_id==-1 and model.snapshot.is_empty() and model.ticket==0,"epoch retires item ownership")
		check(service.result(pending).outcome==("unknown" if sent else "not_sent") and world.calls.size()==count,"epoch never replays edit")
	ready();model.set_flag(C.FarmOperation.ItemHidden,true);service.poll()
	model.changed.connect(func():
		if model.phase==ItemModel.Phase.Reading:model.close())
	completed();service.poll();check(model.phase==ItemModel.Phase.Closed and applied==0,"close during completion notification retires follow-up")
	model.dispose();service.free()
	if failures==0:print("ITEM_SHEET_STATE_PASS")
	quit(0 if failures==0 else 1)
