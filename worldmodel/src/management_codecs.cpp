#include "management_codecs.h"
namespace wm::detail::management {
namespace m = df3d::mirror;

ManagementState decodeState(const m::ManagementState* s) {
  ManagementState next;
  next.revision = s->revision();
  next.worldEpoch = s->world_epoch();
  next.requestSeq = s->request_seq();
  next.action = ManagementAction(s->action());
  next.status = ManagementStatus(s->status());

  if (s->message())
    next.message = s->message()->str();
  decodeConstruction(s, next);
  next.area = decodeArea(s->area());
  next.creature = decodeCreature(s->creature());
  next.citizen = decodeCitizen(s->citizen());
  next.appointments = decodeAppointments(s->appointments());
  next.production = decodeProduction(s->production());
  next.workOrder = decodeWorkOrder(s->work_order());
  next.kitchen = decodeKitchen(s->kitchen());
  next.stocks = decodeStocks(s->stocks());
  next.trade = decodeTrade(s->trade());
  next.agreement = decodeAgreement(s->agreement());
  next.selection = decodeSelection(s->selection());
  next.alert = decodeAlert(s->alert());
  next.report = decodeReport(s->report());
  return next;
}

void encodeRequest(flatbuffers::FlatBufferBuilder& b, const ManagementRequest& r, uint64_t clientId,
                   uint64_t sequence, uint64_t worldEpoch) {
  m::TilePos p(r.x, r.y, r.z);
  flatbuffers::Offset<m::AreaRequest> area;
  if (r.action >= ManagementAction::AreaCatalog && r.action <= ManagementAction::AreaCandidates) {
    area = encodeArea(b, r.area);
  }
  flatbuffers::Offset<m::ProductionRequest> production;
  if (r.action >= ManagementAction::ProductionList && r.action <= ManagementAction::FarmSetCrop) {
    production = encodeProduction(b, r.production);
  }
  flatbuffers::Offset<m::WorkOrderRequest> workOrder;
  if (r.action >= ManagementAction::WorkOrderList &&
      r.action <= ManagementAction::WorkOrderCatalog) {
    workOrder = encodeWorkOrder(b, r.workOrder);
  }
  flatbuffers::Offset<m::CitizenRequest> citizen;
  if (r.action >= ManagementAction::CitizenList && r.action <= ManagementAction::WorkDetailMode) {
    citizen = encodeCitizen(b, r.citizen);
  }
  flatbuffers::Offset<m::SelectionRequest> selection;
  if (r.action == ManagementAction::Selection) {
    selection = encodeSelection(b, r.selection);
  }
  flatbuffers::Offset<m::AlertRequest> alert;
  if (r.action == ManagementAction::Alert) {
    alert = encodeAlert(b, r.alert);
  }
  flatbuffers::Offset<m::KitchenRequest> kitchen;
  if (r.action >= ManagementAction::KitchenOpen && r.action <= ManagementAction::KitchenClose) {
    kitchen = encodeKitchen(b, r.kitchen);
  }
  flatbuffers::Offset<m::AppointmentsRequest> appointments;
  if (r.action >= ManagementAction::AppointmentsOpen &&
      r.action <= ManagementAction::AppointmentsBack) {
    appointments = encodeAppointments(b, r.appointments);
  }
  flatbuffers::Offset<m::StocksRequest> stocks;
  if (r.action >= ManagementAction::StocksOpen && r.action <= ManagementAction::StocksClose) {
    stocks = encodeStocks(b, r.stocks);
  }
  flatbuffers::Offset<m::TradeRequest> trade;
  if (r.action >= ManagementAction::TradeList && r.action <= ManagementAction::TradeExchangeClose) {
    trade = encodeTrade(b, r.trade);
  }
  flatbuffers::Offset<m::AgreementRequest> agreement;
  if (r.action >= ManagementAction::AgreementList &&
      r.action <= ManagementAction::AgreementInspect) {
    agreement = encodeAgreement(b, r.agreement);
  }
  flatbuffers::Offset<m::ReportRequest> report;
  if (r.action >= ManagementAction::ReportList && r.action <= ManagementAction::ReportInspect) {
    report = encodeReport(b, r.report);
  }
  std::vector<flatbuffers::Offset<m::ConstructionSelection>> selections;
  for(const auto& v:r.selections)selections.push_back(m::CreateConstructionSelection(b,v.filter,v.itemType,v.itemSubtype,v.matType,v.matIndex,v.count));
  auto request = m::CreateConstructionRequest(
      b, m::kManagementVersion, clientId, sequence, worldEpoch, m::ManagementAction(r.action),
      b.CreateString(r.definition), &p, r.width, r.height, r.direction, b.CreateVector(r.items),
      r.cursor, r.buildingId, area, production, workOrder, citizen, report, agreement, trade,
      stocks, appointments, kitchen, alert, selection,
      r.action == ManagementAction::CreatureInspect ? m::CreateCreatureRequest(b, r.creatureUnitId)
                                                    : flatbuffers::Offset<m::CreatureRequest>{},
      r.depth,r.retracting,r.filter,b.CreateVector(selections),uint64_t(r.expectedListRevision));
  b.Finish(request);
}
}  // namespace wm::detail::management
