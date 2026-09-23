extends RefCounted
# Native creature-sheet presentation primitives, sourced from installed UI art.
# Only created when displayed data or the selected local tab changes.
static func row(parent: Node, world, height := 36.0) -> HBoxContainer:
 var panel := PanelContainer.new()
 panel.custom_minimum_size.y=height
 panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 var style := StyleBoxTexture.new()
 style.texture=world.ui_texture("BUTTON_RECTANGLE_DARK")
 for side in [SIDE_LEFT,SIDE_RIGHT]:
  style.set_texture_margin(side,8);style.set_content_margin(side,8)
 for side in [SIDE_TOP,SIDE_BOTTOM]:
  style.set_texture_margin(side,12);style.set_content_margin(side,2)
 style.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
 panel.add_theme_stylebox_override("panel",style)
 parent.add_child(panel)
 var contents := HBoxContainer.new()
 contents.add_theme_constant_override("separation",16)
 panel.add_child(contents)
 return contents

static func icon(parent: Node, texture: Texture2D, size := Vector2(32,32)):
 if texture==null: return
 var view := TextureRect.new()
 view.texture=texture
 view.custom_minimum_size=size
 view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 view.mouse_filter=Control.MOUSE_FILTER_IGNORE
 parent.add_child(view)

static func scrollbar(scroll: ScrollContainer, world):
 var bar := scroll.get_v_scroll_bar()
 var source: Texture2D=world.ui_texture("SCROLLBAR")
 if source==null: return
 var track := StyleBoxTexture.new()
 track.texture=source
 track.set_texture_margin(SIDE_TOP,12);track.set_texture_margin(SIDE_BOTTOM,12)
 track.set_content_margin(SIDE_LEFT,8);track.set_content_margin(SIDE_RIGHT,8)
 bar.add_theme_stylebox_override("scroll",track)
 var grip_image := Image.create(16,36,false,Image.FORMAT_RGBA8)
 grip_image.fill(Color.TRANSPARENT)
 var center := Image.create(16,12,false,Image.FORMAT_RGBA8)
 center.fill(Color.TRANSPARENT)
 for row_index in 3:
  for i in 2:
   var part: Texture2D=world.ui_texture(["SCROLLBAR_TOP_SCROLLER","SCROLLBAR_CENTER_SCROLLER","SCROLLBAR_BOTTOM_SCROLLER"][row_index],i)
   if part==null: continue
   var pixels := part.get_image()
   grip_image.blit_rect(pixels,Rect2i(0,0,8,12),Vector2i(i*8,row_index*12))
   if row_index==1: center.blit_rect(pixels,Rect2i(0,0,8,12),Vector2i(i*8,0))
 # Stretch only the rails. The diamond stays twelve pixels high.
 for y in range(12,24):
  for x in 16: grip_image.set_pixel(x,y,center.get_pixel(x,0))
 var grip := StyleBoxTexture.new()
 grip.texture=ImageTexture.create_from_image(grip_image)
 grip.set_texture_margin(SIDE_TOP,12);grip.set_texture_margin(SIDE_BOTTOM,12)
 grip.set_content_margin(SIDE_LEFT,8);grip.set_content_margin(SIDE_RIGHT,8)
 grip.set_content_margin(SIDE_TOP,6);grip.set_content_margin(SIDE_BOTTOM,6)
 for state in ["grabber","grabber_highlight","grabber_pressed"]: bar.add_theme_stylebox_override(state,grip)
 var empty := Image.create(1,1,false,Image.FORMAT_RGBA8)
 empty.fill(Color.TRANSPARENT)
 for state in ["increment","increment_highlight","increment_pressed","decrement","decrement_highlight","decrement_pressed"]:
  bar.add_theme_icon_override(state,ImageTexture.create_from_image(empty))
 var marker := TextureRect.new()
 marker.texture=ImageTexture.create_from_image(center)
 marker.mouse_filter=Control.MOUSE_FILTER_IGNORE
 bar.add_child(marker)
 var place := func():
  var extent := maxf(bar.max_value-bar.min_value,1)
  var track_height := maxf(bar.size.y-2,0)
  var thumb := clampf(track_height*bar.page/extent,12,track_height)
  var fraction := clampf((bar.value-bar.min_value)/maxf(extent-bar.page,1),0,1)
  marker.position=Vector2(0,roundf(1+(track_height-thumb)*fraction+thumb*.5-6))
 bar.changed.connect(place)
 bar.resized.connect(place)
 bar.value_changed.connect(func(_value): place.call())
 place.call_deferred()
