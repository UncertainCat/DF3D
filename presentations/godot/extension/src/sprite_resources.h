#pragma once
#include "stable_resource_slots.h"
#include "df3d_assets/compositor.h"
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <set>
#include <tuple>
#include <unordered_map>

namespace df3d_godot {
// Main-thread resource owner. Asset slots live until asset replacement;
// appearance/building composites belong to the session. Consumers hold stable
// handles and observe revision before reusing cached engine resources.
class SpriteResources {
public:
    struct TextureSlot {
        int page=-1, paletteRow=-1;
        bool fill=false;
        godot::Ref<godot::ImageTexture> texture;
        int width=0, height=0;
        godot::Vector2 cutoutScale{1,1}, cutoutOffset{};
    };
    struct CompositeSlot {
        int slot=-1;
        godot::Vector2 size{1,1};
        bool failed=false;
    };
    StableResourceSlots<TextureSlot> slots;
    df3d::assets::CompositeCache composites;
    std::unordered_map<uint32_t, CompositeSlot> appearances;
    std::map<std::string,int> buildings;
    std::map<int,godot::Ref<godot::Image>> images;
    std::map<std::string,godot::Ref<godot::ArrayMesh>> meshes;
    std::map<std::tuple<int,int,int,int,int>,godot::Vector2> metrics;
    uint64_t revision=0;
    bool collectionPending=true;
    uint64_t membershipSeen=UINT64_MAX, collections=0;
    int buildsSeen=-1;

    void retire(int slot) {
        if (!slots.erase(slot)) return;
        images.erase(slot);
        const auto prefix=std::to_string(slot)+":";
        std::erase_if(meshes,[&](const auto& e){return e.first.starts_with(prefix);});
        std::erase_if(metrics,[&](const auto& e){return std::get<0>(e.first)==slot;});
        ++revision;
    }
    void retainAppearances(const std::set<uint32_t>& versions, const std::set<int>& published) {
        for (auto it=appearances.begin(); it!=appearances.end();) {
            if (versions.contains(it->first) || published.contains(it->second.slot)) { ++it; continue; }
            retire(it->second.slot);
            composites.erase(it->first);
            it=appearances.erase(it);
        }
    }
    void resetSession() {
        for (const auto& [version, appearance]:appearances) retire(appearance.slot);
        for (const auto& [key, slot]:buildings) retire(slot);
        appearances.clear(); buildings.clear(); composites.clear();
        collectionPending=true;
        ++revision;
    }
    void clear() {
        slots.clear(); composites.clear(); appearances.clear(); buildings.clear();
        images.clear(); meshes.clear(); metrics.clear(); ++revision;
        collectionPending=true;
    }
};
}
