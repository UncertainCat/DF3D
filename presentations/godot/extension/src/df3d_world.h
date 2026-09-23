// Df3dWorld: Godot node adapting the DF3D world model (public wm:: API + pure mesher only, never the mirror); attach()/load_fixture(), then poll() per frame and read the cached arrays.
#pragma once
#include "item_group_members.h"
#include "sprite_resources.h"
#include "layout_causal_probe.h"
#include "shared_stack_atlas.h"
#include "df3d_mesher/terrain_support.h"
#include "unit_art_key.h"
#include "submission_metrics.h"
#include "df3d_mesher/cutout.h"
#include "glyph_dependencies.h"
#include "terrain_visibility_dependencies.h"
#include "profiling.h"
#include "df3d_assets/bitmap_slots.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>

#include <chrono>
#include <cstdint>
#include <list>
#include <map>
#include <memory>
#include <string>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "df3d_assets/classic_glyphs.h"
#include "df3d_assets/compositor.h"
#include "df3d_assets/provider.h"
#include "df3d_assets/resolver.h"
#include "df3d_mesher/block_mesher.h"
#include "df3d_mesher/depth_layout.h"
#include "df3d_mesher/level_block_revision.h"
#include "sprite_ceiling_cache.h"
#include "wm/mirror_client.h"
#include "wm/world_source.h"
#include "df3d_mesher/lazy_tile_layout.h"
#include "mesh_batches.h"
#include "wm/session_client.h"
#include "wm/resident_info.h"
#include "wm/creature_info.h"
#include "wm/management_client.h"
#include "wm/world_model.h"

namespace df3d_godot {

class Df3dWorld : public godot::Node {
    GDCLASS(Df3dWorld, godot::Node)

public:
    Df3dWorld();
    ~Df3dWorld() override;

    void set_mesh_batching_enabled(bool enabled);
    godot::Dictionary mesh_batch_stats() const;
    void refresh_building_batches(int64_t id);

    // --- assets --- load_assets(override_path) must succeed first (else assets_error(); there is no placeholder mode).
    bool load_assets(const godot::String& override_path);
    godot::String assets_root() const;
    bool assets_loaded() const { return static_cast<bool>(assets_); }
    godot::String assets_error() const { return assetsError_; }
    godot::String assets_summary() const;
    // Faces drawn with the vertex-colour placeholder because no tile
    // resolved (counted over the built blocks).
    int64_t unresolved_face_count() const { return unresolvedFaces_; }
    int64_t textured_face_count() const { return texturedFaces_; }
    // Faces of the undisclosed mass (mesher FacePart::Hidden, drawn solid
    // black; merged, so far fewer than the tiles they cover).
    int64_t hidden_face_count() const { return hiddenFaces_; }
    // Tier-4 aid: what the world model holds at a DF tile ("Wall Stone
    // GRANITE hidden" / "outside the map"), for the camera-eye hook.
    godot::String tile_summary(const godot::Vector3i& tile) const;
    godot::Dictionary tile_hover_info(const godot::Vector3i& tile) const;
    int64_t terrain_revision() const { return static_cast<int64_t>(source_.model().terrainVersion()); }
    int64_t spatter_revision() const { return static_cast<int64_t>(source_.model().spatterVersion()); }
    godot::Array tile_spatters(godot::Vector3i tile) const;
    // Read-only interaction queries, in DF tile coordinates; hidden/unknown
    // tiles are excluded even in debug reveal mode.
    godot::Array items_at_tile(const godot::Vector3i& tile) const;
    godot::Array buildings_at_tile(const godot::Vector3i& tile) const;
    godot::Vector3i unit_tile(int64_t id) const;
    godot::Array inspect_tile(const godot::Vector3i& tile) const;
    godot::Dictionary inspect_entity(int64_t kind, int64_t id) const;
    godot::Dictionary pick_building(const godot::Vector3& origin, const godot::Vector3& direction, int z) const;
    // Original interface art, resolved only through the verified parsed index.
    godot::Ref<godot::Texture2D> ui_texture(const godot::String& name, int variant = -1);
    godot::Dictionary elevation_overview(int x, int y) const;
    godot::String ui_font_path() const;
    godot::Vector3i item_tile(int64_t id) const;
    double selection_height(const godot::Vector3i& tile) const;
    godot::Vector3i pick_tile(const godot::Vector3& origin, const godot::Vector3& direction, int z) const;
    godot::Array designation_tiles(int z) const;
    int64_t sprite_resource_revision() const { return int64_t(spriteResources_.revision); }
    bool sprite_slot_valid(int slot) const { return spriteResources_.slots.contains(slot); }
    godot::Dictionary sprite_resource_stats() const;
    // Original rock backing in source sRGB; hidden material source_color
    // uniform converts it like the terrain texture's source_color sampler.
    godot::Color rock_backing_color();
    // Texture behind a sprite slot (unit_sprite_slots); null when invalid.
    godot::Ref<godot::Texture2D> sprite_texture(int slot);
    godot::Ref<godot::ArrayMesh> sprite_cutout_mesh(int slot, godot::Color region);
    // Opaque fraction and bottom padding, measured once per resident art region.
    godot::Color unitScaleFor(int slot, godot::Color region, godot::Vector2 size, uint32_t volume);

