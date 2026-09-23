extends SceneTree
var failures := 0
func check(ok: bool, why: String):
	if not ok:
		failures += 1
		push_error(why)
func _initialize():
	call_deferred("run")
func run():
	var world := Df3dWorld.new()
	root.add_child(world)
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/effect-events.df3dfix")), "source fixture loads")
	world.set_replay_speed(0.0)
	world.set_fixed_render_tick(89.0)
	world.poll()
	check(world.effect_events().is_empty(), "report cannot lead delayed presentation tick")
	check(world.unit_combat_events().is_empty(), "wound cannot lead delayed presentation tick")
	check(world.item_contact_events(0).is_empty(), "contact cannot lead delayed presentation tick")
	check(world.resolved_attack_events(0).is_empty(), "resolved attack waits for delayed tick")
	check(world.projectile_combat_events(0).is_empty(), "projectile phase waits for delayed tick")
	world.set_fixed_render_tick(90.0)
	world.poll()
	var reports: Array = world.effect_events()
	check(reports.size() == 1, "only due report is returned")
	if reports.size() == 1:
		check(reports[0].type == "COMBAT_PARRY" and reports[0].has_position, "native token and position survive")
		check(reports[0].position == Vector3i(3,4,1) and reports[0].position2 == Vector3i(5,4,1), "report coordinates stay DF xyz")
		check(not reports[0].has("success") and not reports[0].has("attacker_id"), "no invented defense outcome or roles")
	check(world.effect_events(1).is_empty(), "cursor suppresses repeats without draining other consumers")
	check(world.effect_events().size() == 1, "journal query is nondestructive")
	world.set_fixed_render_tick(98.0)
	world.poll()
	var wounds: Array = world.unit_combat_events()
	check(wounds.size() == 1, "due confirmed wound returned")
	if wounds.size() == 1:
		check(wounds[0].weapon_source == "observed_action" and wounds[0].report_id == 51, "weapon context provenance survives")
		check(wounds[0].weapon_material == "wood" and wounds[0].weapon.id == 8, "observed weapon identity and material survive")
	var releases: Array = world.projectile_release_events()
	var contacts: Array = world.item_contact_events(0)
	check(contacts.size() == 1, "positive item contact survives transport")
	if contacts.size() == 1:
		check(contacts[0].first.id == 10 and contacts[0].second.id == 11, "both exact contact identities survive")
		check(contacts[0].first.material_token == "INORGANIC:IRON", "source material retained independently of presentation classification")
	check(world.item_contact_events(1).is_empty() and world.item_contact_events(0).size() == 1, "contact cursors are independent nondestructive queries")
	check(world.item_contact_stats().source_dropped == 2, "contact source overflow visible")
	check(world.item_contact_stats().available, "source capability distinguishable from silent combat")
	check(releases.size() == 1, "due observed projectile release returned")
	if releases.size() == 1:
		check(releases[0].launcher_type == "ITEM_WEAPON_CROSSBOW" and releases[0].launcher_material == "wood", "exact launcher metadata survives")
		check(releases[0].ammunition_material == "bone" and releases[0].item_id == 9, "actual ammunition metadata survives")
	world.set_fixed_render_tick(100.0)
	world.poll()
	reports = world.effect_events(1)
	check(reports.size() == 1 and not reports[0].has_position, "nonspatial report is preserved")
	check(world.effect_event_stats().source_dropped == 7, "source overflow remains observable")
	world.set_fixed_render_tick(89.0)
	world.poll()
	check(world.effect_events().is_empty(), "fixed presentation rewind re-applies due-tick gate")
	check(world.item_contact_events(0).is_empty(), "contact due gate respects presentation rewind")
	world.set_fixed_render_tick(98.0)
	world.poll()
	var attacks: Array = world.resolved_attack_events(0)
	check(attacks.size() == 1, "resolved attack survives adapter")
	if attacks.size() == 1:
		check(attacks[0].attacker_id == 1 and attacks[0].action_id == 7, "execution identities preserved")
		check(attacks[0].contacts.size() == 1 and attacks[0].contacts[0].second.id == 11, "nested result identities preserved")
		check(attacks[0].equipment_contacts_complete, "coverage preserved")
		check(attacks[0].wounds_complete and attacks[0].wounds.size() == 1, "causal injury collection survives")
		if attacks[0].wounds.size() == 1:
			var injury: Dictionary = attacks[0].wounds[0]
			check(injury.wound_id == 12 and injury.victim_id == 2 and injury.severed_part, "exact wound identity and severing preserved")
			check(injury.parts_complete and injury.parts.size() == 1, "part coverage survives")
			if injury.parts.size() == 1:
				check(injury.parts[0].body_part_token == "HEAD" and injury.parts[0].damage_flags == 4, "anatomy and semantic damage survive")
	check(world.resolved_attack_events(1).is_empty() and world.resolved_attack_events(0).size() == 1, "attack queries are nondestructive")
	check(world.resolved_attack_stats().available, "attack source availability preserved")
	var projectile_events: Array = world.projectile_combat_events(0)
	check(projectile_events.size() == 1 and world.projectile_combat_stats().available, "source projectile phase survives adapter")
	if projectile_events.size() == 1:
		check(projectile_events[0].kind == 1 and projectile_events[0].launcher == 2 and projectile_events[0].projectile_id == 7, "projectile identity and phase preserved")
		check(projectile_events[0].ammunition.material_flags == 4 and projectile_events[0].ammunition.material_flags_known, "native material facts survive")
	check(world.projectile_combat_events(1).is_empty() and world.projectile_combat_events(0).size() == 1, "projectile phase queries are nondestructive")
	if attacks.size() == 1:
		check(attacks[0].outcome == 2 and attacks[0].outcome_complete and attacks[0].weapon_context_complete, "native outcome coverage survives")
	world.queue_free()
	await process_frame
	print("EFFECT_EVENTS_ADAPTER_PASS" if failures == 0 else "EFFECT_EVENTS_ADAPTER_FAIL")
	quit(0 if failures == 0 else 1)
