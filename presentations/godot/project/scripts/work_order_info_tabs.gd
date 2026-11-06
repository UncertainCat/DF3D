extends RefCounted
# Native information-tab geometry shared by the global list and Conditions.
static func rows(wide: bool) -> Array:
	return [["Creatures","Tasks","Places","Labor","Work orders","Nobles and administrators","Objects","Justice"]] if wide else [["Nobles and administrators","Objects","Justice"],["Creatures","Tasks","Places","Labor","Work orders"]]
static func caption_at(point: Vector2,wide: bool) -> String:
	var groups:=rows(wide)
	for row in groups.size():
		var x:=8
		for caption in groups[row]:
			var width: int=(caption.length()+4)*8
			if Rect2(x,12+row*24,width,24).has_point(point):return caption
			x+=width
	return ""
