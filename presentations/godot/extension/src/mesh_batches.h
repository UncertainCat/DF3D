#pragma once
// Presentation-only spatial merging. Semantic source meshes remain available
// for picking and view effects; dirty groups draw their sources until rebuilt.
#include <godot_cpp/classes/mesh_instance3d.hpp>
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
    explicit MeshBatches(uint64_t quietFrames = 0, const char* detailKind = "other");
    ~MeshBatches();
    void put(uint64_t id, godot::MeshInstance3D* node, godot::Vector3i cell);
    void erase(uint64_t id);
    void clear();
    void flush(double budgetMs);
    void set_enabled(bool value);
    bool enabled() const { return enabled_; }
    int pending() const { return enabled_ ? static_cast<int>(dirty_.size()+quiet_.pending()) : 0; }
    godot::Dictionary stats() const;
private:
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
    struct Work;
    std::unique_ptr<Work> work_;
    bool step();
    void recordDetail(const char* stage,double elapsed,uint64_t copied=0,uint64_t api=0,bool cancelled=false);
    const char* detailKind_;
    std::map<uint64_t, Source> sources_;
    std::map<Key, Group> groups_;
    std::set<Key> dirty_;
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