    // --- unit appearance composites --- how units were drawn over the last poll().
    int composited_unit_count() const { return compositedUnits_; }
    int simple_sprite_unit_count() const { return simpleUnits_; }
    int cube_unit_count() const { return cubeUnits_; }
    // Units whose composite was deferred to a later poll() by the budget.
    int composite_pending_count() const { return compositePending_; }
    // Composited appearance versions (shared per stack) and the failed ones (not retried).
    int composite_cache_size() const { return static_cast<int>(spriteResources_.appearances.size()); }
    int composite_failed_count() const { return compositeFailed_; }
    int composite_build_count() const { return compositeBuildCount_; }
    double composite_last_ms() const { return compositeLastMs_; }
    double composite_total_ms() const { return compositeTotalMs_; }
    // Compositing budget per poll() (default 8 ms; <= 0 unbounded); overflow draws cubes until the next poll.
    void set_composite_budget_ms(double ms) { compositeBudgetMs_ = ms; }
    // Appearance change events drained so far (units whose stack changed).
    int64_t appearance_event_count() const { return appearanceEvents_; }
    // Tier-4 hook: dumps unit composites as PNGs plus listing/contact sheet under `dir`; returns how many.
    int dump_unit_composites(const godot::String& dir, const godot::PackedInt64Array& ids,
                             int max_units);

    // --- sources ---
    // Opens the live mirror. Safe to call repeatedly; returns current state.
    bool attach();
    void detach_live();
    bool live_synchronized() const { if(!source_.live())return false; const auto s=source_.liveStats();return s.terrainSynced && s.buildingsSynced && s.itemsSynced; }
    godot::Dictionary poll_session();
    godot::Dictionary poll_management();
    void update_resident_info();
    void demand_resident_info(int64_t demand);
    void refresh_resident_info();
    godot::Dictionary resident_info_state();
    void demand_creature_info(int64_t id);
    godot::Dictionary creature_info_state(int64_t id);
    void reconcile_resident_icons();
    godot::Ref<godot::Texture2D> creature_portrait(int64_t id);
    godot::Ref<godot::Texture2D> resident_icon(int64_t id);
    godot::Ref<godot::Texture2D> composite_portrait(const wm::SelectionAppearance& source);
    godot::Ref<godot::Texture2D> composite_appearance_texture(const wm::SelectionAppearance& source, bool framed);
    godot::Ref<godot::Texture2D> selection_icon(int kind,int64_t id);
    int64_t report_request(const godot::Dictionary& data);
    int64_t work_order_request(const godot::Dictionary& data);
    int64_t area_request(const godot::Dictionary& data);
    int64_t construction_request(const godot::Dictionary& request);
    void reconnect_management() { managementClient_.reset(); }
    int64_t load_fortress(const godot::String& id);
    int64_t save_fortress(bool return_to_menu, const godot::String& checkpoint_name);
    // Replays a fixture offline at set_replay_speed; false + last_error() on parse/validation failure.
    bool load_fixture(const godot::String& path);
    void set_replay_speed(double speed) { source_.setReplaySpeed(speed); }
    // Deterministic fixture ingestion for tests. Negative restores wall time.
    void set_replay_elapsed(double seconds) { source_.setReplayElapsed(seconds); }
    // >= 0 freezes the render tick (fixed fake clock, deterministic frames)
    // and ingests the whole fixture at once; < 0 follows the replay clock.
    void set_fixed_render_tick(double tick);
    // True once a live mirror or a fixture is attached.
    bool is_attached() const;
    bool is_live() const { return static_cast<bool>(source_.live()); }
    godot::String source_name() const { return godot::String::utf8(source_.name().c_str()); }
    godot::String last_error() const { return lastError_; }

    // Per-frame ingest, bounded terrain rebuild and unit state update; true when displayed units changed.
    bool poll();

