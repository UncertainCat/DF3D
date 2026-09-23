#pragma once
// Logical inputs to presentation upload APIs, not driver traffic or residency.
// Fixed storage; no allocations, clocks, or increments when disabled.
#include <array>
#include <cstddef>
#include <cstdint>

namespace df3d_godot::submission {
enum BuildingReason : uint32_t { Window = 1, Semantic = 2, Layout = 4, Visibility = 8 };
struct GeometryFingerprint { uint64_t full = 0, withoutY = 0; bool valid = false; };
inline uint64_t hashBytes(uint64_t hash, const void* data, std::size_t count) {
    const auto* bytes = static_cast<const unsigned char*>(data);
    for (std::size_t i = 0; i < count; ++i) { hash ^= bytes[i]; hash *= 1099511628211ULL; }
    return hash;
}
inline const char* streamRelation(const GeometryFingerprint& previous,uint64_t full,uint64_t withoutY,bool supported) {
    return !supported?"unavailable":!previous.valid?"first":previous.full==full?"identical":previous.withoutY==withoutY?"y_only":"changed";
}
enum class MeshSite { Terrain, Building, Batch, Cutout, Backdrop, Count };
enum class TextureSite { Atlas, Walltop, Glyph, Composite, BuildingArt, Minimap, Ui, Portrait, Count };
inline constexpr std::array meshNames{"terrain", "building", "batch", "cutout", "backdrop"};
inline constexpr std::array textureNames{"atlas", "walltop", "glyph", "composite", "building_art", "minimap", "ui", "portrait"};
struct MeshCounts {
    uint64_t calls = 0, vertices = 0, indices = 0, bytes = 0, resources = 0, unknownChannels = 0;
};
struct TextureCounts { uint64_t calls = 0, bytes = 0; };
class Counters {
public:
    explicit Counters(bool enabled) : enabled_(enabled) {}
    bool enabled() const { return enabled_; }
    void mesh(MeshSite site, uint64_t vertices, uint64_t indices, uint64_t bytes, uint64_t unknownChannels = 0) {
        if (!enabled_) return;
        auto& value = meshes[std::size_t(site)];
        ++value.calls; value.vertices += vertices; value.indices += indices;
        value.bytes += bytes; value.unknownChannels += unknownChannels;
    }
    void resource(MeshSite site) { if (enabled_) ++meshes[std::size_t(site)].resources; }
    void texture(TextureSite site, uint64_t bytes) {
        if (!enabled_) return;
        ++textures[std::size_t(site)].calls; textures[std::size_t(site)].bytes += bytes;
    }
    std::array<MeshCounts, std::size_t(MeshSite::Count)> meshes{};
    std::array<TextureCounts, std::size_t(TextureSite::Count)> textures{};
private:
    bool enabled_;
};
}
