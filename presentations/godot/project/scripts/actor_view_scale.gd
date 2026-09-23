extends RefCounted
# Transient view state, not a Truescale calibration or saved preference.
# Restrict to shrink-only so existing resident bounds/ceiling envelopes stay valid.
const WALK := 0.75
const WALK_EYE := 0.72 * WALK
static var current := 1.0

static func set_walk(enabled: bool) -> void:
	current = WALK if enabled else 1.0
	RenderingServer.global_shader_parameter_set("actor_view_scale", current)

static func effective(payload_scale: float, truescale: bool) -> float:
	return (payload_scale if truescale else 1.0) * current