    // --- unit queries over the last poll() --- Godot space (DF x,z,y -> x,y,z), interpolated tile centres, y = floor + half cube.
    godot::PackedVector3Array unit_positions() const { return positions_; }
    int64_t unit_render_revision() const { return static_cast<int64_t>(unitRenderRevision_); }
    int64_t item_render_revision() const { return static_cast<int64_t>(itemRenderRevision_); }
    godot::Array item_render_groups();
    godot::Dictionary item_render_group_delta(int64_t since);
    void configure_sprite_batches(bool enabled, int cell_xy, int cell_z);
    double sprite_ceiling(const godot::AABB& bounds, int floorZ) const;
    int64_t sprite_ceiling_source_revision(const godot::AABB& bounds, int floorZ) const;
    godot::Dictionary sprite_ceiling_cache_stats() const;
    uint64_t spriteCeilingBlockSamples() const { return spriteCeilingCache_.stats.blockSamples; }
    int64_t door_orientation_revision() const;
    godot::Dictionary door_orientation(const godot::Vector3i& tile) const;
    godot::Dictionary presentation_perf_stats() const;
    godot::Dictionary profiling_trace() const;
    godot::Dictionary engine_submission_stats() const;
    godot::Dictionary engine_submission_details();
    godot::Dictionary profiling_render_sync();
    godot::Dictionary profiling_cpu_clock() const;
    godot::Dictionary profiling_render_boundary(bool enqueue);
    double profiling_clock_usec() const;
    godot::Dictionary wall_top_cache_stats() const;
    godot::Dictionary buffered_state() const;
    bool layout_matches_reference() const;
    void set_presentation_region(godot::Rect2i region);
    int presentation_art_margin() const;
    void clear_layout_cache();
    godot::PackedVector3Array unit_cutout_positions() const { return unitCutoutPositions_; }
    godot::PackedFloat32Array unit_thicknesses() const { return unitThicknesses_; }
    godot::PackedColorArray unit_colors() const { return colors_; }
    godot::PackedInt64Array unit_ids() const { return ids_; }
    // Existing semantic JobKind values, aligned with unit_ids() and evaluated
    // at the same delayed render tick as positions. No per-unit query needed.
    godot::PackedInt32Array unit_jobs() const { return unitJobs_; }
    godot::PackedInt64Array unit_status_flags() const { return unitStatusFlags_; }
    godot::PackedColorArray unit_motion_from() const { return unitMotionFrom_; }
    godot::PackedColorArray unit_motion_to() const { return unitMotionTo_; }
    godot::PackedVector2Array unit_motion_epochs() const { return unitMotionEpochs_; }
    godot::Dictionary unit_render_delta(int64_t since) const;
    // Model-classified motion, same order/tick; Hold, Continuous,
    // ZTransition, Fall, Teleport (wm::SegmentKind).
    godot::PackedInt32Array unit_motion_segments() const { return unitMotionSegments_; }
    godot::Array unit_combat_events(int64_t after_id = 0) const;
    godot::Array effect_events(int64_t after_id = 0) const;
    godot::Dictionary effect_event_stats() const;
    godot::PackedInt64Array projectile_ids() const { return projectileIds_; }
    godot::PackedVector3Array projectile_positions() const { return projectilePositions_; }
    godot::PackedVector3Array projectile_directions() const { return projectileDirections_; }
    godot::Array projectile_release_events(int64_t after_id = 0) const;
    godot::PackedInt32Array unit_attack_ids() const { return unitAttackIds_; }
    godot::PackedInt32Array unit_attack_targets() const { return unitAttackTargets_; }
    int unit_count() const { return static_cast<int>(ids_.size()); }
    godot::String unit_species(int64_t unit_id) const;
    // Simple-format sprite per unit: slot (-1 = none), region (u0, v0, du, dv), size in tiles.
    godot::PackedInt32Array unit_sprite_slots() const { return spriteSlots_; }
    godot::PackedColorArray unit_sprite_regions() const { return spriteRegions_; }
    godot::PackedVector2Array unit_sprite_sizes() const { return spriteSizes_; }
    godot::PackedColorArray unit_scale_params() const { return unitScaleParams_; }
    // Unit draw kind: 0 cube, 1 simple sprite, 2 composite, 3 composite pending, 4 classic glyph.
    godot::PackedInt32Array unit_sprite_kinds() const { return spriteKinds_; }

    // --- classic glyph fallback ---
    // Units drawn as their creature's classic glyph over the last poll().
    int unit_glyph_count() const { return glyphUnits_; }
    // Item counts over the last rebuild by art source (composite, body part, web, glyph, budget-deferred).
    int item_composited_count() const { return compositeItems_; }
    int item_piece_count() const { return pieceItems_; }
    int item_web_count() const { return webItems_; }
    int item_glyph_count() const { return glyphItems_; }
    int item_composite_pending_count() const { return itemCompositePending_; }
    // Buildings without art drawn as classic glyphs (not counted unresolved).
    int building_glyph_count() const { return buildingsGlyph_; }
    int64_t item_appearance_event_count() const { return itemAppearanceEvents_; }
    // "curses_640x300.png 8x12 (data/init/init_default.txt FONT), colours
    // from install" or why the fallback is off.
    godot::String glyph_summary() const;
    // How each item is drawn: 0 marker, 1 sprite, 2 composite, 3 body part /
    // bone pile, 4 classic glyph, 5 web.
    godot::PackedByteArray item_ground_flags() const { return itemGroundFlags_; }

    godot::Vector3i map_size() const;
    // Selected-level overview, DF x/y dimensions; cached and hidden-safe.
    godot::Dictionary minimap_data(int z, int resolution = 256);
    godot::Dictionary auxiliary_cache_stats() const;
    int64_t bridge_tick() const;
    double render_tick() const { return renderTick_; }

    // --- terrain ---
    int64_t session_generation() const { return static_cast<int64_t>(source_.model().sessionGeneration()); }
    bool terrain_loaded() const { return source_.model().hasTerrain(); }
    int64_t known_block_count() const { return static_cast<int64_t>(source_.model().knownBlockCount()); }
    int64_t map_block_count() const { return static_cast<int64_t>(source_.model().mapBlockCount()); }
    // Blocks currently carrying a mesh node / blocks waiting to be (re)built.
    int built_block_count() const { return meshCount_; }
    int pending_block_count() const { return static_cast<int>(queue_.size() - queueHead_) + terrainBatches_.pending(); }
    int64_t face_count() const { return faceCount_; }
    double last_build_ms() const { return lastBuildMs_; }
    double total_build_ms() const { return totalBuildMs_; }
    // z-slice: only blocks with z <= top_z are built; the layer at top_z
    // shows its tops. -1 until terrain arrives (then suggest_top_z()).
    void set_top_z(int z);
    int get_top_z() const { return topZ_; }
    // z with the most present units at the last poll (map top if none).
    int suggest_top_z() const;
    void set_window_depth(int levels);
    int get_window_depth() const { return windowDepth_; }
    void set_reveal_hidden(bool reveal);
    bool get_reveal_hidden() const { return revealHidden_; }
    // Hide units above top_z (default on) so they do not float over the cut.
    void set_slice_units(bool enabled) { sliceUnits_ = enabled; lastRenderedTick_ = UINT64_MAX; }
    void set_terrain_root(godot::Node3D* root);
    godot::Node3D* get_terrain_root();
    static double floor_height();

