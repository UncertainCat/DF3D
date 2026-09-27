#pragma once
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include "wm/management_client.h"

namespace df3d_godot::management {
// Stateless presentation codecs own dictionary spelling, types and bounds.
// Callers own connection availability and request sequencing.
void writeConstruction(godot::Dictionary& result, const wm::ManagementState& s);
void writeArea(godot::Dictionary& result, const wm::AreaState& s);
void writeProduction(godot::Dictionary& result, const wm::ProductionState& s);
void writeWorkOrder(godot::Dictionary& result, const wm::WorkOrderState& s);
void writeCitizen(godot::Dictionary& result, const wm::CitizenState& s);
void writeAgreement(godot::Dictionary& result, const wm::AgreementState& s);
void writeTrade(godot::Dictionary& result, const wm::TradeState& s);
void writeReport(godot::Dictionary& result, const wm::ReportState& s);
// Preserve the public adapter error precedence: shape validation, connection
// availability, then bounded conversion. read* requires successful validate*Shape.
bool validateConstructionShape(const godot::Dictionary& data, godot::String& error);
bool readConstruction(const godot::Dictionary& data, wm::ManagementRequest& r,
                      godot::String& error);
bool validateAreaShape(const godot::Dictionary& data, godot::String& error);
bool readArea(const godot::Dictionary& data, wm::ManagementRequest& r, godot::String& error);
bool validateWorkOrderShape(const godot::Dictionary& data, godot::String& error);
bool readWorkOrder(const godot::Dictionary& data, wm::ManagementRequest& r, godot::String& error);
bool validateReportShape(const godot::Dictionary& data, godot::String& error);
bool readReport(const godot::Dictionary& data, wm::ManagementRequest& r, godot::String& error);
bool validateProductionShape(const godot::Dictionary& data, godot::String& error);
bool readProduction(const godot::Dictionary& data, wm::ManagementRequest& r, godot::String& error);
bool validateCitizenShape(const godot::Dictionary& data, godot::String& error);
bool readCitizen(const godot::Dictionary& data, wm::ManagementRequest& r, godot::String& error);
bool validateAgreementShape(const godot::Dictionary& data, godot::String& error);
bool readAgreement(const godot::Dictionary& data, wm::ManagementRequest& r, godot::String& error);
bool validateTradeShape(const godot::Dictionary& data, godot::String& error);
bool readTrade(const godot::Dictionary& data, wm::ManagementRequest& r, godot::String& error);
}  // namespace df3d_godot::management
