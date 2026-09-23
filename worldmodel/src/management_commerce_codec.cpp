#include "management_codecs.h"

namespace wm::detail::management {
namespace m = df3d::mirror;

StocksState decodeStocks(const m::StocksState* t) {
  StocksState out;
  if (!t)
    return out;
  auto& n = out;
  n.open = t->open();
  n.receipt = t->receipt();
  n.nextCursor = t->next_cursor();
  n.category = t->category();
  n.detail = t->detail()->str();
  for (const auto* v : *t->categories()) {
    StockCategory row;
    row.id = v->id();
    row.name = v->name()->str();
    row.available = {v->available()->amount(), uint8_t(v->available()->accuracy())};
    row.unavailable = {v->unavailable()->amount(), uint8_t(v->unavailable()->accuracy())};
    n.categories.push_back(std::move(row));
  }
  for (const auto* v : *t->items()) {
    StockItem row;
    row.id = v->id();
    row.category = v->category();
    row.description = v->description()->str();
    row.quantity = v->quantity();
    row.x = v->x();
    row.y = v->y();
    row.z = v->z();
    row.canFocus = v->can_focus();
    n.items.push_back(std::move(row));
  }

  return out;
}

TradeState decodeTrade(const m::TradeState* t) {
  TradeState out;
  if (!t)
    return out;
  if (const auto* v = t->exchange()) {
    auto& e = out.exchange;
    e.open = v->open();
    e.receipt = v->receipt();
    e.side = v->side();
    e.canSubmit = v->can_submit();
    e.merchantCount = v->merchant_count();
    e.fortCount = v->fort_count();
    e.merchantSelected = v->merchant_selected();
    e.fortSelected = v->fort_selected();
    e.entityId = v->entity_id();
    e.merchantId = v->merchant_id();
    e.brokerId = v->broker_id();
    e.reply = v->reply()->str();
    e.reason = v->reason()->str();
    e.outcome = v->outcome();
  }
  auto& n = out;
  n.nextCursor = t->next_cursor();
  n.selectedDepot = t->selected_depot();
  n.detail = t->detail()->str();
  for (const auto* v : *t->depots()) {
    TradeDepot d;
    d.id = v->id();
    d.x = v->origin()->x();
    d.y = v->origin()->y();
    d.z = v->origin()->z();
    d.revision = v->revision();
    d.requested = v->requested();
    d.anyone = v->anyone();
    d.accessible = v->accessible();
    d.ready = v->ready();
    d.broker = v->broker()->str();
    d.hauling = v->hauling();
    d.goods = v->goods();
    n.depots.push_back(std::move(d));
  }
  for (const auto* v : *t->caravans())
    n.caravans.push_back({v->id(), v->name()->str(), v->state()->str(), v->days_remaining()});
  for (const auto* v : *t->goods())
    n.goods.push_back({v->id(), v->description()->str(), v->quantity(), v->selected(),
                       v->selectable(), v->reason() ? v->reason()->str() : ""});

  return out;
}

AgreementState decodeAgreement(const m::AgreementState* a) {
  AgreementState out;
  if (!a)
    return out;
  auto& n = out;
  n.nextBeforeId = a->next_before_id();
  n.pendingOnly = a->pending_only();
  if (a->detail())
    n.detail = a->detail()->str();
  if (a->agreements())
    for (const auto* v : *a->agreements()) {
      AgreementInfo p;
      p.id = v->id();
      p.status = uint8_t(v->status());
      p.notApproved = v->not_approved();
      p.concluded = v->concluded();
      p.continuing = v->continuing();
      p.complete = v->complete();
      p.summary = v->summary()->str();
      p.reason = v->reason()->str();
      for (const auto* d : *v->details()) {
        AgreementDetail t;
        t.id = d->id();
        t.kind = d->kind();
        t.siteId = d->site_id();
        t.year = d->year();
        t.yearTick = d->year_tick();
        t.applicantParty = d->applicant_party();
        t.governmentParty = d->government_party();
        t.locationType = d->location_type();
        t.tier = d->tier();
        t.profession = d->profession();
        t.deityType = d->deity_type();
        t.deityId = d->deity_id();
        t.description = d->description()->str();
        p.details.push_back(std::move(t));
      }
      for (const auto* q : *v->parties()) {
        AgreementParty t;
        t.id = q->id();
        t.name = q->name()->str();
        t.entityIds.assign(q->entity_ids()->begin(), q->entity_ids()->end());
        t.histfigIds.assign(q->histfig_ids()->begin(), q->histfig_ids()->end());
        p.parties.push_back(std::move(t));
      }
      n.agreements.push_back(std::move(p));
    }

  return out;
}

flatbuffers::Offset<m::StocksRequest> encodeStocks(flatbuffers::FlatBufferBuilder& b,
                                                   const StocksRequest& value) {
  const auto& a = value;
  return m::CreateStocksRequest(b, a.category, a.cursor, b.CreateString(a.query), a.itemId,
                                a.receipt);
}

flatbuffers::Offset<m::TradeRequest> encodeTrade(flatbuffers::FlatBufferBuilder& b,
                                                 const TradeRequest& value) {
  const auto& t = value;
  return m::CreateTradeRequest(b, t.depotId, t.itemId, t.expectedRevision, t.requested, t.anyone,
                               t.cursor, b.CreateString(t.query), t.receipt, t.side, t.selected);
}

flatbuffers::Offset<m::AgreementRequest> encodeAgreement(flatbuffers::FlatBufferBuilder& b,
                                                         const AgreementRequest& value) {
  const auto& a = value;
  return m::CreateAgreementRequest(b, a.id, a.beforeId, b.CreateString(a.query), a.pendingOnly);
}
}  // namespace wm::detail::management
