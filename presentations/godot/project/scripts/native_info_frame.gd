extends RefCounted
# Native information hierarchy used to resolve launcher destinations.
const MAIN = ["Creatures", "Tasks", "Places", "Labor", "Work orders", "Nobles and administrators", "Objects", "Justice"]
const SUBTABS = {
	"Creatures": ["Residents", "Pets/Livestock", "Other", "Dead/Missing"],
	"Labor": ["Work Details", "Standing orders", "Kitchen", "Stone use"],
	"Places": ["Zones", "Locations", "Stockpiles", "Workshops", "Farm plots", "Siege engines"],
	"Objects": ["Artifacts", "Symbols", "Named objects", "Written content"],
	"Justice": ["Open cases", "Closed cases", "Cold cases", "Fortress guard", "Convicts", "Intelligence"]}

static func destination(caption: String) -> String:
	return str(SUBTABS[caption][0]) if SUBTABS.has(caption) else caption
