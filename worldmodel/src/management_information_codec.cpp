#include "management_codecs.h"

namespace wm::detail::management {
namespace m = df3d::mirror;

SelectionState decodeSelection(const m::SelectionState* a) {
  SelectionState out;
  if (!a)
    return out;
  auto& n = out;
  n.open = a->open();
  n.receipt = a->receipt();
  n.kind = SelectionKind(a->kind());
  n.id = a->id();
  if (a->tile()) {
    n.x = a->tile()->x();
    n.y = a->tile()->y();
    n.z = a->tile()->z();
  }
  n.title = a->title()->str();
  n.subtitle = a->subtitle()->str();
  n.job = a->job()->str();
  n.description = a->description()->str();
  n.weight = a->weight();
  n.value = a->value();
  n.passable = a->passable();
  n.isDoor = a->is_door();
  n.complete = a->complete();
  auto identity = [](const m::SelectionIdentity* e) {
    return SelectionIdentity{SelectionKind(e->kind()), e->id(), e->name()->str()};
  };
  for (const auto* e : *a->alternatives())
    n.alternatives.push_back(identity(e));
  if (a->container())
    n.container = identity(a->container());
  for (const auto* e : *a->items())
    n.items.push_back({e->id(), e->name()->str()});
  for (const auto* e : *a->overview())
    n.overview.push_back({SelectionSection(e->section()), e->text()->str()});
  if (const auto* p = a->portrait()) {
    for (const auto* t : *p->tile_pages())
      n.portrait.tilePages.push_back(t->str());
    for (const auto* t : *p->palettes())
      n.portrait.palettes.push_back(t->str());
    for (const auto* l : *p->layers())
      n.portrait.layers.push_back({l->page(), l->tile_x(), l->tile_y(), l->cells_x(), l->cells_y(),
                                   l->palette(), l->palette_row(), l->palette_key_row(),
                                   l->offset_x(), l->offset_y()});
  }

  return out;
}

AlertState decodeAlert(const m::AlertState* a) {
  AlertState out;
  if (!a)
    return out;
  auto& n = out;
  n.view = AlertView(a->view());
  n.receipt = a->receipt();
  n.category = a->category();
  n.unitId = a->unit_id();
  n.unitCategory = a->unit_category();
  n.selectedTab = a->selected_tab();
  n.scroll = a->scroll();
  n.total = a->total();
  n.complete = a->complete();
  if (a->focus()) {
    n.focusX = a->focus()->x();
    n.focusY = a->focus()->y();
    n.focusZ = a->focus()->z();
  }
  for (const auto* e : *a->entries())
    n.entries.push_back(
        {e->text()->str(), e->report_id(), e->unit_id(), e->unit_category(), e->can_recenter()});
  for (const auto* t : *a->tabs())
    n.tabs.push_back(t->str());

  return out;
}

ReportState decodeReport(const m::ReportState* r) {
  ReportState out;
  if (!r)
    return out;
  auto& n = out;
  n.nextBeforeId = r->next_before_id();
  n.announcementsOnly = r->announcements_only();
  if (r->detail())
    n.detail = r->detail()->str();
  if (r->reports())
    for (const auto* v : *r->reports()) {
      ReportInfo p;
      p.id = v->id();
      p.category = v->category()->str();
      p.text = v->text()->str();
      p.year = v->year();
      p.yearTick = v->year_tick();
      p.repeatCount = v->repeat_count();
      p.continuation = v->continuation();
      p.textComplete = v->text_complete();
      p.x = v->x();
      p.y = v->y();
      p.z = v->z();
      p.x2 = v->x2();
      p.y2 = v->y2();
      p.z2 = v->z2();
      p.positionVisible = v->position_visible();
      p.position2Visible = v->position2_visible();
      n.reports.push_back(std::move(p));
    }

  return out;
}

flatbuffers::Offset<m::SelectionRequest> encodeSelection(flatbuffers::FlatBufferBuilder& b,
                                                         const SelectionRequest& value) {
  const auto& a = value;
  const m::TilePos tile(a.x, a.y, a.z);
  return m::CreateSelectionRequest(b, m::SelectionOperation(a.operation),
                                   a.operation == SelectionOperation::OpenTile ? &tile : nullptr,
                                   a.receipt, a.index);
}

flatbuffers::Offset<m::AlertRequest> encodeAlert(flatbuffers::FlatBufferBuilder& b,
                                                 const AlertRequest& value) {
  const auto& a = value;
  return m::CreateAlertRequest(b, m::AlertOperation(a.operation), a.category, a.receipt, a.entry,
                               a.tab, a.delta);
}

flatbuffers::Offset<m::ReportRequest> encodeReport(flatbuffers::FlatBufferBuilder& b,
                                                   const ReportRequest& value) {
  const auto& p = value;
  return m::CreateReportRequest(b, p.id, p.beforeId, b.CreateString(p.query), p.announcementsOnly);
}
}  // namespace wm::detail::management
