extends RefCounted
# Pure, engine-independent-of-scene selection and command bookkeeping.

static func rectangle(a: Vector2i, b: Vector2i, map: Vector2i) -> Rect2i:
	if map.x <= 0 or map.y <= 0:
		return Rect2i()
	var lo := Vector2i(clampi(mini(a.x, b.x), 0, map.x - 1), clampi(mini(a.y, b.y), 0, map.y - 1))
	var hi := Vector2i(clampi(maxi(a.x, b.x), 0, map.x - 1), clampi(maxi(a.y, b.y), 0, map.y - 1))
	return Rect2i(lo, hi - lo + Vector2i.ONE)

static func project_tile(origin: Vector3, direction: Vector3, z: int, size: Vector3, height: float) -> Vector3i:
	var invalid := Vector3i(-1, -1, -1)
	if z < 0 or z >= int(size.y) or absf(direction.y) < 0.00001:
		return invalid
	var distance := (z + height - origin.y) / direction.y
	if distance < 0.0:
		return invalid
	var point := origin + direction * distance
	if point.x < 0 or point.z < 0 or point.x >= size.x or point.z >= size.z:
		return invalid
	return Vector3i(floori(point.x), floori(point.z), z)

# Pick only visible pieces on the active level; depth then id makes overlap
# deterministic. Bounds are projected by the presentation, not game semantics.
static func choose_item(candidates: Array, screen: Vector2, z: int) -> Dictionary:
	var best: Dictionary = {}
	for candidate in candidates:
		if not candidate.visible or candidate.tile.z != z or not candidate.bounds.has_point(screen):
			continue
		if best.is_empty() or candidate.depth < best.depth or (candidate.depth == best.depth and candidate.id < best.id):
			best = candidate
	return best

# No optimistic flag mutation: results alone retire outstanding submissions.
var pending: Dictionary = {}
var _sent_at: Dictionary = {}
const RECEIPT_TIMEOUT_MS := 30000
var history: Array[String] = []

func submitted(seq: int, description: String, now_ms := -1) -> void:
	if seq > 0:
		pending[seq] = description
		_sent_at[seq] = Time.get_ticks_msec() if now_ms < 0 else now_ms
		note("Order sent: %s" % description)

func expire(now_ms: int) -> void:
	for seq in _sent_at.keys():
		if now_ms - int(_sent_at[seq]) < RECEIPT_TIMEOUT_MS: continue
		var description: String = pending.get(seq, "Command")
		pending.erase(seq)
		_sent_at.erase(seq)
		note("No confirmation for %s. Check the map before retrying." % description)

func receive(results: Array) -> Array[int]:
	var outcomes: Array[int] = []
	for result in results:
		var seq := int(result.seq)
		if not pending.has(seq):
			continue # another consumer's command, or a repeated result
		var description: String = pending[seq]
		pending.erase(seq)
		_sent_at.erase(seq)
		outcomes.append(int(result.status))
		var outcome := "Accepted" if int(result.status) == 0 else ("Rejected" if int(result.status) == 1 else "Unknown command")
		note("%s #%d (%s): %s" % [outcome, seq, description, str(result.message)])
	return outcomes

func note(message: String) -> void:
	history.push_front(message)
	if history.size() > 3:
		history.resize(3)
