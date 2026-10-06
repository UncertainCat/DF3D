extends "res://scripts/area_location_scrollbar.gd"
# Reports protected062806 agrees with the shared native scrollbar formula/input.
var input_allowed:Callable
var wheel_enabled:=true
var use_standalone_sheet:=true
func _input(event:InputEvent) -> void:
 if input_allowed.is_valid() and not input_allowed.call():dragging=false;return
 if event is InputEventMouseMotion and hover_cell!=-1 and not get_global_rect().has_point(event.position):
  hover_cell=-1;queue_redraw()
 super._input(event)
func _gui_input(event:InputEvent) -> void:
 # A released drag can still route captured motion through this control. Do not
 # treat its outside-local coordinates as a hovered scrollbar cell.
 if event is InputEventMouseMotion and not Rect2(Vector2.ZERO,size).has_point(event.position):
  hover_cell=-1;queue_redraw();return
 if not wheel_enabled and event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:accept_event();return
 if input_allowed.is_valid() and not input_allowed.call():dragging=false;return
 super._gui_input(event)

func thumb() -> Vector2i:
 var grip:Vector2i=super.thumb()
 # Native popup113212 keeps an interior thumb short of the end until the
 # final row, symmetric with the shared formula's first-row endpoint handling.
 if not use_standalone_sheet and first>0 and first<count-page:
  var end_offset:int=int(size.y/12)-2-grip.y
  if end_offset>1:grip.x=mini(grip.x,end_offset)
 return grip

var native_sheet:Image
func configure(world) -> void:
 super.configure(world)
 native_sheet=Image.load_from_file(world.assets_root().path_join("data/art/scrollbar.png"))
func texture(token:String) -> Texture2D:
 if not use_standalone_sheet:return super.texture(token)
 if textures.has(token):return textures[token]
 if native_sheet==null:return null
 var rect:=Rect2i()
 var hover:=token.ends_with("_HOVER")
 var base:=token.trim_suffix("_HOVER")
 match base:
  "SCROLLBAR":rect=Rect2i(0,0,16,36)
  "SCROLLBAR_UP":rect=Rect2i(16,0,16,12)
  "SCROLLBAR_DOWN":rect=Rect2i(16,12,16,12)
  "SCROLLBAR_SMALL_SCROLLER":rect=Rect2i(32 if hover else 16,24,16,24)
  "SCROLLBAR_OFFCENTER_SCROLLER":rect=Rect2i(80,24 if hover else 0,16,24)
  "SCROLLBAR_TOP_SCROLLER":rect=Rect2i(64 if hover else 48,0,16,12)
  "SCROLLBAR_CENTER_SCROLLER":rect=Rect2i(64 if hover else 48,12,16,12)
  "SCROLLBAR_BLANK_SCROLLER":rect=Rect2i(64 if hover else 48,24,16,12)
  "SCROLLBAR_BOTTOM_SCROLLER":rect=Rect2i(64 if hover else 48,36,16,12)
  _:return null
 textures[token]=ImageTexture.create_from_image(native_sheet.get_region(rect))
 return textures[token]
