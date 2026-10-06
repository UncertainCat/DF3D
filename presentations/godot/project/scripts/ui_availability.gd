extends RefCounted
# Product entry points only. Retired implementations are absent from runtime.
# Promote one surface after semantic actions and local navigation are accepted.
# Unknown destinations fail closed; do not add native-screen fallbacks.
const AVAILABLE = [
	"Dig", "Chop trees", "Gather plants", "Smooth", "Remove", "Inspect", "Inspect buildings",
]

# The same registry gates routes and constructs known implementations. Staged
# routes below remain testable without promoting their unfinished launchers.
const PANEL_ROUTES = {"Build / construction":"construction", "Stockpiles / zones":"areas", "Stockpiles":"areas", "Zones":"areas", "Residents":"readouts", "Work Details":"readouts", "Work orders":"readouts", "Reports":"reports"}
const PANEL_SCRIPTS = {"construction":"res://scripts/construction.gd", "areas":"res://scripts/areas.gd", "readouts":"res://scripts/read_only_info.gd", "inspector":"res://scripts/context_inspector.gd", "reports":"res://scripts/reports_panel.gd", "alerts":"res://scripts/alert_popup_panel.gd"}

# Tile facts currently carry enum/token identifiers, not native hover copy.
# Keep the generated-description prototype out of the product until native
# mapping/semantic description and rendered parity have been accepted.
const TILE_HOVER_AVAILABLE = false

const READ_ONLY = ["Residents", "Work Details", "Work orders"]
const READ_LAUNCHERS = {"Citizens":"Residents", "Labor":"Work Details", "Work Details":"Work Details", "Work orders":"Work orders"}
# Reports/alerts and construction are exposed for RC2. Area editors remain staged.
const HIDDEN_LAUNCHERS = ["Stockpiles / zones", "Stockpiles", "Zones"]

static func allows_launcher(destination: String) -> bool:
	return allows(destination) and destination not in HIDDEN_LAUNCHERS

static func allows(destination: String) -> bool:
	return destination in AVAILABLE or PANEL_ROUTES.has(destination) or READ_LAUNCHERS.has(destination)
