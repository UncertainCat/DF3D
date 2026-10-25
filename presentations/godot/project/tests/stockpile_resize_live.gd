extends "res://tests/areas_acceptance_live.gd"
# Protected semantic acceptance, with independent DF observations. UI lifecycle
# and rendering remain separate requirements.
func exercise() -> void:
	await request({"action":0})
	if stopped: return
	step = "stocked pile resize setup"
	var setup := await native("resize_setup")
	if stopped: return
	for rows in [setup.erase,setup.grow,setup.keep]:
		for row in rows:
			for key in ["x","y","length"]: row[key] = int(row[key])
	var pile := await inspect(int(setup.id))
	if stopped: return
	var intent := {"action":11,"kind":0,"id":int(pile.id),"expected_revision":int(pile.revision),
		"operation":Contract.AreaOperation.Paint,"paint_mode":2,"paint_z":int(pile.origin.z),"spans":setup.erase}
	step = "malformed parallel storage vectors refuse before mutation"
	await native("resize_malformed")
	await request(intent,"Invalid area paint geometry")
	if stopped: return
	await native("resize_restore")
	step = "native assignment release and limit clamp"
	var receipt := await request(intent)
	if stopped: return
	if not check(receipt.areas.size() == 1 and int(receipt.areas[0].tile_count) == 1,"shrink did not return one occupied tile"): return
	await native("resize_check",{"tiles":1})
	step = "stale resize must not replay"
	await request(intent,"Area changed; inspect again")
	if stopped: return
	await native("resize_check",{"tiles":1})
	step = "regrow retains clamped limits and released assignments"
	pile = receipt.areas[0]
	intent.expected_revision = int(pile.revision); intent.paint_mode = 1; intent.spans = setup.grow
	receipt = await request(intent)
	if stopped: return
	await native("resize_check",{"tiles":2})
	step = "empty footprint retains identity and assignments during painting"
	intent.expected_revision = int(receipt.areas[0].revision); intent.paint_mode = 2
	intent.spans = setup.grow + setup.keep
	receipt = await request(intent)
	if stopped: return
	if not check(receipt.areas.size() == 1 and int(receipt.areas[0].tile_count) == 0,"empty pile receipt missing"): return
	await native("resize_check",{"tiles":0})
	step = "regrow empty pile with the same identity"
	intent.expected_revision = int(receipt.areas[0].revision); intent.paint_mode = 1; intent.spans = setup.keep
	receipt = await request(intent)
	if stopped: return
	await native("resize_check",{"tiles":1})
	step = "empty pile removal on painting exit"
	intent.expected_revision = int(receipt.areas[0].revision); intent.paint_mode = 2
	receipt = await request(intent)
	if stopped: return
	await native("resize_check",{"tiles":0})
	await request({"action":12,"kind":0,"id":int(pile.id),"expected_revision":int(receipt.areas[0].revision)})
	if stopped: return
	await native("resize_deleted")
	await native("final")
