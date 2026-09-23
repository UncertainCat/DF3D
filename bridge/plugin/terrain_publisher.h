#pragma once
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string_view>
#include "mirror_generated.h"
namespace DFHack { class color_ostream; }
namespace df3d::shm { struct RegionHeader; }

// Owns the terrain grid, scan schedule, material interning and publication
// bookkeeping. Access is restricted to the DF simulation safe point.
class TerrainPublisher {
public:
    using Blocks = flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<df3d::mirror::MapBlock>>>;
    using Materials = flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<flatbuffers::String>>>;
    TerrainPublisher();
    ~TerrainPublisher();
    TerrainPublisher(const TerrainPublisher&) = delete;
    TerrainPublisher& operator=(const TerrainPublisher&) = delete;
    bool create(DFHack::color_ostream&, df3d::shm::RegionHeader*);
    void reset(df3d::shm::RegionHeader*);
    bool mapped() const;
    uint64_t epoch() const;
    uint32_t blockCount() const;
    df3d::mirror::TilePos dimensions() const;
    void hintBlock(int32_t x, int32_t y, int32_t z);
    void hintAround(int32_t x, int32_t y, int32_t z);
    // External event hints are added after native job/unit hints, preserving
    // the publication order without coupling this owner to combat retention.
    void scan(uint64_t tick, void (*hintRecentCombat)(uint64_t));
    void setSliceBlocks(uint32_t);
    void requestRescan();
    void printStatus(DFHack::color_ostream&) const;
    size_t materialCount() const;
    size_t materialTokenCount();
    std::string_view materialToken(size_t);
    uint16_t pairMaterial(int16_t type, int32_t index);
    void beginSnapshotMaterials();
    uint16_t localMaterial(flatbuffers::FlatBufferBuilder&, uint16_t gridId);
    Materials finishSnapshotMaterials(flatbuffers::FlatBufferBuilder&);
    // Selection is provisional. Failed publications retain the spill queue;
    // only published() acknowledges it. Fixture Fulls never retire deltas.
    size_t prepareDelta(int32_t frame, size_t snapshotCapacity);
    size_t reduceDelta();
    Blocks buildDelta(flatbuffers::FlatBufferBuilder&);
    Blocks buildFull(flatbuffers::FlatBufferBuilder&);
    void published(int32_t frame);
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
