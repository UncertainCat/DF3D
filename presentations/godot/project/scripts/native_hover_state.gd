extends RefCounted
# Native203713/204012/204218. Presentation-owned clock and hover identity only.
# Call advance each frame. A shared HUD owner keeps the warm interval across controls.
const DELAY_MS := 500
const WARM_MS := 1000
var owner := 0
var key := ""
var warm := false
var started := 0
var last_visible := 0

func reset() -> void:
	owner=0;key="";warm=false;started=0;last_visible=0

func enter(new_owner: int, new_key: String, now: int) -> void:
	advance(now)
	if new_owner==0 or new_key.is_empty(): return
	if key.is_empty() and not warm: started=now
	owner=new_owner;key=new_key

func leave(previous_owner: int, now: int) -> void:
	if previous_owner!=owner: return
	advance(now)
	owner=0;key=""

func advance(now: int) -> String:
	if key.is_empty():
		if warm and now-last_visible>=WARM_MS: warm=false
		return ""
	if not warm and now-started>=DELAY_MS: warm=true
	if warm:
		last_visible=now
		return key
	return ""
