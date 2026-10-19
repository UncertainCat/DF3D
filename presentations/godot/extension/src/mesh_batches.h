#pragma once
// Presentation-only spatial merging. Terrain can retire duplicate GPU surfaces
// after publishing, retaining CPU arrays/materials for restoration. Building
// source meshes remain available for view effects. Dirty groups retain their
// preceding published geometry until a complete replacement is ready.
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <map>
#include <set>
#include <tuple>
#include <memory>
#include <vector>
#include "quiet_sources.h"

namespace df3d_godot {
class BatchTexturePool;
class MeshBatches {
public:
    explicit MeshBatches(uint64_t quietFrames = 0, const char* detailKind = "other", bool retireSourceSurfaces = false, bool verticalTerrain = false);
    ~MeshBatches();
    void put(uint64_t id, godot::MeshInstance3D* node, godot::Vector3i cell);
    // Skip restoration when the caller immediately destroys/replaces the mesh.
    void erase(uint64_t id, bool restoreSource = true);
    // Pass false only when the caller will destroy every source immediately.
    void clear(bool restoreSources = true);
    void flush(double budgetMs);
    void set_enabled(bool value);
    static constexpr int terrainSlabLevels = 16;
    void set_terrain_slice(int top, int depth);
    bool enabled() const { return enabled_; }
    int pending() const { return enabled_ ? static_cast<int>(dirty_.size()+quiet_.pending()) : 0; }
    godot::Dictionary stats() const;
private:
    friend class MeshBatchesTest;
    using Key = std::tuple<int,int,int>;
    struct Source {
        godot::MeshInstance3D* node;
        Key cell;
        uint64_t mesh;
        uint32_t layers;
        bool deferred = false;
    };
    struct Group {
        std::set<uint64_t> sources;
        std::vector<godot::MeshInstance3D*> nodes;
        std::map<uint64_t,uint64_t> publishedSourceMeshes;
    };
    void invalidate(const Key& key);
    void restore_group(Group& group);
    void retire_source(Source& source);
    void restore_source(Source& source);
    bool retireSourceSurfaces_ = false;
    bool verticalTerrain_ = false;
    int terrainTop_ = -1, terrainBottom_ = 0;
    std::map<uint64_t,godot::Ref<godot::ShaderMaterial>> terrainMaterials_;
    void apply_terrain_slice(godot::MeshInstance3D* node, const Key& key);
    struct Work;
    std::unique_ptr<Work> work_;
    void begin_work();
    bool step();
    void recordDetail(const char* stage,double elapsed,uint64_t copied=0,uint64_t api=0,bool cancelled=false);
    const char* detailKind_;
    std::map<uint64_t, Source> sources_;
    std::map<Key, Group> groups_;
    std::set<Key> dirty_;
    std::set<Key> edited_;
    QuietSources quiet_;
    bool enabled_ = true;
    std::unique_ptr<BatchTexturePool> textures_;
    uint64_t builds_ = 0;
    uint64_t invalidations_ = 0, cancellations_ = 0, restoreChecks_ = 0;
    uint64_t gatheredSources_ = 0, gatheredVertices_ = 0, uploadedSurfaces_ = 0;
    uint64_t deferrals_ = 0, rejoins_ = 0;
    double buildMs_ = 0;
};
}
