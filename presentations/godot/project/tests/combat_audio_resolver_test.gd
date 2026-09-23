extends SceneTree
const Resolver = preload("res://scripts/combat_audio_resolver.gd")
var failures := 0
func check(ok: bool, message: String):
	if not ok: failures += 1; push_error(message)
func _initialize():
	var weapon := {"id":10,"material_flags_known":true,"material_flags":0,"melee_skill":"SWORD"}
	var attack := {"outcome_complete":true,"weapon_context_complete":true,"outcome":2,"weapon":weapon}
	for flags in [0, 1, 2, 4, 7]:
		weapon.material_flags = flags
		var category: String = {0:"wood",1:"glass",2:"metal",4:"bone",7:"glass"}[flags]
		for outcome in [1,2,3,4,5]:
			attack.outcome = outcome
			var cue: String = {1:"combat/melee/%s/swing",2:"combat/melee/%s/hit",3:"combat/block/%s/block",4:"combat/parry/%s/success",5:"combat/parry/%s/fail"}[outcome] % category
			check(Resolver.resolve(attack).get("cue", "") == cue, "Outcome and material select " + cue)
	weapon.melee_skill = "WHIP"
	attack.outcome = 2
	check(Resolver.resolve(attack).category == "whip", "Whip skill precedes material")
	attack.outcome = 4
	check(Resolver.resolve(attack).category == "glass", "Parry uses actual material, no whip override")
	attack.weapon = {}; attack.outcome = 2
	check(Resolver.resolve(attack).cue == "combat/melee/flesh/hit", "Confirmed unarmed context is flesh")
	attack.weapon_context_complete = false
	check(Resolver.resolve(attack).is_empty(), "Missing item lookup cannot pretend to be unarmed")
	attack.weapon_context_complete = true; attack.outcome = 0
	attack.wounds = [{"severed_part":true}]
	check(Resolver.resolve(attack).is_empty(), "Injury cannot manufacture an outcome")
	attack.outcome = 6
	check(Resolver.resolve(attack).cue == "combat/wrestle/wrestle", "Explicit wrestling outcome")
	attack.outcome_complete = false
	check(Resolver.resolve(attack).is_empty(), "Incomplete outcome remains silent")
	for launcher in [1,2,3]:
		for flags in [0,1,2,4,7]:
			var item := {"material_flags_known":true,"material_flags":flags}
			var category := "metal" if flags & 2 else "bone" if flags & 4 else "wood"
			for kind in [1,2,3,4]:
				var event := {"launcher":launcher,"kind":kind,"context_complete":true,"weapon":item,"ammunition":item}
				var result: Dictionary = Resolver.resolve_projectile(event)
				check(result.get("category", "") == category, "Projectile material precedence")
				var family: String = {1:"bow",2:"crossbow",3:"ballista"}[launcher]
				var expected := "combat/fire-projectile/%s/%s/fire-projectile" % [family,category]
				if kind != 1:
					family = "ballista" if launcher == 3 else "bow-crossbow"
					expected = "combat/hit-projectile/%s/%s/%s/hit-projectile" % [family,{2:"flesh",3:"armor",4:"ground"}[kind],category]
				check(result.get("cue", "") == expected, "Projectile phase selects " + expected)
				event.context_complete = false
				check(Resolver.resolve_projectile(event).is_empty(), "Incomplete projectile context")
	check(Resolver.resolve_projectile({"context_complete":true,"launcher":0,"kind":1}).is_empty(), "Unknown launchers stay silent")
	print("COMBAT_AUDIO_RESOLVER_TEST_PASS" if failures == 0 else "COMBAT_AUDIO_RESOLVER_TEST_FAIL")
	quit(0 if failures == 0 else 1)