    // --- buildings and map items --- one ArrayMesh per building under the building root; items are billboards rebuilt on table/slice change.
    void set_building_root(godot::Node3D* root);
    godot::Node3D* get_building_root();
    void set_zone_overlays_visible(bool visible);
    int building_drawn_count() const { return buildingsDrawn_; }
    int building_unresolved_count() const { return buildingsUnresolved_; }
    int building_pending_count() const {
        return static_cast<int>(buildingQueue_.size() - buildingQueueHead_) + buildingBatches_.pending();
    }
    double building_last_ms() const { return buildingLastMs_; }
    double building_total_ms() const { return buildingTotalMs_; }
    int item_drawn_count() const { return itemsDrawn_; }
    int item_unresolved_count() const { return itemsUnresolved_; }
    double item_last_ms() const { return itemLastMs_; }
    int64_t building_event_count() const { return buildingEvents_; }
    int64_t item_event_count() const { return itemEvents_; }
    // Wall time per poll() spent building building meshes (default 6 ms;
    // <= 0 = unbounded); the rest of the queue waits for the next poll.
    void set_entity_budget_ms(double ms) { entityBudgetMs_ = ms; }
    // "Shop:3 | Meat:12 Fish:2": unresolved buildings / items by kind.
    godot::String entity_unresolved_summary() const;
    // Visible layer arrays, not all semantic items: capped reps may repeat an
    // ID for stack quantity. items_at_tile always returns the complete list.
    godot::PackedVector3Array item_positions() const { return itemPositions_; }
    godot::PackedFloat32Array item_thicknesses() const { return itemThicknesses_; }
    godot::PackedFloat32Array item_stack_ordinals() const { return itemStackOrdinals_; }
    godot::Dictionary item_physical_layout() const;
    godot::PackedInt32Array unit_stack_ordinals() const { return unitStackOrdinals_; }
    godot::PackedVector3Array unit_stack_tiles() const { return unitStackTiles_; }
    int64_t stack_atlas_revision() const { return int64_t(stackAtlas_.revision); }
    godot::Vector3 ground_support(godot::Vector3 position) const;
    godot::Vector3 unit_ground_support(int index) const;
    void configure_stack_material(const godot::Ref<godot::ShaderMaterial>& material) const { stackAtlas_.configure(material); }
    godot::PackedInt64Array item_ids() const { return itemIds_; }
    godot::PackedInt32Array item_sprite_slots() const { return itemSlots_; }
    godot::PackedColorArray item_sprite_regions() const { return itemRegions_; }
    godot::PackedVector2Array item_sprite_sizes() const { return itemSizes_; }
    godot::PackedColorArray item_colors() const { return itemColors_; }

    // --- commands --- each send returns seq (> 0) or 0 with last_error(); Rect2i in DF tile coords on one z; DIG_*/SMOOTH_*/FLAG_* constants.
    int64_t send_set_pause(bool paused);
    int64_t designate_dig(const godot::Rect2i& rect, int z, int kind, int priority, bool marker, int mining_mode, int max_z);
    int64_t designate_stairs(const godot::Rect2i& rect, int z1, int z2, int priority, bool marker);
    godot::Array preview_track(const godot::Rect2i& rect, int z, bool from_east, bool from_south, int end_z) const;
    int64_t designate_track(const godot::Rect2i& rect, int z, bool from_east, bool from_south, int priority, bool marker, int end_z);
    int64_t designate_smooth(const godot::Rect2i& rect, int z, int kind, int priority, bool marker, int max_z);
    int64_t designate_chop(const godot::Rect2i& rect, int z, bool enable, int priority, bool marker, int max_z);
    int64_t designate_gather(const godot::Rect2i& rect, int z, bool enable, int priority, bool marker, int max_z);
    int64_t set_item_flags(int64_t item, int forbidden, int dump, int melt);
    int64_t set_building_flags(int64_t building, int forbidden);
    // Results since the last call: Array of {seq, status, message, tick} in arrival order.
    godot::Array drain_command_results();

protected:
    static void _bind_methods();

private:
    struct ResidentIconMemo {
        wm::SelectionAppearance source;
        godot::Ref<godot::Texture2D> texture;
        uint64_t used=0;
    };
    std::map<std::string, godot::Ref<godot::Texture2D>> uiTextures_;
    wm::ResidentInfoService residentInfo_;
    wm::CreatureInfoService creatureInfo_;
    std::shared_ptr<const wm::CreaturePublication> creatureInfoConverted_;
    godot::Dictionary creatureInfoRows_;
    std::shared_ptr<const wm::ResidentInfoSnapshot> residentInfoConverted_;
    godot::Dictionary residentInfoRows_;
    uint64_t residentInfoLastUpdateUs_=0;
    std::unordered_map<int32_t,ResidentIconMemo> residentIcons_;
    std::shared_ptr<const wm::ResidentInfoSnapshot> residentIconPublication_;
    uint64_t residentIconUse_=0;
    std::unique_ptr<wm::ManagementClient> managementClient_;
    std::unique_ptr<wm::SessionClient> sessionClient_;

    struct Built {
        godot::MeshInstance3D* node = nullptr;  // null when the block meshed to nothing
        uint64_t version = 0;
        int32_t topZ = 0;  // top_z the mesh was built against
        int64_t unresolved = 0, textured = 0, hidden = 0;
    };

