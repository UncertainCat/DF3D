extends RefCounted

# Timing and random choice are presentation inputs; this never reads simulation
# state. The bridge supplies both verified alternatives and the native effect.
static func choose(description: Dictionary, time_ms: int, fire_choice: int) -> Array:
	var primary = description.get("color")
	var alternate = description.get("alternate")
	var effect := int(description.get("effect",-1))
	if not primary is Array or not alternate is Array or primary.size() != 3 or alternate.size() != 3 or effect not in range(4): return []
	for color in [primary,alternate]:
		for index in 3:
			if not color[index] is int or int(color[index]) < 0 or int(color[index]) > (1 if index == 2 else 7): return []
	if effect == 0 and primary != alternate: return []
	var phase := posmod(time_ms,1000)
	var use_alternate := (effect == 1 and phase < 333) or (effect == 2 and phase < 500) or (effect == 3 and fire_choice != 0)
	return alternate if use_alternate else primary
