#include "df3d_world.h"
#include "entity_color.h"
#include "df3d_assets/classic_glyphs.h"
#include "df3d_mesher/item_stack.h"
#include "df3d_mesher/piece_policy.h"
#include <cstdio>
#include <cmath>
#include <algorithm>
namespace df3d_godot {
namespace assets=df3d::assets;
namespace mesher=df3d::mesher;
using godot::Color;
using godot::Vector2;
using godot::Vector3;
constexpr float kItemScale=0.7f;
const Df3dWorld::ItemLook& Df3dWorld::itemLookFor(const wm::MapItem& it) {
    // Coins change sprite by stack bucket; everything else ignores stack.
    int bucket = 0;
    if (it.kind == wm::ItemKind::Coin)
        bucket = it.stack <= 1 ? 0 : it.stack < 10 ? 1 : it.stack < 50 ? 2 : it.stack < 200 ? 3 : 4;
    // Webs and skulls pick a deterministic variant by id; the
    // corpse flags select body-part tiles.
    const bool web = it.kind == wm::ItemKind::Thread && (it.flags & wm::kItemWeb);
    const bool skull = it.kind == wm::ItemKind::CorpsePiece && (it.corpseFlags & wm::kCorpseSkull);
    const unsigned variant = web ? it.id % 4 : skull ? it.id % 2 : 0;
    char key[192];
    std::snprintf(key, sizeof key, "%d|%s|%u|%d|%d|%u|%u", static_cast<int>(it.kind),
                  it.subtypeRaw.c_str(), static_cast<unsigned>(it.material),
                  (it.flags & (wm::kItemArtifact | wm::kItemWeb)) ? static_cast<int>(it.flags & (wm::kItemArtifact | wm::kItemWeb)) : 0,
                  bucket, static_cast<unsigned>(it.corpseFlags), variant);
    auto found = itemLooks_.find(key);
    if (found != itemLooks_.end()) return found->second;
    PerfScope profile("items.look_miss", nullptr, df3d::profiling::detailed());
    ItemLook look;
    if (assets_) {
        assets::ItemQuery q;
        q.kind = it.kind;
        q.subtypeRaw = it.subtypeRaw;
        q.material = source_.model().materialName(it.material);
        q.flags = it.flags;
        q.stack = it.stack;
        q.corpseFlags = it.corpseFlags;
        q.id = variant;  // the id only selects variants; keep the memo shared
        const assets::ItemSprite r = assets::resolveItem(assets_->index, q);
        look.rule = r.rule;
        if (r.found) {
            const int slot = slotFor(r.sprite.page, r.paletteRow, false);
            if (const TextureSlot* found = slot >= 0 ? spriteResources_.slots.find(slot) : nullptr) {
                const TextureSlot& s = *found;
                const assets::PixelRect px = assets_->index.pixels(r.sprite);
                look.slot = slot;
                look.region = Color(static_cast<float>(px.px) / s.width,
                                    static_cast<float>(px.py) / s.height,
                                    static_cast<float>(px.pw) / s.width,
                                    static_cast<float>(px.ph) / s.height);
                look.size = Vector2(static_cast<float>(r.sprite.w), static_cast<float>(r.sprite.h));
                look.kind = r.bodyPart ? 3 : web ? 5 : 1;
            }
        }
        if (look.slot < 0) {
            ItemGlyphDependency dependency{it.material, it.kind, it.subtypeRaw, {}};
            dependency.observed = dependency.read(source_.model());
            look.glyphDependency = std::move(dependency);
            look.glyphCacheKey = key;
        }
        if (look.slot < 0 && glyphsReady() && source_.model().glyphsKnown()) {
            // No art in the raws: the classic glyph.
            const std::string_view token = source_.model().materialName(it.material);
            const wm::CreatureGlyph* creature = nullptr;
            if (token.compare(0, 9, "CREATURE:") == 0)
                creature = source_.model().creatureGlyph(assets::AssetIndex::materialRawId(token));
            const wm::ItemDefGlyph* def =
                it.subtypeRaw.empty() ? nullptr : source_.model().itemDefGlyph(it.kind, it.subtypeRaw);
            const assets::ClassicGlyphChoice g = assets::classicItemGlyph(
                assets_->index, it.kind, source_.model().materialGlyph(it.material), def ? def->tile : 0, creature, it.flags);
            if (g.found) {
                look.slot = glyphSlotFor(g.glyph.fg, g.glyph.bg, g.glyph.bright);
                if (look.slot >= 0) {
                    look.region = glyphRegion(g.glyph.tile);
                    look.size = glyphSize();
                    look.kind = 4;
                    look.rule = assets::glyphSourceName(g.tileSource);
                }
            }
        }
    }
    return itemLooks_.emplace(key, look).first->second;
}


void Df3dWorld::detachItemGlyphOwner(wm::ItemId id) {
    const auto owner = itemGlyphOwnerKeys_.find(id);
    if (owner == itemGlyphOwnerKeys_.end()) return;
    const auto group = itemGlyphOwners_.find(owner->second);
    if (group != itemGlyphOwners_.end()) {
        group->second.erase(id);
        if (group->second.empty()) itemGlyphOwners_.erase(group);
    }
    itemGlyphOwnerKeys_.erase(owner);
}

void Df3dWorld::refreshGlyphDependencies() {
    if (glyphVersionSeen_ == source_.model().glyphVersion() && glyphKnownSeen_ == source_.model().glyphsKnown()) return;
    PerfScope profile("items.glyph_invalidation", nullptr, df3d::profiling::detailed());
    glyphVersionSeen_ = source_.model().glyphVersion();
    if (glyphKnownSeen_ != source_.model().glyphsKnown()) lastRenderedTick_ = UINT64_MAX;
    glyphKnownSeen_ = source_.model().glyphsKnown();
    // Visit cached fallback looks, never all map items. Art-backed looks have
    // no glyph dependency. Only owners of a changed dependency are reconciled.
    for (auto it = itemLooks_.begin(); it != itemLooks_.end();) {
        const auto& dependency = it->second.glyphDependency;
        if (!dependency || dependency->observed == dependency->read(source_.model())) { ++it; continue; }
        if (const auto owners = itemGlyphOwners_.find(it->first); owners != itemGlyphOwners_.end()) {
            itemUpdateIDs_.insert(owners->second.begin(), owners->second.end());
            layoutItemChanges_.insert(owners->second.begin(), owners->second.end());
        }
        it = itemLooks_.erase(it);
    }
    for (auto it = unitGlyphLooks_.begin(); it != unitGlyphLooks_.end();) {
        std::optional<wm::CreatureGlyph> current;
        if (const auto* row = source_.model().creatureGlyph(it->first)) current = *row;
        if (current == it->second.creatureDependency) { ++it; continue; }
        it = unitGlyphLooks_.erase(it);
        lastRenderedTick_ = UINT64_MAX;
    }
}

void Df3dWorld::configure_sprite_batches(bool enabled, int cell_xy, int cell_z) {
    cell_xy = cell_xy == 8 || cell_xy == 16 ? cell_xy : 32;
    cell_z = cell_z == 4 ? 4 : 1;
    if (enabled == spatialItemBatches_ && cell_xy == itemCellXY_ && cell_z == itemCellZ_) return;
    spatialItemBatches_ = enabled; itemCellXY_ = cell_xy; itemCellZ_ = cell_z;
    itemGroupsNeedReseed_ = true;
    ++itemRenderRevision_;
}

void Df3dWorld::resetItemPayloads() {
    corpseItemChanges_.clear(); hiddenCorpses_.clear();
    itemPositions_.clear(); itemThicknesses_.clear(); itemStackOrdinals_.clear(); itemIds_.clear(); itemSlots_.clear();
    itemRegions_.clear(); itemSizes_.clear(); itemColors_.clear(); itemKinds_.clear(); itemGroundFlags_.clear();
    itemInstanceIndices_.clear(); itemInstanceOrdinals_.clear(); itemUnresolvedNames_.clear();
    itemUpdateIDs_.clear(); pendingItemComposites_.clear();
    itemGlyphOwners_.clear(); itemGlyphOwnerKeys_.clear();
    itemInstanceGroupKeys_.clear(); itemRenderGroups_.clear(); dirtyItemGroups_.clear();
    itemRenderGroupRecords_.clear(); itemRenderGroupsSeen_ = UINT64_MAX;
    itemRenderGroupDelta_.clear(); itemRenderGroupRemoved_.clear(); itemRenderGroupDeltaBase_ = UINT64_MAX;
    itemGroupsNeedReseed_ = true;
    itemsDrawn_ = itemsUnresolved_ = compositeItems_ = pieceItems_ = webItems_ = glyphItems_ = itemCompositePending_ = 0;
    unresolvedItemKinds_.clear(); itemsDirty_ = true;
    ++itemRenderRevision_;
}

void Df3dWorld::markItemInstanceChanged(int index) {
    if (index < 0 || index >= itemPositions_.size()) return;
    ++itemRenderRevision_;
    if (itemGroupsNeedReseed_) return;
    const int slot = itemSlots_[index];
    const Color region = slot < 0 ? Color() : itemRegions_[index];
    const Vector3 p = itemPositions_[index];
    const bool spatial = spatialItemBatches_ && slot >= 0;
    const ItemRenderGroupKey key{slot < 0 ? -1 : slot,region.r,region.g,region.b,region.a,
        spatial ? int(std::floor(p.x/itemCellXY_)) : 0,
        spatial ? int(std::floor(p.y/itemCellZ_)) : 0,
        spatial ? int(std::floor(p.z/itemCellXY_)) : 0};
    itemInstanceGroupKeys_.resize(itemPositions_.size());
    auto& before = itemInstanceGroupKeys_[index];
    if (before && *before != key) {
        const auto old = itemRenderGroups_.find(*before);
        if (old != itemRenderGroups_.end()) old->second.members.erase(index);
        dirtyItemGroups_.insert(*before);
    }
    itemRenderGroups_[key].members.insert(index);
    dirtyItemGroups_.insert(key);
    before = key;
}

void Df3dWorld::adjustItemCounters(int index, int delta) {
    if (itemSlots_[index] >= 0) {
        itemsDrawn_ += delta;
        switch (itemKinds_[index]) {
            case 2: compositeItems_ += delta; break;
            case 3: pieceItems_ += delta; break;
            case 4: glyphItems_ += delta; break;
            case 5: webItems_ += delta; break;
            default: break;
        }
    } else {
        itemsUnresolved_ += delta;
        const auto& name = itemUnresolvedNames_[index];
        auto& count = unresolvedItemKinds_[name]; count += delta;
        if (!count) unresolvedItemKinds_.erase(name);
    }
}

void Df3dWorld::removeItemInstance(int index) {
    PerfScope profile("items.remove", nullptr, df3d::profiling::detailed());
    const int last = int(itemIds_.size())-1;
    const auto id = wm::ItemId(itemIds_[index]);
    adjustItemCounters(index,-1);
    const auto detach = [&](int slot) {
        if (slot >= int(itemInstanceGroupKeys_.size()) || !itemInstanceGroupKeys_[slot]) return;
        const auto key = *itemInstanceGroupKeys_[slot];
        if (const auto found = itemRenderGroups_.find(key); found != itemRenderGroups_.end()) found->second.members.erase(slot);
        dirtyItemGroups_.insert(key); itemInstanceGroupKeys_[slot].reset();
    };
    detach(index);
    auto& owned = itemInstanceIndices_.at(id);
    const int ordinal = itemInstanceOrdinals_[index];
    owned.erase(owned.begin()+ordinal);
    for (int k=ordinal;k<int(owned.size());++k) itemInstanceOrdinals_[owned[k]]=k;
    if (index != last) {
        // Packed source compaction is not a membership change for the moved
        // item. Preserve its group-local GPU ordinal while renaming the index.
        if (last < int(itemInstanceGroupKeys_.size()) && itemInstanceGroupKeys_[last]) {
            const auto key = *itemInstanceGroupKeys_[last];
            itemRenderGroups_.at(key).members.rename(last, index);
            dirtyItemGroups_.insert(key);
            itemInstanceGroupKeys_[index] = key;
            itemInstanceGroupKeys_[last].reset();
        }
        const auto moved = wm::ItemId(itemIds_[last]);
        const int movedOrdinal = itemInstanceOrdinals_[last];
        itemPositions_.set(index,itemPositions_[last]); itemThicknesses_.set(index,itemThicknesses_[last]); itemStackOrdinals_.set(index,itemStackOrdinals_[last]);
        itemIds_.set(index,itemIds_[last]); itemSlots_.set(index,itemSlots_[last]);
        itemRegions_.set(index,itemRegions_[last]); itemSizes_.set(index,itemSizes_[last]);
        itemColors_.set(index,itemColors_[last]); itemKinds_.set(index,itemKinds_[last]);
        itemGroundFlags_.set(index,itemGroundFlags_[last]);
        itemInstanceOrdinals_[index]=movedOrdinal;
        itemUnresolvedNames_[index]=std::move(itemUnresolvedNames_[last]);
        itemInstanceIndices_.at(moved)[movedOrdinal]=index;
    }
    if (owned.empty()) itemInstanceIndices_.erase(id);
    itemPositions_.resize(last); itemThicknesses_.resize(last); itemStackOrdinals_.resize(last); itemIds_.resize(last); itemSlots_.resize(last);
    itemRegions_.resize(last); itemSizes_.resize(last); itemColors_.resize(last); itemKinds_.resize(last); itemGroundFlags_.resize(last);
    itemInstanceOrdinals_.resize(last); itemUnresolvedNames_.resize(last); itemInstanceGroupKeys_.resize(last);
    ++itemRenderRevision_;
    if (index != last) markItemInstanceChanged(index);
}

godot::Array Df3dWorld::item_render_groups() {
    PerfScope profile("items.groups", nullptr, df3d::profiling::detailed());
    if (itemRenderGroupsGeneration_ != source_.model().sessionGeneration()) itemGroupsNeedReseed_ = true;
    const bool reseeded = itemGroupsNeedReseed_;
    const uint64_t previousRevision = itemRenderGroupsSeen_;
    if (itemGroupsNeedReseed_) {
        itemRenderGroups_.clear(); dirtyItemGroups_.clear();
        itemInstanceGroupKeys_.assign(itemIds_.size(),std::nullopt);
        itemGroupsNeedReseed_ = false;
        itemRenderGroupsGeneration_ = source_.model().sessionGeneration();
        // Only a batch-configuration/session reset visits every live instance.
        for (int i=0;i<itemIds_.size();++i) markItemInstanceChanged(i);
        itemRenderGroupsSeen_ = UINT64_MAX;
    }
    if (itemRenderGroupsSeen_ == itemRenderRevision_) return itemRenderGroupRecords_;
    itemRenderGroupDelta_ = godot::Array();
    itemRenderGroupRemoved_ = godot::PackedInt64Array();
    itemRenderGroupDeltaBase_ = reseeded ? UINT64_MAX : previousRevision;
    const auto* sourceIds=itemIds_.ptr(); const auto* sourcePositions=itemPositions_.ptr();
    const auto* sourceSizes=itemSizes_.ptr(); const auto* sourceThicknesses=itemThicknesses_.ptr(); const auto* sourceOrdinals=itemStackOrdinals_.ptr();
    const auto* sourceColors=itemColors_.ptr(); const auto* sourceGround=itemGroundFlags_.ptr();
    for (const auto& key : dirtyItemGroups_) {
        const auto found = itemRenderGroups_.find(key);
        if (found == itemRenderGroups_.end()) continue;
        auto& group = found->second;
        if (group.members.empty()) {
            if (group.key) itemRenderGroupRemoved_.push_back(int64_t(group.key));
            itemRenderGroups_.erase(found);
            continue;
        }
        ++itemGroupBuildCount_;
        const int count = int(group.members.size());
        const bool hasBaseline = group.key != 0;
        const int oldCount = int(group.ids.size());
        bool same = hasBaseline && oldCount == count;
        bool sameIndices = same;
        godot::PackedInt32Array changedIndices;
        const int64_t baseRevision = int64_t(group.revision);
        if (hasBaseline) {
            const auto* oldIndices=group.indices.ptr(); const auto* oldIds=group.ids.ptr();
            const auto* oldPositions=group.positions.ptr(); const auto* oldSizes=group.sizes.ptr();
            const auto* oldThicknesses=group.thicknesses.ptr(); const auto* oldColors=group.colors.ptr();
            const auto* oldGround=group.groundFlags.ptr();
            int k=0;
            for (int i : group.members) {
                ++itemGroupMemberChecks_;
                sameIndices &= k < oldCount && oldIndices[k] == i;
                if (k >= oldCount || oldIds[k] != sourceIds[i] || oldPositions[k] != sourcePositions[i] ||
                    oldSizes[k] != sourceSizes[i] || oldThicknesses[k] != sourceThicknesses[i] || group.stackOrdinals[k] != sourceOrdinals[i] ||
                    oldColors[k] != sourceColors[i] || oldGround[k] != sourceGround[i]) {
                    same=false;
                    changedIndices.push_back(k);
                }
                ++k;
            }
        }
        if (same) {
            if (!sameIndices) {
                auto* output = group.indices.ptrw();
                std::copy(group.members.begin(),group.members.end(),output);
                group.record = group.record.duplicate();
                group.record["indices"] = group.indices;
                group.record["base_revision"] = baseRevision;
                group.record["changed_indices"] = godot::PackedInt32Array();
                itemRenderGroupDelta_.push_back(group.record);
            }
            continue;
        }
        group.indices.resize(count); group.ids.resize(count); group.positions.resize(count);
        group.sizes.resize(count); group.thicknesses.resize(count); group.stackOrdinals.resize(count); group.colors.resize(count); group.groundFlags.resize(count);
        auto* indices=group.indices.ptrw(); auto* ids=group.ids.ptrw(); auto* positions=group.positions.ptrw();
        auto* sizes=group.sizes.ptrw(); auto* thicknesses=group.thicknesses.ptrw(); auto* colors=group.colors.ptrw();
        auto* ground=group.groundFlags.ptrw();
        int k=0;
        for (int i : group.members) {
            ++itemGroupMemberChecks_;
            indices[k]=i; ids[k]=sourceIds[i]; positions[k]=sourcePositions[i];
            sizes[k]=sourceSizes[i]; thicknesses[k]=sourceThicknesses[i]; group.stackOrdinals.set(k,sourceOrdinals[i]); colors[k]=sourceColors[i]; ground[k]=sourceGround[i]; ++k;
        }
        group.revision=++itemRenderGroupRevision_;
        if (!group.key) group.key=++itemRenderGroupKey_;
        godot::Dictionary record;
        record["key"]=int64_t(group.key); record["revision"]=int64_t(group.revision);
        record["base_revision"] = hasBaseline ? baseRevision : int64_t(-1);
        record["changed_indices"] = hasBaseline ? changedIndices : godot::PackedInt32Array();
        record["slot"]=std::get<0>(key);
        record["region"]=Color(std::get<1>(key),std::get<2>(key),std::get<3>(key),std::get<4>(key));
        record["cell"]=godot::Vector3i(std::get<5>(key),std::get<6>(key),std::get<7>(key));
        record["indices"]=group.indices; group.record=record;
        itemRenderGroupDelta_.push_back(record);
    }
    dirtyItemGroups_.clear();
    godot::Array records;
    for (const auto& [key,group] : itemRenderGroups_) records.push_back(group.record);
    itemRenderGroupRecords_=records; itemRenderGroupsSeen_=itemRenderRevision_;
    return itemRenderGroupRecords_;
}

godot::Dictionary Df3dWorld::item_render_group_delta(int64_t since) {
    item_render_groups();
    const bool current = since >= 0 && uint64_t(since) == itemRenderGroupsSeen_;
    const bool full = !current && (since < 0 || itemRenderGroupDeltaBase_ == UINT64_MAX ||
        uint64_t(since) != itemRenderGroupDeltaBase_);
    godot::Dictionary result;
    result["revision"] = int64_t(itemRenderGroupsSeen_);
    result["full"] = full;
    result["groups"] = current ? godot::Array() : (full ? itemRenderGroupRecords_ : itemRenderGroupDelta_);
    result["removed"] = current || full ? godot::PackedInt64Array() : itemRenderGroupRemoved_;
    return result;
}

void Df3dWorld::updateItems() {
    const double profileStart=df3d::profiling::timestampUs();
    ++perfItemCount_; PerfScope itemTimer{"items.update", &perfItemMs_};
    if (itemsDirty_) {
        PerfScope profile("items.reconcile_scope", nullptr, df3d::profiling::detailed());
        // Scope changes reconcile currently materialized owners against only
        // the newly demanded semantic region. Ordinary events never take this path.
        for (const auto& [id,indices] : itemInstanceIndices_) itemUpdateIDs_.insert(id);
        if (topZ_ >= 0) {
            const int bottom=std::max(0,topZ_-spriteWindowDepth()+1);
            const auto select=[&](const wm::MapItem& item){itemUpdateIDs_.insert(item.id);};
            if (presentationRegionEnabled_) {
                const auto end=presentationRegion_.get_end();
                source_.model().forEachItemInBox({presentationRegion_.position.x,presentationRegion_.position.y,bottom},
                    {end.x-1,end.y-1,topZ_},select);
            } else source_.model().forEachItemInZRange(bottom,topZ_,select);
        }
        itemsDirty_=false;
    }
    for (const auto& [id,count] : pendingItemComposites_) itemUpdateIDs_.insert(id);
    auto updates=std::move(itemUpdateIDs_); itemUpdateIDs_.clear();
    const auto deadline=std::chrono::steady_clock::now()+
        std::chrono::microseconds(static_cast<int64_t>(compositeBudgetMs_*1000.0));
    bool attemptedComposite=false;
    for (const auto id : updates) {
        PerfScope ownerProfile("items.owner_slow", nullptr, df3d::profiling::detailed(), 100);
        ++itemUpdateCount_;
        detachItemGlyphOwner(id);
        if (const auto pending=pendingItemComposites_.find(id);pending!=pendingItemComposites_.end()) {
            itemCompositePending_-=pending->second; pendingItemComposites_.erase(pending);
        }
        const auto* item=source_.model().item(id);
        const bool visible=item && !hiddenCorpses_.count(id) && topZ_>=0 && zInSpriteWindow(item->pos.z) && tileVisible(item->pos) && presentationTileDemanded(item->pos);
        const int wanted=visible?(item->stack>1?2:1):0;
        auto owned=itemInstanceIndices_.find(id);
        while (owned!=itemInstanceIndices_.end() && int(owned->second.size())>wanted) {
            removeItemInstance(owned->second.back()); owned=itemInstanceIndices_.find(id);
        }
        if (!visible) continue;
        ItemLook look;
        bool pending=false;
        {
            PerfScope appearanceProfile("items.appearance_slow", nullptr, df3d::profiling::detailed(), 100);
            const auto* appearance=item->kind==wm::ItemKind::Corpse && !wm::isSkeleton(item->corpseFlags)?source_.model().itemAppearance(id):nullptr;
            bool composited=false;
            if (appearance && !appearance->layers.empty()) {
                if (!spriteResources_.appearances.count(appearance->version) && (!attemptedComposite || compositeBudgetMs_<=0 || std::chrono::steady_clock::now()<deadline)) {
                    compositeFor(appearance->version,appearance->layers,deadline,true);attemptedComposite=true;
                }
                const auto* cs=compositeFor(appearance->version,appearance->layers,deadline,false);
                if (!cs) pending=true;
                else if (!cs->failed) {
                    look.slot=cs->slot;look.region=Color(0,0,1,1);look.size=cs->size;look.kind=2;
                    look.rule="corpse.composite";composited=true;
                }
            }
            if (!composited) look=itemLookFor(*item);
        }
        if (look.glyphDependency) {
            itemGlyphOwners_[look.glyphCacheKey].insert(id);
            itemGlyphOwnerKeys_[id] = look.glyphCacheKey;
        }
        if (pending) {pendingItemComposites_[id]=wanted;itemCompositePending_+=wanted;}
        PerfScope instancesProfile("items.instances_slow", nullptr, df3d::profiling::detailed(), 100);
        const float scale=look.kind==2 || look.kind==3?1.0f:kItemScale;
        const Vector2 size=look.size*scale;
        const Color color=look.slot>=0?Color(1,1,1,1):entityKindColor(wm::itemKindName(item->kind));
        const uint8_t ground=mesher::itemLiesOnGround(item->kind) ? 1 : 0;
        auto& indices=itemInstanceIndices_[id];
        for (int ordinal=0;ordinal<wanted;++ordinal) {
            const bool fresh=ordinal>=int(indices.size());
            int index;
            if (fresh) {
                PerfScope growProfile("items.grow", nullptr, df3d::profiling::detailed());
                index=int(itemIds_.size());const int count=index+1;
                itemPositions_.resize(count);itemThicknesses_.resize(count);itemStackOrdinals_.resize(count);itemIds_.resize(count);itemSlots_.resize(count);
                itemRegions_.resize(count);itemSizes_.resize(count);itemColors_.resize(count);itemKinds_.resize(count);itemGroundFlags_.resize(count);
                itemInstanceOrdinals_.resize(count);itemUnresolvedNames_.resize(count);itemInstanceGroupKeys_.resize(count);
                indices.push_back(index);itemInstanceOrdinals_[index]=ordinal;
            } else {index=indices[ordinal];adjustItemCounters(index,-1);}
            Vector3 position(float(item->pos.x)+.5f,float(item->pos.z)+mesher::kFloorHeight+.005f,float(item->pos.y)+.5f);
            float thickness=mesher::kCutoutThickness;
            if (!fresh && itemPositions_[index].x==position.x && itemPositions_[index].z==position.z &&
                int(std::floor(itemPositions_[index].y))==item->pos.z) {
                position.y=itemPositions_[index].y;thickness=itemThicknesses_[index];
            }
            const bool changed=fresh || itemPositions_[index]!=position || itemThicknesses_[index]!=thickness ||
                itemSlots_[index]!=look.slot || itemRegions_[index]!=look.region || itemSizes_[index]!=size || itemColors_[index]!=color || itemGroundFlags_[index]!=ground;
            if (fresh || itemPositions_[index]!=position) itemPositions_.set(index,position);
            if (fresh || itemThicknesses_[index]!=thickness) itemThicknesses_.set(index,thickness);
            if (fresh) itemIds_.set(index,int64_t(id));
            if (fresh || itemSlots_[index]!=look.slot) itemSlots_.set(index,look.slot);
            if (fresh || itemRegions_[index]!=look.region) itemRegions_.set(index,look.region);
            if (fresh || itemSizes_[index]!=size) itemSizes_.set(index,size);
            if (fresh || itemKinds_[index]!=look.kind) itemKinds_.set(index,look.kind);
            if (fresh || itemGroundFlags_[index]!=ground) itemGroundFlags_.set(index,ground);
            if (fresh || itemColors_[index]!=color) itemColors_.set(index,color);
            itemUnresolvedNames_[index]=look.slot<0?wm::itemKindName(item->kind):"";
            adjustItemCounters(index,1);
            if (changed) markItemInstanceChanged(index);
        }
    }
    itemLastMs_=df3d::profiling::elapsedMs(profileStart);
}
}