    // A loaded (page, palette row, fill) texture variant.
    using TextureSlot = SpriteResources::TextureSlot;
    // A resolved terrain face: which slot and pixel rectangle, and how to draw it.
    struct FaceLook {
        int slot = -1;  // -1 = unresolved (placeholder)
        float u0 = 0, v0 = 0, u1 = 1, v1 = 1;
        bool cutout = false;
    };
    struct PreparedUnitArt {
        UnitArtKey key;
        bool baby=false;
        int slot=-1, kind=0;
        godot::Color color, region, scale;
        godot::Vector2 size{1,1};
        bool ready=false;
    };
    std::unordered_map<wm::UnitId,PreparedUnitArt> unitArtCache_;
    uint64_t unitArtGeneration_=0, unitArtHits_=0, unitArtMisses_=0;
    const PreparedUnitArt& prepareUnitArt(wm::UnitId id,
        std::chrono::steady_clock::time_point deadline,bool allowOne);
    struct UnitLook {
        int slot = -1;
        godot::Color region;
        godot::Vector2 size{1, 1};
    };
    // One composited appearance version: its texture slot (page -1) or the
    // failure that keeps the unit on its fallback.
    using CompositeSlot = SpriteResources::CompositeSlot;
    enum SurfaceKind : uint8_t {
        kSurfOpaque = 0,
        kSurfCutout,
        kSurfWater,
        kSurfMagma,
        kSurfDecal,  // building tiles: alpha-scissored, back-culled quads
        kSurfGhost,  // planned buildings: translucent
        kSurfHidden,  // the undisclosed mass: solid black
    };
    struct SurfaceKey {
        int slot;  // -1 = untextured placeholder
        SurfaceKind kind;
        int spatterSlot = -1;
        bool operator<(const SurfaceKey& o) const {
            return slot != o.slot ? slot < o.slot : kind != o.kind ? kind < o.kind : spatterSlot < o.spatterSlot;
        }
    };

    MeshBatches terrainBatches_{0,"terrain"};
    MeshBatches buildingBatches_{30,"building"};
    std::map<SurfaceKey, godot::Ref<godot::ShaderMaterial>> buildingPieceMaterials_;
    double nowSeconds() const;
    int slotFor(int page, int paletteRow, bool fill);
    int wallTopSlotFor(const df3d::assets::TerrainSprite& wall, uint8_t neighbors);
    godot::Ref<godot::Image> pageImage(int page);
    const FaceLook& lookFor(const df3d::mesher::FaceTag& tag);
    FaceLook spatterLookFor(wm::TilePos pos);
    const UnitLook& unitLookFor(const std::string& species);
    // The decoded page / palette image behind an absolute path (cached;
    // nullptr when unreadable). Feeds the compositor.
    const df3d::assets::RgbaImage* rawImage(const std::string& absPath);
    df3d::assets::CompositeContext compositeContext();
    wm::SelectionAppearance selectionPortraitSource_;
    godot::Ref<godot::Texture2D> selectionPortraitTexture_;
    // Composite for a version, building it (within `deadline` unless
    // `force`) on first use. Returns nullptr when deferred by the budget.
    const CompositeSlot* compositeFor(uint32_t version,
                                      const std::vector<wm::AppearanceLayer>& layers,
                                      std::chrono::steady_clock::time_point deadline, bool force);
    godot::Ref<godot::Material> materialFor(const SurfaceKey& key);
    void updateTerrain();
    void resetTerrain();
    void enqueue(wm::BlockPos p);
    void enqueueWindow();
    void buildBlock(wm::BlockPos p);
    void freeBlock(Built& b);
    void ensureMaterials();
    // Black plane under the z window so a camera inside rock never sees sky through culled bottoms.
    void updateBackdrop();
    bool inWindow(wm::BlockPos p) const;
    static uint64_t key(wm::BlockPos p);

