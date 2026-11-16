extends "res://tests/chest_scene_live.gd"
var trade_clicks:=0
func expected_filename() -> String:return "depot-wire-expected.json"
func result_filename() -> String:
	var label:=OS.get_environment("DF3D_DEPOT_GATE_LABEL")
	return "depot-scene-gate-"+label+"-result.json" if not label.is_empty() else "depot-scene-result.json"
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("furniture")
	# Staged owner only; public map routes remain hidden until goods/trade are ready.
	owner.open_target(int(expected.id))
	if not await chest_ready():return
	if expected.has("trade_worker"):
		check(owner.state.snapshot.depot.worker_id==int(expected.trade_worker),"Native trader presence differs")
		await panel_capture("depot-trade-present" if expected.trade_worker>=0 else "depot-trade-absent",expected.reference)
		owner.panel.trade_requested.connect(func():trade_clicks+=1)
		await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(64,144))
		check(trade_clicks==(1 if expected.trade_worker>=0 else 0),"Trade click did not respect native trader presence")
		if expected.trade_worker>=0:
			if not await trade_ready(int(expected.trade_choices)):return
			if int(expected.trade_choices)>1:
				await pointer(owner.trade_view.catalog.rows.get_global_transform_with_canvas()*Vector2(100,18))
				if not await trade_ready(1):return
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null and owner.trade.session==0 and not owner.trade_mode and not owner.trade_view.visible,"Trade close retained panel/session ownership")
		if expected.trade_worker>=0:
			# Retire an outstanding catalog read through the actual panel close path.
			owner.open_target(int(expected.id))
			if not await chest_ready():return
			owner._open_trade();owner.close_panel();await drain()
			check(owner.trade.phase==owner.trade.Phase.Closed and owner.trade.session==0 and not owner.trade_mode,"Late catalog reply revived closed Trade")
			owner.open_target(int(expected.id))
			if not await chest_ready():return
			await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(64,144))
			if not await trade_ready(int(expected.trade_choices)):return
			owner.set_play_enabled(false);await drain()
			check(scene._ui.host.active==null and owner.trade.session==0 and not owner.trade_view.visible,"Play disable retained Trade")
		exercised=true;return
	if expected.has("reference"):
		check(owner.state.snapshot.depot.broker_id==int(expected.broker_id),"Depot broker identity differs")
		await panel_capture("depot-broker",expected.reference)
		if int(expected.broker_id)>=0:
			for offset in [Vector2(18,18),Vector2(168,18)]:
				await pointer(owner.panel.get_global_transform_with_canvas()*(owner.panel.broker_rect().position+offset))
				check(scene._ui.host.active==owner and owner.panel.visible and owner.state.building_id==int(expected.id),"Informational broker row navigated away from depot")
		key(KEY_ESCAPE);await drain()
		check(scene._ui.host.active==null,"Depot retained broker panel ownership")
		exercised=true
		return
	await panel_capture("depot-idle","depot-settings-idle")
	for step in [[0,"broker"],[1,"anyone"],[0,"broker-again"],[2,"dismissed"],[1,"anyone-fresh"],[2,"dismissed-anyone"],[0,"broker"],[2,"idle"]]:
		await pointer(owner.panel.get_global_transform_with_canvas()*owner.panel.mode_rect(step[0]).get_center())
		if not await chest_ready():return
		check(owner.state.snapshot.depot.requested==(step[0]!=2),"Depot request pointer failed")
		await panel_capture("depot-"+step[1],"depot-settings-"+step[1])
	key(KEY_ESCAPE);await drain()
	check(scene._ui.host.active==null,"Depot retained ownership")
	exercised=true

func trade_ready(choices: int) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01)
		if (choices>1 and owner.trade.phase==owner.trade.Phase.Ready) or (choices==1 and owner.trade.goods_ready()):
			return check(owner.trade_mode and owner.trade_view.visible and not owner.panel.visible and scene._ui.host.active==owner,"Trade lost exclusive panel ownership")
		if owner.trade.phase in [owner.trade.Phase.Rejected,owner.trade.Phase.Unknown,owner.trade.Phase.Unavailable]:break
		await create_timer(0.01).timeout
	return check(false,"Trade did not settle: "+str(owner.trade.phase))
