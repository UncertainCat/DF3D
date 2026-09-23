extends RefCounted
# Resident instance invalidation accepts source dependencies only. Camera pose,
# projection, focus and lighting belong to shader/view state, never this object.
# Explicit style transitions may change the payload convention once.
enum Style { FLAT, BILLBOARD }

var style: Style
var session_generation: int
var top_z: int

func _init(next_style: Style = Style.FLAT, session: int = 0, top: int = 0):
	style = next_style
	session_generation = session
	top_z = top

func key() -> Array:
	return [style, session_generation, top_z]
