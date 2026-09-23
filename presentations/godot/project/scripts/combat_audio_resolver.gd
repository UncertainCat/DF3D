extends RefCounted
# Native outcome semantics select one complete cue per resolved occurrence.
# Material flags are actual item material facts, not raw-name heuristics.
enum Outcome { UNKNOWN, MISS, HIT, BLOCKED, PARRY_SUCCESS, PARRY_FAILED, WRESTLE }

static func material_category(item: Dictionary, allow_whip: bool = true) -> String:
	if allow_whip and item.get("melee_skill", "") == "WHIP": return "whip"
	if not item.get("material_flags_known", false): return ""
	var flags: int = item.get("material_flags", 0)
	if flags & 1: return "glass"
	if flags & 2: return "metal"
	if flags & 4: return "bone"
	return "wood" # Verified native fallback, including other known materials.

static func resolve(attack: Dictionary) -> Dictionary:
	if not attack.get("outcome_complete", false): return {}
	var outcome: int = attack.get("outcome", Outcome.UNKNOWN)
	if outcome == Outcome.WRESTLE:
		return {"cue":"combat/wrestle/wrestle", "category":"flesh", "outcome":outcome}
	if outcome not in [Outcome.MISS, Outcome.HIT, Outcome.BLOCKED, Outcome.PARRY_SUCCESS, Outcome.PARRY_FAILED]: return {}
	if not attack.get("weapon_context_complete", false): return {}
	var weapon: Dictionary = attack.get("weapon", {})
	var parry := outcome == Outcome.PARRY_SUCCESS or outcome == Outcome.PARRY_FAILED
	var category := "flesh" if weapon.is_empty() else material_category(weapon, not parry)
	if category.is_empty() or (parry and category == "flesh"): return {}
	var cue: String
	match outcome:
		Outcome.MISS: cue = "combat/melee/%s/swing" % category
		Outcome.HIT: cue = "combat/melee/%s/hit" % category
		Outcome.BLOCKED: cue = "combat/block/%s/block" % category
		Outcome.PARRY_SUCCESS: cue = "combat/parry/%s/success" % category
		Outcome.PARRY_FAILED: cue = "combat/parry/%s/fail" % category
	return {"cue":cue, "category":category, "outcome":outcome}

# Projectile phases are separate source occurrences: release, then each resolved
# collision. They never borrow nearby melee events or observed trajectory starts.
static func resolve_projectile(event: Dictionary) -> Dictionary:
	if not event.get("context_complete", false): return {}
	var kind: int = event.get("kind", 0)
	var launcher: int = event.get("launcher", 0)
	if launcher not in [1, 2, 3] or kind not in [1, 2, 3, 4]: return {}
	var item: Dictionary = event.get("weapon", {}) if kind == 1 else event.get("ammunition", {})
	if not item.get("material_flags_known", false): return {}
	var flags: int = item.get("material_flags", 0)
	var category := "metal" if flags & 2 else "bone" if flags & 4 else "wood"
	var cue: String
	if kind == 1:
		var family: String = {1:"bow", 2:"crossbow", 3:"ballista"}[launcher]
		cue = "combat/fire-projectile/%s/%s/fire-projectile" % [family, category]
	else:
		var family := "ballista" if launcher == 3 else "bow-crossbow"
		var surface: String = {2:"flesh", 3:"armor", 4:"ground"}[kind]
		cue = "combat/hit-projectile/%s/%s/%s/hit-projectile" % [family, surface, category]
	return {"cue":cue, "category":category, "kind":kind}
