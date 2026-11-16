extends "res://tests/trade_session_wire_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Trade exchange bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-exchange-wire-expected.json"))
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
	var model=Model.new();model.configure(service);model.limits.assign([64,64])
	model.open(int(expected.depot))
	if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
	for intent in expected.intents:
		var side:=int(intent.side);var found:=-1
		for index in range(model.pages[side].rows.size()):
			if not model.pages[side].rows[index].group and model.pages[side].rows[index].id==int(intent.item):found=index;break
		if not check(found>=0,"Trade selection item missing"):quit(1);return
		model.toggle_row(side,found)
		if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
	var first_revision: int=model.revision
	model.exchange();var pending: int=model.ticket;model.exchange()
	check(model.ticket==pending and model.phase==Model.Phase.Exchanging,"Duplicate Trade submitted while pending")
	if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
	var counter: Dictionary=model.conversation.duplicate(true)
	var wanted: Array=[];for id in expected.counter_items:wanted.append(int(id))
	check(counter.dialogue==24 and counter.counter_offer and counter.requested_items==wanted,"Native counteroffer changed across transport")
	check(model.counter_page.total==wanted.size() and model.counter_page.rows.size()==wanted.size(),"Counteroffer page missing")
	var counter_revision: int=model.revision
	await session_request({"action":C.ManagementAction.TradeSessionExchange,"session":model.session,"expected_revision":first_revision},C.TradeSessionOutcome.Rejected)
	model.refresh_session();await poll_controller(service,model,Model.Phase.Active)
	check(model.conversation==counter and model.revision==counter_revision,"Refresh lost the counteroffer")
	model.exchange()
	if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
	var final: Dictionary=model.conversation.duplicate(true)
	check(final.dialogue==7 and not final.counter_offer and final.requested_items==wanted,"Accepted native conversation changed")
	await session_request({"action":C.ManagementAction.TradeSessionExchange,"session":model.session,"expected_revision":counter_revision},C.TradeSessionOutcome.Rejected)
	var result: Dictionary={"success":not failed,"counter":counter,"final":final,"pages":model.pages.duplicate(true),"revision":model.revision}
	var accepted_revision: int=model.revision
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Counteroffer UI assets missing"):quit(1);return
	var view=preload("res://scripts/trade_goods_view.gd").new();root.add_child(view);view.configure_goods(world,model);view.position=Vector2(48,148);view.layout(Vector2(944,708))
	for i in 3:await process_frame
	check(view.counter.visible and not view.searches[1].visible,"Counteroffer pane did not replace fortress goods")
	for pressed in [true,false]:
		var click:=InputEventMouseButton.new();click.position=Vector2(920,166);click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed;root.push_input(click,true);await process_frame
	pending=model.ticket;model.dismiss_counteroffer()
	check(model.ticket==pending,"Duplicate Okay submitted")
	if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
	check(model.counter_page.is_empty() and model.conversation.requested_items.is_empty() and not model.conversation.counter_offer and model.conversation.dialogue==final.dialogue and model.revision==accepted_revision+1,"Okay altered negotiation or failed to clear the pane")
	await session_request({"action":C.ManagementAction.TradeSessionDismiss,"session":model.session,"expected_revision":accepted_revision},C.TradeSessionOutcome.Rejected)
	await session_request({"action":C.ManagementAction.TradeSessionDismiss,"session":model.session,"expected_revision":model.revision},C.TradeSessionOutcome.Rejected)
	check(not view.counter.visible and view.searches[1].visible,"Okay did not restore the fortress goods pane")
	view.queue_free();await process_frame
	result.dismiss_verified=true;result.dismissed=model.conversation.duplicate(true);result.dismissed_revision=model.revision
	var closed: Array=[]
	service.completed.connect(func(_ticket,response):
		if response.get("action")==C.ManagementAction.TradeSessionClose:closed.append(response))
	model.close();deadline=Time.get_ticks_msec()+5000
	while closed.is_empty() and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(closed.size()==1,"Trade exchange session did not close");result.success=not failed
	model.dispose();service.queue_free()
	var file=FileAccess.open(directory+"/trade-exchange-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close()
	world.queue_free();await process_frame
	if not failed:print("TRADE_EXCHANGE_WIRE_PASS")
	quit(1 if failed else 0)