    // entities
    struct BuiltBuilding {
        wm::BuildingId id = 0;
        godot::MeshInstance3D* node = nullptr;
        uint64_t version = 0;
        uint64_t lastBuildPoll = UINT64_MAX;
        submission::GeometryFingerprint submissionFingerprint;
        int32_t z = 0;
        bool unresolved = false;
        bool glyph = false;  // drawn as a classic glyph
        wm::BuildingKind kind = wm::BuildingKind::Unknown;
    };
    struct ItemLook {
        int slot = -1;  // -1 = unresolved (marker)
        godot::Color region;
        godot::Vector2 size{1, 1};
        const char* rule = "none";
        int kind = 0;  // item_sprite_kinds value
        std::optional<ItemGlyphDependency> glyphDependency;
        std::string glyphCacheKey;
        std::optional<wm::CreatureGlyph> creatureDependency;
    };
    // A texture slot holding the classic tileset rendered in one colour
    // triple; the glyph's cell is its region.
    int glyphSlotFor(uint8_t fg, uint8_t bg, uint8_t bright);
    bool glyphsReady() const { return glyphs_.ready(); }
    void loadGlyphTileset();
    // Region + size of a code point in a glyph sheet slot.
    godot::Color glyphRegion(uint8_t tile) const;
    godot::Vector2 glyphSize() const;
    const ItemLook* unitGlyphLookFor(const std::string& species);
    void updateEntities();
    void drainBuildingGeometry();
    void flushPresentationGeometry();
    void resetEntities();
    std::map<wm::BuildingId,uint32_t> buildingSubmissionReasons_;
    void enqueueBuilding(wm::BuildingId id, uint32_t reason = 0);
    void enqueueBuildingWindow();
    void buildBuilding(wm::BuildingId id, uint32_t reason = 0);
    void freeBuilding(BuiltBuilding& b);
    bool tileVisible(wm::TilePos p) const;
    const ItemLook& itemLookFor(const wm::MapItem& it);
    void updateItems();
    godot::Array corpse_item_changes();
    godot::Array projectile_combat_events(int64_t after_id) const;
    godot::Dictionary projectile_combat_stats() const;
    godot::Array resolved_attack_events(int64_t after_id) const;
    godot::Dictionary resolved_attack_stats() const;
    godot::Array item_contact_events(int64_t after_id) const;
    godot::Dictionary item_contact_stats() const;
    void set_hidden_corpses(const godot::PackedInt64Array& ids);
    void refreshGlyphDependencies();
    void detachItemGlyphOwner(wm::ItemId id);
    void resetItemPayloads();
    void markItemInstanceChanged(int index);
    void removeItemInstance(int index);
    void adjustItemCounters(int index, int delta);
    void syncLayoutBuilding(wm::BuildingId id);
    void syncLayoutItem(wm::ItemId id);
    void applyTileLayout(df3d::mesher::DepthTile tile, bool forceItems = false);
    void resetLayoutScope();
    void refreshTerrainSupport(wm::BlockPos block, bool invalidateBuildings = true);
    void updatePresentationLayout();
    godot::Vector3 unitCutoutPosition(int index, float bottom) const;
    void updateUnitCutoutPositions();
    static constexpr float kUnitCubeHalfHeight = 0.4f;
    using PerfScope = df3d::profiling::Scope;
    struct BuildingDrawFootprint {
        uint64_t version = 0;
        df3d::assets::BuildingSprites artwork;
        std::vector<std::pair<int,int>> cells, foreground;
    };
    BuildingDrawFootprint resolveBuildingFootprint(const wm::Building& building);
    std::map<wm::BuildingId,BuildingDrawFootprint> buildingFootprintCache_;
    struct BuildingAlphaRegion {
        std::vector<uint8_t> pixels;
        bool geometryOpaque = false, footprintOpaque = false;
        // Bounded variants of this immutable image's own-art boundary joins.
        using CoverKey=std::vector<std::tuple<int,int,float,float>>;
        mutable std::map<CoverKey,std::vector<df3d::mesher::CutoutVertex>> contours;
    };
    using BuildingAlphaKey = std::tuple<int,int,int,int,int>; // slot, pixel rectangle
    struct BuildingAlphaEntry {
        std::shared_ptr<const BuildingAlphaRegion> region;
        std::list<BuildingAlphaKey>::iterator recent;
    };
    std::shared_ptr<const BuildingAlphaRegion> buildingAlphaRegion(int slot,int x,int y,int width,int height);
    std::map<BuildingAlphaKey,BuildingAlphaEntry> buildingAlphaCache_;
    std::list<BuildingAlphaKey> buildingAlphaRecent_;
    uint64_t perfBuildingArtHits_=0, perfBuildingAlphaHits_=0, perfBuildingAlphaMisses_=0, perfBuildingAlphaEvictions_=0;
    uint64_t perfPollCount_=0, perfUnitCount_=0, perfDepthCount_=0, perfItemCount_=0;
    uint64_t perfFootprintHits_=0, perfFootprintMisses_=0, perfAlphaPixels_=0;
    uint64_t perfFootprintEvictions_=0, perfFootprintResets_=0;
    double perfPollMs_=0, perfUnitMs_=0, perfDepthMs_=0, perfFootprintMs_=0;
    double perfDepthBuildingMs_=0, perfItemMs_=0;
    double perfAdoptionMs_=0, perfTerrainUpdateMs_=0, perfEntityUpdateMs_=0, perfBatchFlushMs_=0;
    double perfBuildingDrainMs_=0;
    uint64_t perfBuildingBuilds_=0, perfBuildingDuplicateBuilds_=0;
    df3d::mesher::LazyTileLayoutCache tileLayouts_{8192};
    LayoutCausalProbe layoutCausalProbe_;
    bool layoutScopeDirty_ = true;
    bool layoutViewDirty_ = true;
    bool presentationRegionEnabled_ = false;
    godot::Rect2i presentationRegion_;
    mutable int presentationArtMargin_ = 2;
    mutable uint64_t presentationArtHash_ = UINT64_MAX, presentationAppearanceVersion_ = UINT64_MAX;
    bool presentationTileDemanded(wm::TilePos p) const {
        return !presentationRegionEnabled_ || presentationRegion_.has_point(godot::Vector2i(p.x,p.y));
    }
    std::set<wm::BuildingId> layoutBuildingChanges_;
    using LayoutBlock = std::tuple<int,int,int>;
    std::map<wm::BuildingId,std::set<LayoutBlock>> layoutBuildingBlocks_;
    std::map<LayoutBlock,std::set<wm::BuildingId>> layoutBuildingsByBlock_;
    TerrainVisibilityDependencies terrainVisibilityDependencies_;
    std::unordered_map<uint64_t, std::array<uint64_t,4>> spatterEdges_;
    std::set<wm::ItemId> layoutItemChanges_;
    std::map<wm::UnitId, wm::TilePos> layoutUnitTiles_;
    std::map<wm::UnitId, df3d::mesher::DepthInterval> unitDepthById_;
    std::map<wm::ItemId, std::vector<int>> itemInstanceIndices_;
    std::vector<std::tuple<int64_t,int,int,int>> depthUnitContents_;
    int compositeBuildingTile(const std::vector<std::pair<int, godot::Color>>& layers);
    godot::PackedVector3Array unitCutoutPositions_;
    std::vector<float> unitDepthBottoms_;
    godot::PackedFloat32Array unitThicknesses_;
    godot::PackedInt32Array unitStackOrdinals_;
    godot::PackedVector3Array unitStackTiles_;
    std::map<wm::UnitId,float> unitStackOrdinalById_;
    SharedStackAtlas stackAtlas_;
    df3d::mesher::TerrainSupportDependencies terrainSupportDependencies_;
    uint64_t supportBlocksChecked_=0,supportBlocksSkipped_=0,supportTilesEvaluated_=0,supportTilesChanged_=0;
    bool zInWindow(int32_t z) const { return z <= topZ_ && z > topZ_ - windowDepth_; }

