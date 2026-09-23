#pragma once
#include "wm/world_model.h"
#include "df3d_mesher/cutout.h"
#include <algorithm>
#include <map>
#include <string_view>
#include <tuple>

namespace df3d::mesher {
// Presentation categories, bottom to top. The two-layer limit belongs to each
// real item identity's quantity; separate items always contribute their layers.
inline int itemStackRank(wm::ItemKind kind) {
    using K = wm::ItemKind;
    switch (kind) {
    case K::Door: case K::Floodgate: case K::Bed: case K::Chair:
    case K::Window: case K::Table: case K::Coffin: case K::Statue:
    case K::Armorstand: case K::Weaponrack: case K::Cabinet: case K::Anvil:
    case K::CatapultParts: case K::BallistaParts: case K::PipeSection:
    case K::HatchCover: case K::Grate: case K::Quern: case K::Millstone:
    case K::TractionBench: case K::Slab: return 0;
    case K::Cage: case K::Barrel: case K::Bucket: case K::AnimalTrap:
    case K::Box: case K::Bag: case K::Bin: return 1;
    case K::Bar: case K::Blocks: case K::Rough: case K::Boulder:
    case K::Wood: case K::Corpse: case K::SkinTanned: case K::Cloth:
    case K::SiegeAmmo: case K::Rock: case K::Branch: return 2;
    case K::Weapon: case K::Armor: case K::Shoes: case K::Shield:
    case K::Helm: case K::Gloves: case K::Pants: case K::Backpack:
    case K::Quiver: case K::TrapParts: case K::TrapComp: case K::Tool:
    case K::Chain: case K::Instrument: case K::Splint: case K::Crutch:
    case K::OrthopedicCast: return 3;
    default: return 4;
    }
}
struct ItemStackLayer {
    const wm::MapItem* item;
    float bottom; // above floor support, including optional installed furniture
    float thickness;
};
inline std::vector<ItemStackLayer> itemStack(std::span<const wm::MapItem* const> items,
                                           float support = 0.0f) {
    using Key = std::tuple<int, wm::ItemKind, std::string, uint16_t>;
    std::map<Key, std::vector<const wm::MapItem*>> groups;
    for (auto* item : items) {
        groups[{itemStackRank(item->kind), item->kind, item->subtypeRaw,
                item->subtypeRaw.empty() ? item->subtype : wm::kNoSubtype}].push_back(item);
    }
    std::vector<ItemStackLayer> out;
    for (auto& [key, group] : groups) {
        std::sort(group.begin(), group.end(), [](auto* a, auto* b) { return a->id < b->id; });
        for (auto* item : group) {
            out.push_back({item, 0, 0});
            if (item->stack > 1) out.push_back({item, 0, 0});
        }
    }
    if (out.empty()) return out;
    // One tile above floor total, including installed furniture. A visible seam
    // separates identical silhouettes; scale it with thickness so all layers fit.
    support = std::clamp(support, 0.0f, 0.9f);
    constexpr float normalGap = 0.01f;
    const float step = std::min(kCutoutThickness + normalGap, (0.995f-support)/out.size());
    const float gap = step * (normalGap / (kCutoutThickness + normalGap));
    for (size_t i=0; i<out.size(); ++i) {
        out[i].bottom = support + 0.005f + float(i)*step;
        out[i].thickness = step-gap;
    }
    return out;
}

// Shared by native rendering and worker depth preparation. Query only indexed
// occupants of the selected semantic elevation range before grouping/sorting.
// Preserve the existing descending-z, packed-tile-key and
// itemStack ordering exactly; pointers remain owned by the supplied snapshot.
inline std::vector<ItemStackLayer> visibleItemStackLayers(const wm::WorldModel& model,
                                                         int top, int window, bool reveal) {
    std::vector<ItemStackLayer> layers;
    if (top < 0 || window <= 0) return layers;
    using TileOrder = std::pair<int64_t, uint64_t>;
    struct Entry { const wm::MapItem* item; TileOrder tile; };
    std::vector<Entry> selected;
    size_t layerCount = 0;
    model.forEachItemInZRange(int32_t(std::max<int64_t>(0, int64_t(top) - window + 1)), top, [&](const wm::MapItem& item) {
        const auto p = item.pos;
        if (p.z < 0 || p.z > top || int64_t(p.z) <= int64_t(top) - window) return;
        if (!reveal) {
            const auto tile = model.tileAt(p);
            if (tile && (tile->flags & wm::kTileHidden)) return;
        }
        const uint64_t key = (uint64_t(uint32_t(p.z)) << 42) |
            (uint64_t(uint32_t(p.y) & 0x1FFFFF) << 21) | (uint32_t(p.x) & 0x1FFFFF);
        selected.push_back({&item, {-int64_t(p.z), key}});
        layerCount += item.stack > 1 ? 2 : 1;
    });
    // Compare borrowed raw names: no per-tile maps, per-kind vectors or string
    // copies. This is the exact concatenation of the former map/sort keys.
    const auto order = [](const wm::MapItem* item) {
        return std::tuple{itemStackRank(item->kind), item->kind,
            std::string_view(item->subtypeRaw),
            item->subtypeRaw.empty() ? item->subtype : wm::kNoSubtype, item->id};
    };
    std::sort(selected.begin(), selected.end(), [&](const Entry& a, const Entry& b) {
        if (a.tile != b.tile) return a.tile < b.tile;
        return order(a.item) < order(b.item);
    });
    layers.reserve(layerCount);
    for (size_t first = 0; first < selected.size();) {
        size_t end = first, count = 0;
        while (end < selected.size() && selected[end].tile == selected[first].tile) {
            count += selected[end].item->stack > 1 ? 2 : 1;
            ++end;
        }
        // Keep itemStack's support=0 arithmetic and quantity-layer limit exact.
        constexpr float normalGap = 0.01f;
        const float step = std::min(kCutoutThickness + normalGap, 0.995f/count);
        const float gap = step * (normalGap / (kCutoutThickness + normalGap));
        size_t index = 0;
        for (size_t i = first; i < end; ++i) {
            const auto* item = selected[i].item;
            for (int piece = 0; piece < (item->stack > 1 ? 2 : 1); ++piece) {
                layers.push_back({item, 0.005f + float(index)*step, step-gap});
                ++index;
            }
        }
        first = end;
    }
    return layers;
}
}
