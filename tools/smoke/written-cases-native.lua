-- Restore every controlled input before returning, including on capture failure.
local unit,id,capture,baseline=...
local content=assert(df.written_content.find(id))
local original={title=content.title,author=content.author,type=content.type,poetic_form=content.poetic_form}
local function restore()
 content.title=original.title;content.author=original.author;content.type=original.type;content.poetic_form=original.poetic_form
end
local ok,err=xpcall(function()
 assert(original.title~='' and original.author>=0,'Need titled work with native author')
 for _,variant in ipairs{'untitled','no-author','missing-author','selected-author'}do
  restore()
  if variant=='untitled'then content.title=''
  elseif variant=='no-author'then content.author=-1
  elseif variant=='missing-author'then
   content.author=2147483647;assert(not df.historical_figure.find(content.author))
  else
   assert(unit.hist_figure_id>=0 and unit.hist_figure_id~=original.author)
   content.author=unit.hist_figure_id
  end
  assert(capture(variant)~=baseline,'Written variant did not change native text: '..variant)
 end
 for kind=0,25 do
  restore();content.type=kind;content.poetic_form=-1
  local text=capture('type-'..kind..'-missing-form')
  if kind~=original.type then assert(text~=baseline,'Written type did not change native text')end
 end
end,debug.traceback)
restore();assert(ok,err)