namespace df3d_godot {
godot::Array Df3dWorld::corpse_item_changes() {
    auto result = corpseItemChanges_; corpseItemChanges_ = godot::Array(); return result;
}

void Df3dWorld::set_hidden_corpses(const godot::PackedInt64Array& ids) {
    std::set<wm::ItemId> next;
    for (int64_t id : ids) {
        const auto* item = source_.model().item(wm::ItemId(id));
        if (item && item->kind == wm::ItemKind::Corpse && item->corpseUnitId >= 0) next.insert(item->id);
    }
    if (next == hiddenCorpses_) return;
    for (auto id : next) if (!hiddenCorpses_.count(id)) itemUpdateIDs_.insert(id);
    for (auto id : hiddenCorpses_) if (!next.count(id)) itemUpdateIDs_.insert(id);
    std::set<mesher::DepthTile> affected;
    for (auto id : itemUpdateIDs_) if (const auto* item = source_.model().item(id))
        affected.emplace(item->pos.z, item->pos.x, item->pos.y);
    hiddenCorpses_ = std::move(next);
    updateItems();
    // Reapply the resident semantic intervals to newly revealed instances.
    // Hiding a corpse never removes it from the tile layout.
    for (const auto& tile : affected) applyTileLayout(tile, true);
}

}
