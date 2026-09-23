#pragma once
#include "PluginManager.h"
#include "mirror_generated.h"
namespace df3d_contact {
void registerCommands(std::vector<DFHack::PluginCommand>& commands);
void setEnabled(bool enabled);
void reset();
void shutdown();
bool available();
uint64_t dropped();
const char* status();
flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<df3d::mirror::ItemContactEvent>>>
build(flatbuffers::FlatBufferBuilder&,uint64_t tick);
flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<df3d::mirror::ResolvedAttack>>>
buildAttacks(flatbuffers::FlatBufferBuilder&,uint64_t tick);
uint64_t attacksDropped();
flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<df3d::mirror::ProjectileCombatEvent>>>
buildProjectiles(flatbuffers::FlatBufferBuilder&,uint64_t tick);
uint64_t projectilesDropped();
}
