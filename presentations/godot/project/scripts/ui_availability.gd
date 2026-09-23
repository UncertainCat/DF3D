extends RefCounted
# Product entry points only. Retired implementations are absent from runtime.
# Promote one surface after semantic actions and local navigation are accepted.
# Unknown destinations fail closed; do not add native-screen fallbacks.
const AVAILABLE = [
	"Dig", "Chop trees", "Gather plants", "Smooth", "Remove", "Inspect", "Inspect buildings",
]

# The same registry gates routes and constructs only accepted implementations.
const PANEL_ROUTES = {"Build / construction":"construction", "Stockpiles / zones":"areas", "Residents":"readouts", "Work Details":"readouts", "Work orders":"readouts"}
const PANEL_SCRIPTS = {"construction":"res://scripts/construction.gd", "areas":"res://scripts/areas.gd", "readouts":"res://scripts/read_only_info.gd", "inspector":"res://scripts/context_inspector.gd"}

const READ_ONLY = ["Residents", "Work Details", "Work orders"]
const READ_LAUNCHERS = {"Citizens":"Residents", "Labor":"Work Details", "Work Details":"Work Details", "Work orders":"Work orders"}
# Keep the user's staged editor rollout: semantic routes remain testable, but
# building/area buttons are not promoted into the ordinary toolbar yet.
const HIDDEN_LAUNCHERS = ["Build / construction", "Stockpiles / zones"]

static func allows_launcher(destination: String) -> bool:
	return allows(destination) and destination not in HIDDEN_LAUNCHERS

static func allows(destination: String) -> bool:
	return destination in AVAILABLE or PANEL_ROUTES.has(destination) or READ_LAUNCHERS.has(destination)
