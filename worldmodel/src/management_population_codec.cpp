#include "management_codecs.h"

namespace wm::detail::management {
namespace m = df3d::mirror;

CreatureInfo decodeCreature(const m::CreatureState* c) {
  CreatureInfo out;
  if (!c)
    return out;
  auto str = [](const flatbuffers::String* v) { return v ? v->str() : std::string(); };
  out.unitId = c->unit_id();
  out.capturedTick = c->captured_tick();
  out.name = str(c->name());
  out.species = str(c->species());
  out.profession = str(c->profession());
  out.job = str(c->job());
  out.age = c->age();
  out.sex = c->sex();
  out.complete = c->complete();
  if (const auto* p = c->portrait()) {
    for (const auto* t : *p->tile_pages())
      out.portrait.tilePages.push_back(t->str());
    for (const auto* t : *p->palettes())
      out.portrait.palettes.push_back(t->str());
    for (const auto* l : *p->layers())
      out.portrait.layers.push_back({l->page(), l->tile_x(), l->tile_y(), l->cells_x(),
                                     l->cells_y(), l->palette(), l->palette_row(),
                                     l->palette_key_row(), l->offset_x(), l->offset_y()});
  }
  if (c->origin()) {
    out.x = c->origin()->x();
    out.y = c->origin()->y();
    out.z = c->origin()->z();
  }
  if (c->sections())
    for (const auto* v : *c->sections()) {
      CreatureSection section;
      section.kind = CreatureSectionKind(v->kind());
      section.available = v->available();
      section.truncated = v->truncated();
      section.reason = str(v->reason());
      if (v->records())
        for (const auto* r : *v->records()) {
          CreatureRecord row;
          row.id = r->id();
          row.relatedId = r->related_id();
          row.name = str(r->name());
          if (r->facts())
            for (const auto* f : *r->facts())
              row.facts.push_back({str(f->key()), str(f->text()), f->number(), f->has_number()});
          section.records.push_back(std::move(row));
        }
      out.sections.push_back(std::move(section));
    }

  return out;
}

CitizenState decodeCitizen(const m::CitizenState* c) {
  CitizenState out;
  if (!c)
    return out;
  auto& n = out;
  auto str = [](const flatbuffers::String* v) { return v ? v->str() : std::string(); };
  n.nextCursor = c->next_cursor();
  n.selectedUnit = c->selected_unit();
  n.selectedDetail = c->selected_detail();
  n.externalController = c->external_controller();
  n.recalcDone=c->recalc_done();n.recalcTotal=c->recalc_total();
  n.recalcError=str(c->recalc_error());n.detailListRevision=int64_t(c->detail_list_revision());
  n.detail = str(c->detail());
  if (c->citizens())
    for (const auto* v : *c->citizens()) {
      CitizenInfo u;
      u.revision=int64_t(v->revision());u.detailMember=v->detail_member();u.detailSkill=v->detail_skill();
      u.detailSkillRating=v->detail_skill_rating();u.detailSkillName=str(v->detail_skill_name());
      u.portraitState=v->portrait_state();u.rowError=str(v->row_error());
      u.professionColor = v->profession_color();
      u.professionId = v->profession_id();
      u.jobType = v->job_type();
      u.id = v->id();
      u.age = v->age();
      u.stress = v->stress();
      u.hasStress = v->has_stress();
      u.name = str(v->name());
      u.profession = str(v->profession());
      u.job = str(v->job());
      u.reason = str(v->reason());
      u.x = v->origin()->x();
      u.y = v->origin()->y();
      u.z = v->origin()->z();
      u.canFocus = v->can_focus();
      u.eligible = v->eligible();
      u.onlyAssignedJobs = v->only_assigned_jobs();
      u.socialActivity = v->social_activity();
      if (v->assigned_details())
        for (const auto* d : *v->assigned_details())
          u.assignedDetails.push_back({d->index(), d->icon(), str(d->name())});
      if (const auto* p = v->sheet_icon()) {
        for (const auto* t : *p->tile_pages())
          u.sheetIcon.tilePages.push_back(t->str());
        for (const auto* t : *p->palettes())
          u.sheetIcon.palettes.push_back(t->str());
        for (const auto* l : *p->layers())
          u.sheetIcon.layers.push_back({l->page(), l->tile_x(), l->tile_y(), l->cells_x(),
                                        l->cells_y(), l->palette(), l->palette_row(),
                                        l->palette_key_row(), l->offset_x(), l->offset_y()});
      }
      if (v->labors())
        u.labors.assign(v->labors()->begin(), v->labors()->end());
      if (v->offices())
        u.offices.assign(v->offices()->begin(), v->offices()->end());
      if (v->labor_names())
        for (const auto* name : *v->labor_names())
          u.laborNames.push_back(str(name));
      if (v->roles())
        for (const auto* r : *v->roles())
          u.roles.push_back({str(r->name()), r->required_office()});
      n.citizens.push_back(std::move(u));
    }
  if (c->details())
    for (const auto* v : *c->details()) {
      WorkDetailInfo d;
      d.icon=v->icon();d.rowError=str(v->row_error());
      d.index = v->index();
      d.revision = v->revision();
      d.name = str(v->name());
      d.reason = str(v->reason());
      d.mode = v->mode();
      d.noModify = v->no_modify();
      d.cannotBeEverybody = v->cannot_be_everybody();
      d.editable = v->editable();
      d.modeEditable = v->mode_editable();
      if (v->labors())
        d.labors.assign(v->labors()->begin(), v->labors()->end());
      if (v->labor_names())
        for (const auto* name : *v->labor_names())
          d.laborNames.push_back(str(name));
      if (v->assigned_units())
        d.assignedUnits.assign(v->assigned_units()->begin(), v->assigned_units()->end());
      n.details.push_back(std::move(d));
    }

  return out;
}

AppointmentsState decodeAppointments(const m::AppointmentsState* t) {
  AppointmentsState out;
  if (!t)
    return out;
  auto& n = out;
  n.open = t->open();
  n.choosing = t->choosing();
  n.receipt = t->receipt();
  n.detail = t->detail()->str();
  for (const auto* v : *t->roles()) {
    AppointmentRole r;
    r.entityId = v->entity_id();
    r.positionId = v->position_id();
    r.assignmentId = v->assignment_id();
    r.unitId = v->unit_id();
    r.name = v->name()->str();
    r.holder = v->holder()->str();
    r.office = v->office();
    r.bedroom = v->bedroom();
    r.dining = v->dining();
    r.tomb = v->tomb();
    r.boxes = v->boxes();
    r.cabinets = v->cabinets();
    r.racks = v->racks();
    r.stands = v->stands();
    r.actionable = v->actionable();
    r.reason = v->reason()->str();
    n.roles.push_back(std::move(r));
  }
  for (const auto* v : *t->candidates()) {
    AppointmentCandidate c;
    c.unitId = v->unit_id();
    c.name = v->name()->str();
    c.skill = v->skill()->str();
    c.selectable = v->selectable();
    c.reason = v->reason()->str();
    n.candidates.push_back(std::move(c));
  }

  return out;
}

flatbuffers::Offset<m::CitizenRequest> encodeCitizen(flatbuffers::FlatBufferBuilder& b,
                                                     const CitizenRequest& value) {
  const auto& c = value;
  return m::CreateCitizenRequest(b, c.unitId, c.detailIndex, c.expectedRevision, c.cursor,
                                 b.CreateString(c.query), c.member, c.mode,b.CreateString(c.name),b.CreateVector(c.labors),c.edit,c.onlyAssigned,c.expectedListRevision);
}

flatbuffers::Offset<m::AppointmentsRequest> encodeAppointments(flatbuffers::FlatBufferBuilder& b,
                                                               const AppointmentsRequest& value) {
  const auto& a = value;
  return m::CreateAppointmentsRequest(b, a.entityId, a.positionId, a.assignmentId, a.unitId,
                                      a.receipt);
}
}  // namespace wm::detail::management
