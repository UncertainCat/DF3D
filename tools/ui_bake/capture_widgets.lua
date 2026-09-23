-- Development-only, read-only export. Never invokes widget callbacks or input.
-- Raw observations stay under ignored build/, not in shipped panel definitions.
local path,mode=...
local templates=mode=='templates'
assert(type(path)=='string' and path~='','Output path required')
local count,limit=0,2048
local seen={}
local function is(name,w) return df[name] and df[name]:is_instance(w) end
local classes={'widget_text_truncated','widget_text_multiline','widget_text',
 'widget_character','widget_nineslice_horizontal','widget_nineslice',
 'widget_anchored_tile','widget_unit_portrait','widget_item_portrait',
 'widget_unit_name','widget_item_name','widget_tabs','widget_table',
 'widget_scroll_rows','widget_rows_container','widget_columns_container',
 'widget_container','widget'}
local function text(value) return dfhack.df2utf(value or '') end
local function walk(w,id,depth)
 if not w then return nil end
 if count>=limit or depth>32 then return {id=id,unsupported='capture_limit'} end
 if seen[w] then return {id=id,unsupported='shared_or_cyclic_widget'} end
 seen[w]=true;count=count+1
 local kind='unknown'
 for _,name in ipairs(classes)do if is(name,w) then kind=name;break end end
 local r={id=id,native_type=kind,name=text(w.name),children={},
  rect={w.rect.x1,w.rect.y1,w.rect.x2,w.rect.y2},
  anchors={w.anchor_left,w.anchor_top,w.anchor_right,w.anchor_bottom},
  offsets={w.offset_left,w.offset_top,w.offset_right,w.offset_bottom},
  minimum={w.min_w,w.min_h},flags=w.flag.whole,
  custom={feed=#w.custom_feed,logic=#w.custom_logic,render=#w.custom_render,activated=#w.custom_activated}}
 if is('widget_text',w) then r.text=text(w.str);r.foreground=w.fg;r.background=w.bg;r.bright=w.bright end
 if is('widget_tabs',w) then
  r.selected=w.cur_idx;r.tab_labels={}
  for _,label in ipairs(w.tab_labels)do r.tab_labels[#r.tab_labels+1]=text(label)end
 end
 if is('widget_scroll_rows',w) then r.scroll=w.scroll;r.num_visible=w.num_visible end
 if is('widget_container',w) then
  local children=dfhack.gui.getWidgetChildren(w)
  local ordinal=0
  for _,child in ipairs(children)do
   if templates and is('widget_scroll_rows',w) and ordinal>=1 then r.row_template=true;r.observed_row_count=#children;break end
   if count>=limit then r.truncated_children=true;break end
   local nested=nil
   if not templates or not is('widget_tabs',w) or ordinal==w.cur_idx then nested=walk(child,id..'/'..ordinal,depth+1) end
   if nested then r.children[#r.children+1]=nested end
   ordinal=ordinal+1
  end
 end
 return r
end
local game=df.global.game
assert(game,'DF game unavailable')
local w,h=dfhack.screen.getWindowSize()
local result={format_version=1,df_version=dfhack.getDFVersion(),
 coordinate_space='native_widget_rect_inclusive',viewport_cells={w,h},
 cell_pixels={df.global.gps.tile_pixel_x,df.global.gps.tile_pixel_y},
 focus=dfhack.gui.getFocusStrings(dfhack.gui.getCurViewscreen(true)),roots={},unsupported={}}
local info=game.main_interface.info
result.roots[1]=walk(info,'info',0)
-- The native Info wrapper does not attach its active page to children. Resolve
-- the explicitly selected page only; other embedded pages may be stale caches.
local mode=df.info_interface_mode_type[info.current_mode]
local page_name=type(mode)=='string' and mode:lower() or nil
if info.open and page_name then
 local ok,page=pcall(function()return info[page_name]end)
 if ok and page and is('widget',page) then result.roots[#result.roots+1]=walk(page,'info.'..page_name,0)
 else result.unsupported[#result.unsupported+1]={source_path='info.'..page_name,reason='Active page is not an exposed widget container'} end
end
result.info_open=info.open
result.unsupported[#result.unsupported+1]={source_path='view_sheets',reason='view_sheets_interfacest is not a widget tree; use observed reference definitions'}
result.widget_count=count
result.template_capture=templates
local file=assert(io.open(path,'w'));assert(file:write(require('json').encode(result)));assert(file:close())
print('WIDGET_CAPTURE_PASS count='..count..' info_open='..tostring(info.open))
