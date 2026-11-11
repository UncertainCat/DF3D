#pragma once
#include "management_util.h"
#include "wm/management_client.h"

namespace wm::detail::management {
inline SelectionAppearance decodeItemRecipe(const df3d::mirror::SelectionAppearance* p) {
  SelectionAppearance result;
  for(const auto* t:*p->tile_pages())result.tilePages.push_back(t->str());
  for(const auto* t:*p->palettes())result.palettes.push_back(t->str());
  for(const auto* l:*p->layers())result.layers.push_back({l->page(),l->tile_x(),l->tile_y(),l->cells_x(),l->cells_y(),
    l->palette(),l->palette_row(),l->palette_key_row(),l->offset_x(),l->offset_y()});
  return result;
}
inline ItemInspectionAppearance decodeInspectionAppearance(const df3d::mirror::ItemInspectionAppearance* a) {
  ItemInspectionAppearance result{a->material_token()->str(),a->subtype_raw()->str(),a->color_token()->str(),a->stack(),a->flags(),a->instrument_family(),a->instrument_placed()};
  result.slabEngraving=a->slab_engraving();
  result.craftSoftMaterial=a->craft_soft_material();result.artifactMood=a->artifact_mood();
  if(a->craft_gem_color())result.craftGemColor=a->craft_gem_color()->str();
  if(a->legwear_selector())result.legwearSelector=decodeItemRecipe(a->legwear_selector());
  if(a->corpse_selector())result.corpseSelector=decodeItemRecipe(a->corpse_selector());
  if(a->portrait())result.portrait=decodeItemRecipe(a->portrait());
  if(a->cage_occupant())result.cageOccupant=decodeItemRecipe(a->cage_occupant());
  result.restraintRope=a->restraint_rope();if(a->restraint_solid_color())result.restraintSolidColor=a->restraint_solid_color()->str();
  result.cageMaterialFamily=a->cage_material_family();result.cageOccupantEntity=a->cage_occupant_entity();result.cageOccupantId=a->cage_occupant_id();if(a->cage_solid_color())result.cageSolidColor=a->cage_solid_color()->str();
  result.floodgateOpen=a->floodgate_open();result.doorOpen=a->door_open();result.doorForbidden=a->door_forbidden();result.doorWear=a->door_wear();result.bucketLiquid=a->bucket_liquid();if(a->bucket_liquid_color())result.bucketLiquidColor=a->bucket_liquid_color()->str();
  if(const auto* contents=a->contents()){auto& c=result.contents.emplace();c.container=contents->container();c.materialInorganic=contents->material_inorganic();if(contents->solid_color())c.solidColor=contents->solid_color()->str();
    for(const auto* e:*contents->entries())c.entries.push_back({e->item_type(),e->material_token()->str(),e->color_token()->str(),e->effective_armor_level(),e->metal(),e->coal(),e->contains_powder(),e->rolls_sheets(),e->protects_folded_sheets(),e->contains_writing(),e->liquid(),e->subterranean_plant()});}
  return result;
}
// Only validated wire tables enter these decoders. Each domain owns its fields;
// transport correlation, world epochs and replay policy remain in the client.
// Construction fields are embedded in the legacy envelope, not a nested table.
void decodeConstruction(const df3d::mirror::ManagementState* state, ManagementState& output);
AreaState decodeArea(const df3d::mirror::AreaState* a);
CreatureInfo decodeCreature(const df3d::mirror::CreatureState* c);
CitizenState decodeCitizen(const df3d::mirror::CitizenState* c);
AppointmentsState decodeAppointments(const df3d::mirror::AppointmentsState* t);
ProductionState decodeProduction(const df3d::mirror::ProductionState* p);
WorkOrderState decodeWorkOrder(const df3d::mirror::WorkOrderState* w);
KitchenState decodeKitchen(const df3d::mirror::KitchenState* k);
StocksState decodeStocks(const df3d::mirror::StocksState* t);
TradeState decodeTrade(const df3d::mirror::TradeState* t);
AgreementState decodeAgreement(const df3d::mirror::AgreementState* a);
SelectionState decodeSelection(const df3d::mirror::SelectionState* a);
AlertState decodeAlert(const df3d::mirror::AlertState* a);
ReportState decodeReport(const df3d::mirror::ReportState* r);
ManagementState decodeState(const df3d::mirror::ManagementState* state);
flatbuffers::Offset<df3d::mirror::AreaRequest> encodeArea(flatbuffers::FlatBufferBuilder& b,
                                                          const AreaRequest& value);
flatbuffers::Offset<df3d::mirror::CitizenRequest> encodeCitizen(flatbuffers::FlatBufferBuilder& b,
                                                                const CitizenRequest& value);
flatbuffers::Offset<df3d::mirror::AppointmentsRequest> encodeAppointments(
    flatbuffers::FlatBufferBuilder& b, const AppointmentsRequest& value);
flatbuffers::Offset<df3d::mirror::ProductionRequest> encodeProduction(
    flatbuffers::FlatBufferBuilder& b, const ProductionRequest& value);
WorkOrderArtState decodeArtState(const df3d::mirror::WorkOrderArtState& value);
flatbuffers::Offset<df3d::mirror::WorkOrderArtRequest> encodeArtRequest(flatbuffers::FlatBufferBuilder& b,const WorkOrderArtRequest& value);
flatbuffers::Offset<df3d::mirror::WorkOrderRequest> encodeWorkOrder(
    flatbuffers::FlatBufferBuilder& b, const WorkOrderRequest& value);
flatbuffers::Offset<df3d::mirror::KitchenRequest> encodeKitchen(flatbuffers::FlatBufferBuilder& b,
                                                                const KitchenRequest& value);
flatbuffers::Offset<df3d::mirror::StocksRequest> encodeStocks(flatbuffers::FlatBufferBuilder& b,
                                                              const StocksRequest& value);
flatbuffers::Offset<df3d::mirror::TradeRequest> encodeTrade(flatbuffers::FlatBufferBuilder& b,
                                                            const TradeRequest& value);
flatbuffers::Offset<df3d::mirror::AgreementRequest> encodeAgreement(
    flatbuffers::FlatBufferBuilder& b, const AgreementRequest& value);
flatbuffers::Offset<df3d::mirror::SelectionRequest> encodeSelection(
    flatbuffers::FlatBufferBuilder& b, const SelectionRequest& value);
flatbuffers::Offset<df3d::mirror::AlertRequest> encodeAlert(flatbuffers::FlatBufferBuilder& b,
                                                            const AlertRequest& value);
flatbuffers::Offset<df3d::mirror::ReportRequest> encodeReport(flatbuffers::FlatBufferBuilder& b,
                                                              const ReportRequest& value);
void encodeRequest(flatbuffers::FlatBufferBuilder& builder, const ManagementRequest& request,
                   uint64_t clientId, uint64_t sequence, uint64_t worldEpoch);
}  // namespace wm::detail::management
