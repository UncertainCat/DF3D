extends RefCounted
# Native staff/selector captures224159 and020926 use the original INTERFACE_BITS
# BUTTON_PICTURE_BOX cells for unselected rows. The later DARK token names a
# different image. Select the original nine variants retained by the asset index.
var normal: Texture2D
var selected: Texture2D

func configure(world) -> void:
	selected=world.ui_texture("BUTTON_PICTURE_BOX_SELECTED")
	var image:=Image.create_empty(24,36,false,Image.FORMAT_RGBA8)
	for y in 3:
		for x in 3:
			var cell: Texture2D=world.ui_texture("BUTTON_PICTURE_BOX",y*3+x)
			if cell==null or cell.get_size()!=Vector2(8,12):normal=null;return
			image.blit_rect(cell.get_image(),Rect2i(0,0,8,12),Vector2i(x*8,y*12))
	normal=ImageTexture.create_from_image(image)

func texture(is_selected: bool) -> Texture2D:
	return selected if is_selected else normal