    godot::Node3D* buildingRoot_ = nullptr;
    bool zoneOverlaysVisible_ = false;
    bool ownBuildingRoot_ = false;
    std::unordered_map<wm::BuildingId, BuiltBuilding> builtBuildings_;
    std::vector<wm::BuildingId> buildingQueue_;
    size_t buildingQueueHead_ = 0;
    std::unordered_set<wm::BuildingId> buildingQueued_;
    std::unordered_map<std::string, ItemLook> itemLooks_;
    std::unordered_map<std::string, ItemLook> unitGlyphLooks_;
    uint64_t glyphVersionSeen_ = 0;
    bool glyphKnownSeen_ = false;
    std::unordered_map<std::string, std::set<wm::ItemId>> itemGlyphOwners_;
    std::unordered_map<wm::ItemId, std::string> itemGlyphOwnerKeys_;
    std::map<std::string, int> unresolvedBuildingKinds_, unresolvedItemKinds_;
    df3d::assets::GlyphRenderer glyphs_;
    bool glyphTried_ = false;
    std::string glyphWhy_;  // why the tileset is not loaded ("" when it is)
    std::map<int, int> glyphSlots_;  // fg | bg << 3 | bright << 6 -> texture slot
    int glyphUnits_ = 0, glyphItems_ = 0, buildingsGlyph_ = 0;
    int compositeItems_ = 0, pieceItems_ = 0, webItems_ = 0, itemCompositePending_ = 0;
    int64_t itemAppearanceEvents_ = 0;
    godot::PackedInt32Array itemKinds_;
    godot::PackedByteArray itemGroundFlags_;
    godot::PackedInt64Array projectileIds_;
    godot::PackedVector3Array projectilePositions_, projectileDirections_;
    double entityBudgetMs_ = 6.0;
    int buildingsDrawn_ = 0, buildingsUnresolved_ = 0;
    double buildingLastMs_ = 0.0, buildingTotalMs_ = 0.0;
    int itemsDrawn_ = 0, itemsUnresolved_ = 0;
    double itemLastMs_ = 0.0;
    int64_t buildingEvents_ = 0, itemEvents_ = 0;
    bool itemsDirty_ = true;
    std::set<wm::ItemId> itemUpdateIDs_;
    godot::Array corpseItemChanges_;
    std::set<wm::ItemId> hiddenCorpses_;
    std::map<wm::ItemId, int> pendingItemComposites_;
    std::vector<int> itemInstanceOrdinals_;
    std::vector<std::string> itemUnresolvedNames_;
    uint64_t itemUpdateCount_ = 0, itemGroupBuildCount_ = 0, itemGroupMemberChecks_ = 0;
    godot::PackedVector3Array itemPositions_;
    godot::PackedFloat32Array itemThicknesses_;
    godot::PackedFloat32Array itemStackOrdinals_;
    godot::PackedInt64Array itemIds_;
    godot::PackedInt32Array itemSlots_;
    godot::PackedColorArray itemRegions_;
    godot::PackedVector2Array itemSizes_;
    godot::PackedColorArray itemColors_;
    using ItemRenderGroupKey = std::tuple<int, float, float, float, float, int, int, int>;
    // Stable world-space groups enable engine culling without camera-driven residency changes.
    bool spatialItemBatches_ = true;
    int itemCellXY_ = 32, itemCellZ_ = 1;
    struct ItemRenderGroup {
        ItemGroupMembers members;
        uint64_t revision = 0, key = 0;
        godot::Dictionary record;
        godot::PackedInt32Array indices;
        godot::PackedInt64Array ids;
        godot::PackedVector3Array positions;
        godot::PackedVector2Array sizes;
        godot::PackedFloat32Array thicknesses;
        godot::PackedFloat32Array stackOrdinals;
        godot::PackedColorArray colors;
        godot::PackedByteArray groundFlags;
    };
    std::map<ItemRenderGroupKey, ItemRenderGroup> itemRenderGroups_;
    std::vector<std::optional<ItemRenderGroupKey>> itemInstanceGroupKeys_;
    std::set<ItemRenderGroupKey> dirtyItemGroups_;
    bool itemGroupsNeedReseed_ = true;
    godot::Array itemRenderGroupRecords_;
    // Only the latest publication is retained. Lagged readers resynchronize
    // from the full manifest instead of growing an unbounded change journal.
    godot::Array itemRenderGroupDelta_;
    godot::PackedInt64Array itemRenderGroupRemoved_;
    uint64_t itemRenderGroupDeltaBase_ = UINT64_MAX;
    uint64_t itemRenderGroupsSeen_ = UINT64_MAX, itemRenderGroupsGeneration_ = UINT64_MAX;
    uint64_t itemRenderGroupRevision_ = 0, itemRenderGroupKey_ = 0;
    using SpriteCeilingCell = std::tuple<int, int, int>;
    mutable SpriteCeilingCache spriteCeilingCache_;
    void resetSpriteCeilingCache() const;
    mutable std::map<SpriteCeilingCell, int> doorOrientationCells_;
    mutable uint64_t doorOrientationRevision_ = 0, doorOrientationTerrain_ = UINT64_MAX;
    mutable std::tuple<uint64_t, int, int, bool> doorOrientationScope_{UINT64_MAX, -1, -1, false};
    void resetDoorOrientationCache() const;
    void ensureDoorOrientationScope() const;
    int doorCellClass(int x, int y, int z) const;
    SpriteCeilingCache::Result spriteCeilingQuery(const godot::AABB& bounds, int floorZ) const;

