extends "res://tests/trade_session_wire_live.gd"
var view
func select_item(model,side: int,index: int) -> void:model.toggle_row(side,index)
func exchange_click() -> void:
	var point: Vector2=view.frame.position+view.actions.position+view.actions.buttons[1].get_center()
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func snapshot_view(service,model) -> Dictionary:
	for i in 3:await process_frame
	var deadline:=Time.get_ticks_msec()+10000
	while model.appearance_pending() and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(not model.appearance_pending(),"Counteroffer artwork did not finish")
	return {"header":model.header.duplicate(true),"footer":model.footer.duplicate(true),"entry":model.entry.duplicate(true),"actions":model.actions.duplicate(true),"pages":model.pages.duplicate(true),"appearances":model.appearances.duplicate(true),"conversation":model.conversation.duplicate(true),"counter_page":model.counter_page.duplicate(true)}
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	if not await initialize_world():quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-exchange-wire-expected.json"))
	var owners: Dictionary=await create_models(expected)
	if owners.is_empty():quit(1);return
	var service=owners.service;var model=owners.model
	if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
	for intent in expected.intents:
		var side:=int(intent.side);var found:=-1
		for index in range(model.pages[side].rows.size()):
			if not model.pages[side].rows[index].group and model.pages[side].rows[index].id==int(intent.item):found=index;break
		if not check(found>=0,"Trade selection item missing"):quit(1);return
		await select_item(model,side,found)
		if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
	if not configure_view(model):quit(1);return
	for i in 3:await process_frame
	var first_revision: int=model.revision
	exchange_click();var pending: int=model.ticket;model.exchange()
	check(model.ticket==pending and model.phase==Model.Phase.Exchanging,"Duplicate Trade submitted while pending")
	if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
	var counter: Dictionary=model.conversation.duplicate(true)
	var wanted: Array=[];for id in expected.counter_items:wanted.append(int(id))
	check(counter.dialogue==24 and counter.counter_offer and counter.requested_items==wanted,"Native counteroffer changed across transport")
	check(model.counter_page.total==wanted.size() and model.counter_page.rows.size()==wanted.size(),"Counteroffer page missing")
	var counter_view: Dictionary=await snapshot_view(service,model)
	await capture_state("counter")
	check(view.actions.actions[1].caption=="Accept Counteroffer","Composite omitted native acceptance caption")
	var counter_revision: int=model.revision
	await session_request({"action":C.ManagementAction.TradeSessionExchange,"session":model.session,"expected_revision":first_revision},C.TradeSessionOutcome.Rejected)
	model.refresh_session();await poll_controller(service,model,Model.Phase.Active)
	check(model.conversation==counter and model.revision==counter_revision,"Refresh lost the counteroffer")
	var active_okay_view: Dictionary={}
	if expected.get("active_okay",false):
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new();event.position=Vector2(920,166);event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
		if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
		check(model.counter_page.is_empty() and model.conversation.counter_offer and model.conversation.requested_items.is_empty() and model.conversation.dialogue==24,"Active Okay lost the retained counteroffer")
		check(model.actions[1].caption=="Accept Counteroffer" and view.goods.searches[1].visible,"Active Okay did not restore goods with acceptance available")
		await session_request({"action":C.ManagementAction.TradeSessionDismiss,"session":model.session,"expected_revision":counter_revision},C.TradeSessionOutcome.Rejected)
		counter_revision=model.revision
		active_okay_view=await snapshot_view(service,model)
	exchange_click()
	if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
	var final: Dictionary=model.conversation.duplicate(true)
	check(final.dialogue==7 and not final.counter_offer and final.requested_items==([] if expected.get("active_okay",false) else wanted),"Accepted native conversation changed")
	await session_request({"action":C.ManagementAction.TradeSessionExchange,"session":model.session,"expected_revision":counter_revision},C.TradeSessionOutcome.Rejected)
	var accepted_view: Dictionary=await snapshot_view(service,model)
	await capture_state("accepted")
	var result: Dictionary={"counter_view":counter_view,"accepted_view":accepted_view,"active_okay_view":active_okay_view,"success":not failed,"counter":counter,"final":final,"pages":model.pages.duplicate(true),"revision":model.revision}
	var accepted_revision: int=model.revision
	if not expected.get("active_okay",false):
		for i in 3:await process_frame
		check(view.goods.counter.visible and not view.goods.searches[1].visible,"Counteroffer pane did not replace fortress goods")
		for pressed in [true,false]:
			var click:=InputEventMouseButton.new();click.position=Vector2(920,166);click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed;root.push_input(click,true);await process_frame
		pending=model.ticket;model.dismiss_counteroffer()
		check(model.ticket==pending,"Duplicate Okay submitted")
		if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
		check(model.counter_page.is_empty() and model.conversation.requested_items.is_empty() and not model.conversation.counter_offer and model.conversation.dialogue==final.dialogue and model.revision==accepted_revision+1,"Okay altered negotiation or failed to clear the pane")
		await session_request({"action":C.ManagementAction.TradeSessionDismiss,"session":model.session,"expected_revision":accepted_revision},C.TradeSessionOutcome.Rejected)
		await session_request({"action":C.ManagementAction.TradeSessionDismiss,"session":model.session,"expected_revision":model.revision},C.TradeSessionOutcome.Rejected)
		check(not view.goods.counter.visible and view.goods.searches[1].visible,"Okay did not restore the fortress goods pane")
	retire_view();await process_frame
	result.dismiss_verified=true;result.dismissed=model.conversation.duplicate(true);result.dismissed_revision=model.revision
	var closed: Array=[]
	service.completed.connect(func(_ticket,response):
		if response.get("action")==C.ManagementAction.TradeSessionClose:closed.append(response))
	close_model(model);deadline=Time.get_ticks_msec()+5000
	while closed.is_empty() and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(closed.size()==1,"Trade exchange session did not close");result.success=not failed;result.surface=surface()
	var file=FileAccess.open(directory+"/trade-exchange-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close()
	dispose_models(service,model);await process_frame
	if not failed:print("TRADE_EXCHANGE_WIRE_PASS")
	quit(1 if failed else 0)

func initialize_world() -> bool:
	world=Df3dWorld.new();root.add_child(world)
	return check(world.attach(),"Trade exchange bridge attach failed")
func create_models(expected: Dictionary) -> Dictionary:
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
	var model=Model.new();model.configure(service);model.limits.assign([64,64]);model.open(int(expected.depot))
	return {"service":service,"model":model}
func configure_view(model) -> bool:
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Trade UI assets missing"):return false
	view=preload("res://scripts/trade_view.gd").new();root.add_child(view);view.configure_trade(world,model);view.layout(Vector2(1200,800))
	return true
func capture_state(_label: String) -> void:pass
func retire_view() -> void:view.queue_free()
func close_model(model) -> void:model.close()
func dispose_models(service,model) -> void:model.dispose();service.queue_free();world.queue_free()
func surface() -> String:return "assembled Trade view"
