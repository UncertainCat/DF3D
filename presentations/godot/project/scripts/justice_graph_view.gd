extends RefCounted
# Native4769d0 graph rows and d1650 hierarchy geometry. Simulation membership,
# ordering, labels and relationships arrive from DF; this owns only layout/input.
var view
func configure(owner) -> void:view=owner
func model():return view.state.intelligence
func capacity() -> int:return maxi(0,int((view.size.y-view.list_top()-48)/12))
func rows() -> Array:
	var m=model()
	if m.mode==0 or m.graph.phase!=m.graph.Phase.Ready:return []
	return m.graph.graph[["actors","organizations","plots"][m.mode-1]]
func cells(index: int) -> int:
	var m=model();var data:=rows()
	if index!=m.graph_selected:return 5
	if m.mode==1:return maxi(3,data[index].lines.size())+2
	if m.mode==2 and data[index].node_count>0:return maxi(5,capacity()-7)
	return 5
func total() -> int:
	var value:=0
	for index in rows().size():value+=cells(index)
	return value+(2 if model().mode==1 and not rows().is_empty() else 0)
func seek(value: int) -> void:
	model().graph_scroll=clampi(value,0,maxi(0,total()-capacity()));model().changed.emit()
func rect(index: int) -> Rect2:
	var y: int=view.list_top()+24-model().graph_scroll*12
	for before in index:y+=cells(before)*12
	return Rect2(16,y,view.size.x-32-(16 if total()>capacity() else 0),cells(index)*12)
func clipped(value: String,columns: int,ellipsis:=false) -> String:
	if value.length()<=columns:return value
	return value.left(maxi(0,columns-3))+"..." if ellipsis else value.left(maxi(0,columns))
func positions(org: Dictionary,box: Rect2) -> Dictionary:
	var nodes: Array=model().graph.graph.nodes
	var descendants: Dictionary={};var xs: Dictionary={}
	for i in range(org.first_node+org.node_count-1,org.first_node-1,-1):
		descendants[i]=0;xs[i]=0
		for child in range(i+1,org.first_node+org.node_count):
			if nodes[child].parent==i:descendants[i]+=descendants[child]+1
	for i in range(org.first_node,org.first_node+org.node_count):
		if descendants[i]==0:continue
		var start: int=xs[i]+int((5-5*descendants[i])/2.0)
		for child in range(i,org.first_node+org.node_count):
			if nodes[child].tier>nodes[i].tier+1:break
			if nodes[child].parent==i:
				xs[child]=start+int(descendants[child]*5/2.0);start+=descendants[child]*5+5
	var output: Dictionary={};var center:=int((box.position.x*2+box.size.x-8)/16)*8-16
	for i in range(org.first_node,org.first_node+org.node_count):output[i]=Rect2(center+xs[i]*8,box.position.y+nodes[i].tier*72,40,60)
	return output
func click(point: Vector2) -> void:
	var m=model();var data:=rows()
	for i in data.size():
		var box:=rect(i)
		if not box.has_point(point):continue
		if m.mode==2 and i==m.graph_selected:
			var nodes:=positions(data[i],box)
			for index in nodes:
				if nodes[index].has_point(point):m.selected_node=index;m.changed.emit();return
		m.select_graph_row(i);return
func draw() -> void:
	var m=model();var data:=rows();var all: Dictionary=m.graph.graph
	for i in data.size():
		var box:=rect(i)
		if box.end.y<view.list_top()+24 or box.position.y>view.size.y-24:continue
		var selected: bool=i==m.graph_selected;var row: Dictionary=data[i]
		view.patch("BUTTON_RECTANGLE",Vector2i(box.position/Vector2(8,12)),int(box.size.x/8),cells(i))
		view.text(clipped(row.name,int((box.size.x-32)/8),true),box.position+Vector2(16,12),14 if selected else 6)
		var count:="%d/%d"%[i+1,data.size()]
		view.text(count,Vector2(box.end.x-(count.length()+3)*8,box.position.y+12),12 if selected else 4)
		if m.mode==1:
			var offset:=24 if row.lines.size()==1 else 12
			for line in mini(row.lines.size(),maxi(3,row.lines.size()) if selected else 3):
				view.text(clipped(row.lines[line],m.columns),box.position+Vector2(16,offset+(line+1)*12),15 if selected else 7)
		elif m.mode==3:
			if row.organization>=0:view.text(clipped("Org: "+all.organizations[row.organization].name,m.columns),box.position+Vector2(16,24),11 if selected else 3)
		elif selected:draw_organization(row,box)
func draw_organization(org: Dictionary,box: Rect2) -> void:
	var m=model();var all: Dictionary=m.graph.graph;var positions_by_node:=positions(org,box)
	var selected: int=m.selected_node if positions_by_node.has(m.selected_node) else org.first_node
	if org.node_count==0:return
	var actor: int=all.nodes[selected].actor
	if actor>=0:view.text(clipped("Selected actor: "+all.actors[actor].name,m.columns),box.position+Vector2(16,24))
	for index in positions_by_node:
		var node: Dictionary=all.nodes[index];var node_box: Rect2=positions_by_node[index]
		if positions_by_node.has(node.parent):
			var parent_box: Rect2=positions_by_node[node.parent]
			var from:=Vector2i((parent_box.position+Vector2(16,24))/Vector2(8,12));var to:=Vector2i((node_box.position+Vector2(16,24))/Vector2(8,12))
			draw_edge(from,to,10 if index==selected or node.parent==selected else 2)
	for index in positions_by_node:
		var node: Dictionary=all.nodes[index];var node_box: Rect2=positions_by_node[index]
		view.patch("GRID_CELL_ACTIVE",Vector2i(node_box.position/Vector2(8,12)),5,5)
		view.text(node.label,node_box.position+Vector2(0,12),node.foreground+node.bright*8)
		view.text(node.name,node_box.position+Vector2(8,36))
		view.text(node.status,node_box.position+Vector2(8,48))
func draw_edge(from: Vector2i,to: Vector2i,color: int) -> void:
	# The native chart rasterizes straight grid edges, then chooses text glyphs
	# from neighboring points; nodes are drawn over the edge interiors.
	var points: Array[Vector2i]=[];var at:=from;var dx:=absi(to.x-from.x);var dy:=-absi(to.y-from.y)
	var sx:=1 if from.x<to.x else -1;var sy:=1 if from.y<to.y else -1;var error:=dx+dy
	while true:
		points.append(at)
		if at==to:break
		var twice:=2*error
		if twice>=dy:error+=dy;at.x+=sx
		if twice<=dx:error+=dx;at.y+=sy
	for i in range(1,points.size()-1):
		var before:=points[i-1];var here:=points[i];var after:=points[i+1]
		var glyph:="|" if before.x==here.x or after.x==here.x else "-" if before.y==here.y or after.y==here.y else "\\" if (after.x-before.x)*(after.y-before.y)>0 else "/"
		view.text(glyph,Vector2(here.x*8,(here.y+1)*12),color)
