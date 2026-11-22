extends RefCounted
# Product entry points only. Retired implementations are absent from runtime.
# Promote one surface after semantic actions and local navigation are accepted.
# Unknown destinations fail closed; do not add native-screen fallbacks.
const AVAILABLE = [
	"Dig", "Chop trees", "Gather plants", "Smooth", "Remove", "Inspect", "Inspect buildings",
]

# The same registry gates routes and constructs known implementations. Staged
# routes below remain testable without promoting their unfinished launchers.
const PANEL_ROUTES = {"Build / construction":"construction", "Stockpiles / zones":"areas", "Stockpiles":"areas", "Zones":"areas", "Residents":"residents", "Work Details":"work_details", "Work orders":"workshop", "Reports":"reports"}
const PANEL_SCRIPTS = {"pressure_plate":"res://scripts/pressure_plate_panel.gd", "justice":"res://scripts/justice_panel.gd", "objects":"res://scripts/objects_panel.gd", "nobles":"res://scripts/nobles_panel.gd", "places":"res://scripts/places_panel.gd", "tasks":"res://scripts/tasks_panel.gd", "stocks":"res://scripts/stocks_panel.gd", "standing_orders":"res://scripts/standing_orders_panel.gd", "work_details":"res://scripts/work_details_panel.gd", "residents":"res://scripts/residents_panel.gd", "construction":"res://scripts/construction.gd", "areas":"res://scripts/areas.gd", "inspector":"res://scripts/context_inspector.gd", "reports":"res://scripts/reports_panel.gd", "alerts":"res://scripts/alert_popup_panel.gd", "farm":"res://scripts/farm_panel.gd", "chest":"res://scripts/chest_panel.gd", "furniture":"res://scripts/furniture_panel.gd", "door":"res://scripts/door_panel.gd", "pending_building":"res://scripts/pending_building_panel.gd", "workshop":"res://scripts/workshop_panel.gd", "lever":"res://scripts/lever_panel.gd"}

# Native ordered world-hover entries from independently owned bridge inputs.
const TILE_HOVER_AVAILABLE = true

const LAUNCHER_DESTINATIONS = {"Citizens":"Residents", "Labor":"Work Details", "Work Details":"Work Details"}
# Stockpiles and Zones use the verified native semantic workflows.
const HIDDEN_LAUNCHERS = ["Stockpiles / zones"]

static func allows_launcher(destination: String) -> bool:
	return allows(destination) and destination not in HIDDEN_LAUNCHERS

static func allows(destination: String) -> bool:
	return destination in AVAILABLE or PANEL_ROUTES.has(destination) or LAUNCHER_DESTINATIONS.has(destination)
