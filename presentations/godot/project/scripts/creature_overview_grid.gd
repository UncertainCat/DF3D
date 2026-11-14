extends GridContainer
# Native Overview uses complete interior-border cells, including junctions.
# The summaries occupy seven text rows each; border cells share their last row.
var borders: Dictionary={}
func configure(world) -> void:
	for token in ["N_S","W_E","N_S_W_E","N_W_E"]:
		borders[token]=world.ui_texture("INTERIOR_BORDER_"+token)
	resized.connect(queue_redraw)
func _draw() -> void:
	var columns:=floori(size.x/8)
	var middle:=columns/2
	for row in 28:
		var separator:=row%7==6
		if separator:
			for column in columns:
				var token: String=("N_W_E" if row==27 else "N_S_W_E") if column==middle else "W_E"
				if borders.get(token)!=null:draw_texture(borders[token],Vector2(column*8,6+row*12))
		elif borders.get("N_S")!=null:draw_texture(borders.N_S,Vector2(middle*8,6+row*12))
