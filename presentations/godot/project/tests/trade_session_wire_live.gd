extends "res://tests/machinery_wire_live.gd"
var receipts: Array=[]
const Model=preload("res://scripts/trade_catalog_state.gd")
func poll_controller(service,model,terminal: int) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while model.phase in [Model.Phase.Reading,Model.Phase.Choosing,Model.Phase.Checking] and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	return check(model.phase==terminal,"Trade controller did not reach expected phase: "+str(model.phase))
func controller_workflow(depot: int) -> Dictionary:
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true);service.set_process(false)
	var model=Model.new();model.configure(service)
	var closed: Array=[];service.completed.connect(func(_ticket,result):
		if result.get("action")==C.ManagementAction.TradeSessionClose:closed.append(result.get("trade_session",{})))
	model.open(depot)
	if not await poll_controller(service,model,Model.Phase.Active):model.dispose();service.queue_free();return {}
	var initial: int=model.session
	model.refresh_session();await poll_controller(service,model,Model.Phase.Active)
	check(model.session==initial,"Controller read replaced session")
	model.close()
	var deadline:=Time.get_ticks_msec()+5000
	while closed.size()<1 and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(closed.size()==1 and closed[0].get("outcome")==C.TradeSessionOutcome.Closed and closed[0].get("session")==initial,"Controller close did not retire native session")
	# Stop observing an open after it was sent, before consuming its response.
	model.open(depot);deadline=Time.get_ticks_msec()+5000
	while model.phase==Model.Phase.Reading and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	check(model.phase==Model.Phase.Choosing and model.ticket>0,"Cancellation did not reach a pending open")
	var opening: int=model.ticket
	check(service._requests.get(opening,{}).get("sequence",0)>0,"Cancellation open was not sent")
	model.dispose()
	deadline=Time.get_ticks_msec()+5000
	while closed.size()<2 and Time.get_ticks_msec()<deadline:
		world.poll();service.poll(0.01);await create_timer(0.01).timeout
	var late: Dictionary=service.result(opening).get("trade_session",{})
	check(late.get("outcome")==C.TradeSessionOutcome.Available and closed.size()==2 and closed[1].get("session")==late.get("session") and closed[1].get("outcome")==C.TradeSessionOutcome.Closed,"Disposed panel's late session was not retired")
	check(model.phase==Model.Phase.Closed and model.session==0,"Late open revived disposed panel")
	var result: Dictionary={"initial_session":initial,"late_open":late,"closes":closed}
	service.queue_free();await process_frame
	return result
func session_request(intent: Dictionary,outcome: int) -> Dictionary:
	var response:=await request("trade_session",intent)
	var value: Dictionary=response.get("trade_session",{})
	check(response.get("status")==C.ManagementStatus.Ok and value.get("outcome")==outcome,"Trade session receipt differs: "+str(response))
	receipts.append(value);return value
func catalog_token(depot: int) -> int:
	var response:=await request("trade_catalog",{"action":C.ManagementAction.TradeCatalogRead,"depot_id":depot})
	var rows: Array=response.get("trade_catalog",{}).get("choices",[])
	if not check(rows.size()==1,"Expected one native merchant"):return 0
	return rows[0].token
func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.attach(),"Trade session attach failed"):quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		world.poll()
		if world.poll_management().get("transport_alive",false):break
		await create_timer(0.01).timeout
	await request("construction",{"action":C.ManagementAction.Catalog})
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/trade-session-wire-expected.json"))
	var depot:=int(expected.depot_id)
	var token:=await catalog_token(depot)
	for intent in [{"action":C.ManagementAction.TradeSessionOpen,"depot_id":depot,"choice_token":0},{"action":C.ManagementAction.TradeSessionOpen,"depot_id":depot,"choice_token":1.5},{"action":C.ManagementAction.TradeSessionRead,"session":1,"expected_revision":0},{"action":C.ManagementAction.TradeSessionClose,"session":1,"extra":0}]:
		check(world.management_request("trade_session",intent)==0,"Malformed trade request reached transport")
	await session_request({"action":C.ManagementAction.TradeSessionOpen,"depot_id":depot,"choice_token":token+999},C.TradeSessionOutcome.Rejected)
	var sessions: Array=[]
	for iteration in range(3):
		if iteration>0:token=await catalog_token(depot)
		var opened:=await session_request({"action":C.ManagementAction.TradeSessionOpen,"depot_id":depot,"choice_token":token},C.TradeSessionOutcome.Available)
		if not check(opened.get("session",0)>0 and opened.get("revision")==1 and opened.has("entry"),"Missing opened session"):break
		check(not sessions.has(opened.session),"Session identity reused");sessions.append(opened.session)
		var entry: Dictionary=opened.entry
		check(entry.title==expected.title and entry.entity_id==expected.entity_id and entry.fortress_trader==expected.fortress_trader,"Native entry changed across transport")
		var read: Dictionary={"action":C.ManagementAction.TradeSessionRead,"session":opened.session,"expected_revision":1}
		await session_request(read,C.TradeSessionOutcome.Available)
		await session_request({"action":C.ManagementAction.TradeSessionOpen,"depot_id":depot,"choice_token":token},C.TradeSessionOutcome.Rejected)
		await session_request({"action":C.ManagementAction.TradeSessionRead,"session":opened.session,"expected_revision":2},C.TradeSessionOutcome.Rejected)
		await session_request(read,C.TradeSessionOutcome.Available)
		if iteration==1:
			await catalog_token(depot)
		else:
			await session_request({"action":C.ManagementAction.TradeSessionClose,"session":opened.session+100},C.TradeSessionOutcome.Rejected)
			var closed:=await session_request({"action":C.ManagementAction.TradeSessionClose,"session":opened.session},C.TradeSessionOutcome.Closed)
			check(closed.get("session")==opened.session,"Close receipt lost session identity")
		await session_request(read,C.TradeSessionOutcome.Rejected)
	var controller:=await controller_workflow(depot)
	var file:=FileAccess.open(directory+"/trade-session-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed,"receipts":receipts,"sessions":sessions,"controller":controller}));file.close()
	world.queue_free();await process_frame;quit(1 if failed else 0)
