#pragma once
#include "mirror_generated.h"
#include "report_journal.h"
#include <string>
namespace df { struct unit; struct item; }
namespace df3d_events {
struct ItemSource {
    int32_t id=-1;
    std::string type, subtype, material;
    uint32_t material_flags=0;
    bool material_flags_known=false;
    std::string melee_skill;
};
ItemSource itemSource(df::item* item);
struct AttackSource {
    int32_t actionId=-1;
    ItemSource weapon;
};
AttackSource attackSource(df::unit* attacker, int32_t victim);
flatbuffers::Offset<df3d::mirror::EventItem> buildItem(flatbuffers::FlatBufferBuilder&, const ItemSource&);
void resetReports(bool newSession=true);
void observeReport(int32_t reportId);
flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<df3d::mirror::ReportEvent>>>
buildReports(flatbuffers::FlatBufferBuilder&, uint64_t tick);
const ReportJournal& reports();
}
