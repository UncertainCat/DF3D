extends "res://tests/trade_session_wire_live.gd"
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Trade transfer bridge attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-transfer-wire-expected.json"))
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
	var action: int=C.ManagementAction.TradeSessionGift if int(expected.side)==1 else C.ManagementAction.TradeSessionSeize
	var method: String="offer_gift" if int(expected.side)==1 else "seize"
	var view=preload("res://scripts/trade_view.gd").new();root.add_child(view)
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Trade UI assets missing"):quit(1);return
	view.configure_trade(world,model);view.layout(Vector2(1200,800))
	for i in 3:await process_frame
	deadline=Time.get_ticks_msec()+10000
	while model.appearance_pending() and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(not model.appearance_pending(),"Trade artwork did not finish")
	var before_view: Dictionary={"header":model.header.duplicate(true),"footer":model.footer.duplicate(true),"entry":model.entry.duplicate(true),"actions":model.actions.duplicate(true),"pages":model.pages.duplicate(true),"appearances":model.appearances.duplicate(true)}
	check(model.actions.size()==3 and view.actions.actions==model.actions,"Action summary missing from composite")
	var button_index: int=2 if int(expected.side)==1 else 0
	check(model.actions[button_index].enabled,"Native transfer action disabled")
	var point: Vector2=view.frame.position+view.actions.position+view.actions.buttons[button_index].get_center()
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	var pending: int=model.ticket;model.call(method)
	check(model.ticket==pending and model.phase==Model.Phase.Exchanging,"Duplicate transfer submitted")
	if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
	var final: Dictionary=model.conversation.duplicate(true)
	check(final.dialogue==int(expected.dialogue) and not final.counter_offer and model.revision==first_revision+1,"Transfer outcome mismatch")
	await session_request({"action":action,"session":model.session,"expected_revision":first_revision},C.TradeSessionOutcome.Rejected)
	model.refresh_session()
	if not await poll_controller(service,model,Model.Phase.Active):quit(1);return
	check(model.conversation==final,"Refresh lost transfer conversation")
	var result: Dictionary={"before_view":before_view,"conversation":final,"pages":model.pages.duplicate(true),"revision":model.revision}
	var old_session: int=model.session;var old_revision: int=model.revision
	var closed: Array=[]
	service.completed.connect(func(_ticket,response):
		if response.get("action")==C.ManagementAction.TradeSessionClose:closed.append(response))
	model.close();deadline=Time.get_ticks_msec()+5000
	while closed.is_empty() and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(closed.size()==1,"Trade transfer session did not close")
	await session_request({"action":action,"session":old_session,"expected_revision":old_revision},C.TradeSessionOutcome.Rejected)
	result.success=not failed
	view.queue_free();await process_frame
	model.dispose();service.queue_free()
	var file=FileAccess.open(directory+"/trade-transfer-wire-result.json",FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close()
	world.queue_free();await process_frame
	if not failed:print("TRADE_TRANSFER_WIRE_PASS")
	quit(1 if failed else 0)
