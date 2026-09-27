#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include "management_codecs.h"
#include "management_dictionary.h"

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


bool validateAgreementShape(const Dictionary& data, String& error) {
  return managementDictionaryTypes(data, {"id", "before_id"}, error) &&
      managementRequiredFields(data, error);
}

// management_request("agreements", request): action 36 lists, 37 inspects.
// id: int -1..INT32_MAX; -1 absent, required native agreements[].id for 37;
//     36 must omit it or use -1.
// before_id: int -1..INT32_MAX, 36 only; exclusive previous next_before_id,
//     -1 starts newest. query: String <=128 UTF-8 bytes, 36 only; exact decimal
//     id or case-insensitive substring of summary, party names, descriptions.
// pending_only: bool, default false, 36 only; plotinfo.petitions membership, echoed.
// Reply poll_management()["agreement"]: agreements[]{id, status (0 Pending,
// 1 Accepted, 2 Unapproved, 3 Concluded), not_approved, concluded, continuing,
// complete, summary, reason, details[]{id, kind, site_id, year, year_tick,
// applicant_party, government_party, location_type, tier, profession, deity_type,
// deity_id, description}, parties[]{id, name, entity_ids[], histfig_ids[]}},
// next_before_id, pending_only, detail. Pending is native petition membership;
// neither denial nor expiry is inferred (e12/findings.md item 8).
bool readAgreement(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  bool valid = true;
  auto n = [&](const char* key, int64_t def, int64_t low, int64_t high) {
    int64_t value = data.get(key, def);
    if (value < low || value > high) valid = false;
    return value;
  };
  r.action = wm::ManagementAction(n("action", 0, static_cast<int>(wm::ManagementAction::AgreementList),
      static_cast<int>(wm::ManagementAction::AgreementInspect)));
  auto& value = r.agreement;
  value.id = int32_t(n("id", -1, -1, INT32_MAX));
  value.beforeId = int32_t(n("before_id", -1, -1, INT32_MAX));
  String query = data.get("query", String());
  value.query = query.utf8().get_data();
  if (value.query.size() > 128) valid = false;
  value.pendingOnly = data.get("pending_only", false);
  if (r.action == wm::ManagementAction::AgreementList && value.id != -1) valid = false;
  if (r.action == wm::ManagementAction::AgreementInspect &&
      (value.beforeId != -1 || !value.query.empty() || value.pendingOnly)) valid = false;
  if (!valid) { error = "Invalid bounded agreement request"; return false; }
  return true;
}

bool validateTradeShape(const Dictionary& data, String& error) {
  return managementDictionaryTypes(data, {"depot_id", "item_id", "expected_revision", "requested", "anyone", "cursor", "receipt", "side", "selected"}, error) &&
      managementRequiredFields(data, error);
}

bool readTrade(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  bool valid = true;
  auto n = [&](const char* key, int64_t def, int64_t low, int64_t high) {
    int64_t value = data.get(key, def);
    if (value < low || value > high) valid = false;
    return value;
  };
  r.action = wm::ManagementAction(n("action", 0, static_cast<int>(wm::ManagementAction::TradeList),
      static_cast<int>(wm::ManagementAction::TradeBring)));
  auto& value = r.trade;
  value.depotId = int32_t(n("depot_id", -1, -1, INT32_MAX));
  value.itemId = int32_t(n("item_id", -1, -1, INT32_MAX));
  value.expectedRevision = uint64_t(n("expected_revision", 0, 0, INT64_MAX));
  value.requested = int8_t(n("requested", -1, -1, 1));
  value.anyone = int8_t(n("anyone", -1, -1, 1));
  value.cursor = uint32_t(n("cursor", 0, 0, UINT32_MAX));
  value.receipt = uint64_t(n("receipt", 0, 0, INT64_MAX));
  value.side = uint8_t(n("side", 0, 0, 1));
  value.selected = int8_t(n("selected", -1, -1, 1));
  String query = data.get("query", String());
  value.query = query.utf8().get_data();
  if (value.query.size() > 128) valid = false;
  if (!valid) { error = "Invalid bounded trade request"; return false; }
  return true;
}
}  // namespace df3d_godot::management
