-- Controlled formatter inputs in the protected paused, unsaved diagnostic only.
local unit,id,capture,baseline=...
local form=assert(df.poetic_form.find(id))
local original={author=form.original_author,entity=form.originating_entity,subject=form.subject,target=form.subject_target.Histfig.subject_histfig,
 preferred=form.preferred_perspective,perspectives={}}
for _,value in ipairs(form.perspectives)do original.perspectives[#original.perspectives+1]=value end
local persona=df.poetic_form_perspective:new()
local function restore()
 form.original_author=original.author;form.originating_entity=original.entity;form.subject=original.subject
 form.subject_target.Histfig.subject_histfig=original.target;form.preferred_perspective=original.preferred
 form.perspectives:resize(0);for _,value in ipairs(original.perspectives)do form.perspectives:insert('#',value)end
end
local ok,err=xpcall(function()
 assert(unit.hist_figure_id>=0 and unit.race>=0 and unit.caste>=0)
 for _,variant in ipairs{'named-author','figure-subject','figure-persona','animal-persona'}do
  restore()
  if variant=='named-author'then form.original_author=unit.hist_figure_id;form.originating_entity=-1
  elseif variant=='figure-subject'then form.subject=df.poetic_form_subject.Histfig;form.subject_target.Histfig.subject_histfig=unit.hist_figure_id
  else
   persona.type=variant=='figure-persona'and df.poetic_form_persona_type.Histfig or df.poetic_form_persona_type.Animal
   persona.subtype=variant=='figure-persona'and unit.hist_figure_id or unit.race;persona.subtype2=unit.caste
   form.perspectives:insert('#',persona);form.preferred_perspective=#form.perspectives-1
  end
  assert(capture(variant)~=baseline,'Controlled poetic variant did not change native text: '..variant)
 end
end,debug.traceback)
restore();df.delete(persona);assert(ok,err)
