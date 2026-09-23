#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include "management_codecs.h"

namespace df3d_godot::management {
using namespace godot;
void writeAgreement(Dictionary& result, const wm::AgreementState& s) {
  auto ids = [](const auto& source) {
    Array out;
    for (auto v : source)
      out.push_back(v);
    return out;
  };
  Dictionary agreement;
  Array agreementRows;
  for (const auto& a : s.agreements) {
    Dictionary row;
    row["id"] = a.id;
    row["status"] = a.status;
    row["not_approved"] = a.notApproved;
    row["concluded"] = a.concluded;
    row["continuing"] = a.continuing;
    row["complete"] = a.complete;
    row["summary"] = String::utf8(a.summary.c_str());
    row["reason"] = String::utf8(a.reason.c_str());
    Array ds, ps;
    for (const auto& d : a.details) {
      Dictionary v;
      v["id"] = d.id;
      v["kind"] = d.kind;
      v["site_id"] = d.siteId;
      v["year"] = d.year;
      v["year_tick"] = d.yearTick;
      v["applicant_party"] = d.applicantParty;
      v["government_party"] = d.governmentParty;
      v["location_type"] = d.locationType;
      v["tier"] = d.tier;
      v["profession"] = d.profession;
      v["deity_type"] = d.deityType;
      v["deity_id"] = d.deityId;
      v["description"] = String::utf8(d.description.c_str());
      ds.push_back(v);
    }
    for (const auto& p : a.parties) {
      Dictionary v;
      v["id"] = p.id;
      v["name"] = String::utf8(p.name.c_str());
      v["entity_ids"] = ids(p.entityIds);
      v["histfig_ids"] = ids(p.histfigIds);
      ps.push_back(v);
    }
    row["details"] = ds;
    row["parties"] = ps;
    agreementRows.push_back(row);
  }
  agreement["agreements"] = agreementRows;
  agreement["next_before_id"] = s.nextBeforeId;
  agreement["pending_only"] = s.pendingOnly;
  agreement["detail"] = String::utf8(s.detail.c_str());
  result["agreement"] = agreement;
}

void writeTrade(Dictionary& result, const wm::TradeState& s) {
  Dictionary trade;
  Array tradeDepots, tradeCaravans, tradeGoods;
  for (const auto& d : s.depots) {
    Dictionary row;
    row["id"] = d.id;
    row["position"] = Vector3i(d.x, d.y, d.z);
    row["revision"] = int64_t(d.revision);
    row["requested"] = d.requested;
    row["anyone"] = d.anyone;
    row["accessible"] = d.accessible;
    row["ready"] = d.ready;
    row["broker"] = String::utf8(d.broker.c_str());
    row["hauling"] = d.hauling;
    row["goods"] = d.goods;
    tradeDepots.push_back(row);
  }
  for (const auto& c : s.caravans) {
    Dictionary row;
    row["id"] = c.id;
    row["name"] = String::utf8(c.name.c_str());
    row["state"] = String::utf8(c.state.c_str());
    row["days_remaining"] = c.daysRemaining;
    tradeCaravans.push_back(row);
  }
  for (const auto& g : s.goods) {
    Dictionary row;
    row["id"] = g.id;
    row["description"] = String::utf8(g.description.c_str());
    row["quantity"] = g.quantity;
    row["selected"] = g.selected;
    row["selectable"] = g.selectable;
    row["reason"] = String::utf8(g.reason.c_str());
    tradeGoods.push_back(row);
  }
  trade["depots"] = tradeDepots;
  trade["caravans"] = tradeCaravans;
  trade["goods"] = tradeGoods;
  trade["next_cursor"] = s.nextCursor;
  trade["selected_depot"] = s.selectedDepot;
  trade["detail"] = String::utf8(s.detail.c_str());
  result["trade"] = trade;
}

}  // namespace df3d_godot::management