    wm::WorldSource source_;
    uint64_t sessionSeen_ = 0;
    std::chrono::steady_clock::time_point epoch_ = std::chrono::steady_clock::now();
    godot::String lastError_;

    SpriteResources spriteResources_;
    void collectAppearanceResources();

    // assets
    std::unique_ptr<df3d::assets::Provider> assets_;
    godot::String assetsError_;
    std::map<std::tuple<int, int, bool>, int> slotIndex_;
    std::map<std::tuple<int, int, int, int, uint8_t>, int> wallTopIndex_;
    df3d::assets::BitmapSlots wallTopBitmaps_;
    godot::Color rockBackingColor_{64.0f / 255.0f, 64.0f / 255.0f, 64.0f / 255.0f, 1.0f};
    bool rockBackingReady_ = false;
    std::unordered_map<int, godot::Ref<godot::Image>> pageImages_;
    godot::Ref<godot::Image> paletteImage_;
    bool paletteTried_ = false;
    godot::Ref<godot::ImageTexture> minimapTexture_;
    df3d::mesher::LevelBlockRevision minimapLevel_;
    mutable df3d::mesher::LevelBlockRevision designationLevel_;
    mutable godot::Array designationTiles_;
    std::vector<int8_t> minimapPixels_;
    int minimapZ_ = -1, minimapResolution_ = 0;
    uint64_t minimapBuilds_ = 0;
    uint64_t minimapCacheHits_ = 0, minimapSamples_ = 0, minimapEvaluations_ = 0;
    mutable uint64_t designationBuilds_ = 0, designationCacheHits_ = 0, designationSamples_ = 0;
    std::unordered_map<uint64_t, FaceLook> faceLooks_;
    std::unordered_map<std::string, UnitLook> unitLooks_;
    std::unordered_map<std::string, std::unique_ptr<df3d::assets::RgbaImage>> rawImages_;
    double compositeBudgetMs_ = 8.0;
    double compositeLastMs_ = 0.0, compositeTotalMs_ = 0.0;
    int compositeBuildCount_ = 0, compositeFailed_ = 0, compositePending_ = 0;
    int compositedUnits_ = 0, simpleUnits_ = 0, cubeUnits_ = 0;
    int compositeWhyPrinted_ = 0;
    int64_t appearanceEvents_ = 0;
    std::map<SurfaceKey, godot::Ref<godot::Material>> materials_;
    // Terrain shaders: unshaded, both sides drawn, back faces solid
    // black so a camera clipped into rock sees black, not the rooms beyond.
    godot::Ref<godot::Shader> terrainShader_, terrainCutoutShader_;
    int64_t unresolvedFaces_ = 0;
    int64_t texturedFaces_ = 0;
    int64_t hiddenFaces_ = 0;

    // units
    double renderTick_ = 0.0;
    uint64_t lastRenderedTick_ = UINT64_MAX;
    // Presentation arrays have independent lifetimes: moving units can change
    // item heights, while an unchanged paused frame changes neither.
    uint64_t unitRenderRevision_ = 0;
    uint64_t itemRenderRevision_ = 0;
    godot::PackedVector3Array positions_;
    godot::PackedColorArray colors_;
    godot::PackedInt64Array ids_;
    godot::PackedInt32Array unitJobs_;
    godot::PackedInt64Array unitStatusFlags_;
    godot::PackedColorArray unitMotionFrom_, unitMotionTo_;
    godot::PackedVector2Array unitMotionEpochs_;
    struct UnitVisualKey {
        godot::Color from, to, region, scale, color;
        godot::Vector2 epochs, size;
        godot::Vector3 stackTile;
        int slot = -1, job = 0, segment = 0, attack = -1, target = -1, ordinal = 0;
        uint64_t statusFlags = 0;
        bool operator==(const UnitVisualKey&) const = default;
    };
    std::unordered_map<wm::UnitId, UnitVisualKey> unitVisualKeys_;
    godot::PackedInt32Array unitChangedIndices_;
    godot::PackedInt64Array unitRemovedIds_;
    uint64_t unitDeltaBase_ = 0;
    void updateUnitVisualChanges();
    godot::PackedInt32Array unitMotionSegments_;
    godot::PackedInt32Array unitAttackIds_, unitAttackTargets_;
    godot::PackedInt64Array unitAttackTicks_;
    godot::PackedInt32Array spriteSlots_;
    godot::PackedColorArray spriteRegions_;
    godot::PackedVector2Array spriteSizes_;
    godot::PackedColorArray unitScaleParams_;
    godot::PackedInt32Array spriteKinds_;

    // terrain
    godot::Node3D* terrainRoot_ = nullptr;
    bool ownRoot_ = false;
    godot::MeshInstance3D* backdrop_ = nullptr;
    int32_t backdropTopZ_ = -1, backdropDepth_ = 0;
    int32_t topZ_ = -1;
    int32_t windowDepth_ = 24;
    bool revealHidden_ = false;
    bool sliceUnits_ = true;
    int buildBudget_ = 256;
    wm::TilePos builtMapSize_;
    std::unordered_map<uint64_t, Built> built_;
    std::vector<wm::BlockPos> queue_;
    size_t queueHead_ = 0;
    std::unordered_set<uint64_t> queued_;
    int meshCount_ = 0;
    int64_t faceCount_ = 0;
    double lastBuildMs_ = 0.0;
    double totalBuildMs_ = 0.0;
};

}  // namespace df3d_godot
