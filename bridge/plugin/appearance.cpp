#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "appearance.h"
#include "dwarf_layer_anatomy.h"

#include "modules/DFSDL.h"
#include "modules/Filesystem.h"
#include "modules/Materials.h"
#include "modules/Units.h"

#include "df/appearance_modifier_type.h"
#include "df/bp_appearance_modifier.h"
#include "df/body_part_raw.h"
#include "df/caste_body_info.h"
#include "df/caste_raw.h"
#include "df/cgl_bp_conditionst.h"
#include "df/cgl_itemst.h"
#include "df/cgl_tissue_layer_conditionst.h"
#include "df/cgl_tissue_layer_swapst.h"
#include "df/color_modifier_raw.h"
#include "df/creature_graphics_layer_materialst.h"
#include "df/creature_graphics_layer_setst.h"
#include "df/creature_graphics_layerst.h"
#include "df/creature_graphics_role.h"
#include "df/creature_raw.h"
#include "df/creature_raw_graphics.h"
#include "df/descriptor_color.h"
#include "df/descriptor_handlerst.h"
#include "df/descriptor_pattern.h"
#include "df/enabler.h"
#include "df/global_objects.h"
#include "df/graphic.h"
#include "df/graphic_viewportst.h"
#include "df/historical_figure.h"
#include "df/item.h"
#include "df/item_body_component.h"
#include "df/item_corpsest.h"
#include "df/job_item.h"
#include "df/material.h"
#include "df/palette_pagest.h"
#include "df/palette_rowst.h"
#include "df/syndrome.h"
#include "df/texture_handlerst.h"
#include "df/tile_pagest.h"
#include "df/unit.h"
#include "df/unit_inventory_item.h"
#include "df/unit_syndrome.h"
#include "df/unit_wound.h"
#include "df/unit_wound_layerst.h"
#include "df/world.h"

#include <algorithm>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

using namespace DFHack;
using df::global::enabler;
using df::global::gps;
using df::global::texture;
using df::global::world;

namespace df3d_appearance {

namespace {

// ---- texpos -> (page, tile) map ----

struct TexRef {
    int32_t page = -1;   // index into texture->page
    int32_t index = -1;  // index into page->texpos (row-major tile index)
};
std::vector<TexRef> g_texmap;
size_t g_texmapRaws = 0;

void ensureTexposMap() {
    if (!texture || !enabler) return;
    const size_t n = enabler->textures.raws.size();
    if (!g_texmap.empty() && g_texmapRaws == n) return;
    g_texmap.assign(n, TexRef{});
    g_texmapRaws = n;
    for (size_t pi = 0; pi < texture->page.size(); ++pi) {
        const df::tile_pagest* p = texture->page[pi];
        if (!p) continue;
        for (size_t k = 0; k < p->texpos.size(); ++k) {
            const long t = p->texpos[k];
            if (t < 0 || static_cast<size_t>(t) >= n) continue;
            if (g_texmap[t].page < 0) g_texmap[t] = TexRef{static_cast<int32_t>(pi), static_cast<int32_t>(k)};
        }
    }
}

bool texposToTile(int32_t texpos, const df::tile_pagest*& page, int32_t& x, int32_t& y) {
    ensureTexposMap();
    if (texpos < 0 || static_cast<size_t>(texpos) >= g_texmap.size()) return false;
    const TexRef r = g_texmap[texpos];
    if (r.page < 0) return false;
    page = texture->page[r.page];
    const int32_t cols = page->page_dim_x > 0 ? page->page_dim_x : 1;
    x = r.index % cols;
    y = r.index / cols;
    return true;
}

// Resolves a [3][2] cell block (a layer or simple sprite) into a Layer's
// page/tile/cells. Cells are contiguous on the page; the top-left cell
// gives the tile. Returns false if cell (0,0) is not a page tile.
bool cellsToLayer(const std::array<std::array<int32_t, 2>, 3>& cells, Layer& l) {
    const df::tile_pagest* page = nullptr;
    int32_t x = 0, y = 0;
    if (!texposToTile(cells[0][0], page, x, y)) return false;
    l.page = page;
    l.tileX = static_cast<uint16_t>(x);
    l.tileY = static_cast<uint16_t>(y);
    // Unused cells hold texpos 0 (DF's blank), never a page tile.
    uint8_t cx = 1, cy = 1;
    for (int dx = 1; dx < 3; ++dx)
        if (cells[dx][0] > 0) cx = static_cast<uint8_t>(dx + 1);
    for (int dy = 1; dy < 2; ++dy)
        if (cells[0][dy] > 0) cy = static_cast<uint8_t>(dy + 1);
    l.cellsX = cx;
    l.cellsY = cy;
    return true;
}

// Diagnostic trace state (see layerPasses).
color_ostream* g_traceOut = nullptr;
std::string g_traceToken;

// ---- unit context: everything the conditions read, gathered once ----

// The subject of a resolution: a live unit, or a corpse item,
// which carries its own copies of the appearance state the conditions
// read (item_body_component::appearance / body). Everything the
// evaluators consult goes through these fields, never through `u`
// directly, except the inventory (corpses have none).
struct Ctx {
    df::unit* u = nullptr;                    // null for a corpse item
    df::item_body_component* corpse = nullptr;
    df::creature_raw* raw = nullptr;
    df::caste_raw* caste = nullptr;
    df::creature_raw_graphics* g = nullptr;
    int32_t casteIdx = -1;
    int32_t seedId = 0;        // CONDITION_RANDOM_PART_INDEX stand-in seed (unit id)
    int32_t profession = -1;   // df::profession of the unit (or the dead unit)
    bool child = false, baby = false, ghost = false, undead = false;
    int32_t haulCount = 0;
    int32_t sizeCur = 0;
    std::vector<const std::string*> synClasses;
    const std::vector<int32_t>* colors = nullptr;                 // appearance.colors
    const std::vector<df::tissue_style_type>* tissueStyle = nullptr;
    const std::vector<df::body_part_status>* bpStatus = nullptr;  // body.components.body_part_status
    const std::vector<int32_t>* bpModifiers = nullptr;            // appearance.bp_modifiers / body.bp_modifiers
    const std::vector<df::unit_wound*>* wounds = nullptr;
};

bool buildCasteCtx(Ctx& c, int32_t race, int32_t caste) {
    c.raw = df::creature_raw::find(race);
    if (!c.raw) return false;
    c.casteIdx = caste;
    c.caste = (caste >= 0 && static_cast<size_t>(caste) < c.raw->caste.size()) ? c.raw->caste[caste] : nullptr;
    if (!c.caste) return false;
    // CREATURE_CASTE_GRAPHICS override the creature's block when present.
    c.g = c.caste->caste_graphics ? c.caste->caste_graphics : c.raw->graphics;
    return c.g != nullptr;
}

bool buildCtx(df::unit* u, Ctx& c) {
    c.u = u;
    if (!buildCasteCtx(c, u->race, u->caste)) return false;
    c.seedId = u->id;
    c.profession = static_cast<int32_t>(u->profession);
    c.child = Units::isChild(u);
    c.baby = Units::isBaby(u);
    c.ghost = Units::isGhost(u);
    c.undead = u->enemy.undead;
    c.sizeCur = u->body.size_info.size_cur;
    c.colors = &u->appearance.colors;
    c.tissueStyle = &u->appearance.tissue_style;
    c.bpStatus = &u->body.components.body_part_status;
    c.bpModifiers = &u->appearance.bp_modifiers;
    c.wounds = &u->body.wounds;
    for (const df::unit_inventory_item* inv : u->inventory)
        if (inv && inv->mode == df::inv_item_role_type::Hauled) ++c.haulCount;
    for (const df::unit_syndrome* us : u->syndromes.active) {
        if (!us) continue;
        const df::syndrome* s = df::syndrome::find(us->type);
        if (!s) continue;
        for (const std::string* cls : s->syn_class) c.synClasses.push_back(cls);
    }
    return true;
}

// A corpse item as the subject: race / caste and the appearance
// copies come from the item; the dead unit's child status from the unit
// if DF still holds it (dead units stay in units.all), else from its
// historical figure's profession, else adult. The random-part seed is the
// dead unit's id so the corpse keeps the face the unit had (stand-in seed
// either way). The bridge's item shadow tells corpse pieces
// apart; here only whole corpses have a role set.
bool buildCorpseCtx(df::item_body_component* it, Ctx& c) {
    c.corpse = it;
    if (!buildCasteCtx(c, it->race, it->caste)) return false;
    c.seedId = it->unit_id;
    c.sizeCur = it->body.size_info.size_cur;
    c.colors = &it->appearance.colors;
    c.tissueStyle = &it->appearance.tissue_style;
    c.bpStatus = &it->body.components.body_part_status;
    c.bpModifiers = &it->body.bp_modifiers;
    c.wounds = &it->body.wounds;
    c.profession = -1;
    if (df::unit* u = it->unit_id >= 0 ? df::unit::find(it->unit_id) : nullptr) {
        c.child = Units::isChild(u);
        c.baby = Units::isBaby(u);
        c.profession = static_cast<int32_t>(u->profession);
    } else if (df::historical_figure* hf = it->hist_figure_id >= 0 ? df::historical_figure::find(it->hist_figure_id) : nullptr) {
        c.child = hf->profession == df::profession::CHILD;
        c.baby = hf->profession == df::profession::BABY;
        c.profession = static_cast<int32_t>(hf->profession);
    }
    return true;
}

bool hasSynClass(const Ctx& c, const std::string& cls) {
    for (const std::string* s : c.synClasses)
        if (s && *s == cls) return true;
    return false;
}

// Caste-parallel body part lists: (check_caste[k], check_bp[k]). Returns
// the matching entries' k indices for this unit's caste (all entries when
// the caste list is absent or shorter).
template <class F>
void forEachCasteEntry(const std::vector<int32_t>& castes, size_t n, int32_t casteIdx, F&& f) {
    for (size_t k = 0; k < n; ++k) {
        if (castes.size() == n && castes[k] != casteIdx) continue;
        f(k);
    }
}

// Value of the appearance modifier `type` on (bp, tl) (tl = -1: the body
// part itself). Returns false if the caste has no such modifier there.
bool bpModifier(const Ctx& c, int16_t bp, int16_t tl, df::appearance_modifier_type type, int32_t& value) {
    const auto& bpa = c.caste->bp_appearance;
    const auto& mods = *c.bpModifiers;
    for (size_t j = 0; j < bpa.modifier_idx.size() && j < bpa.part_idx.size() && j < bpa.layer_idx.size(); ++j) {
        if (bpa.part_idx[j] != bp) continue;
        if (tl >= 0 && bpa.layer_idx[j] != tl) continue;
        const int32_t mi = bpa.modifier_idx[j];
        if (mi < 0 || static_cast<size_t>(mi) >= bpa.modifiers.size()) continue;
        const df::bp_appearance_modifier* m = bpa.modifiers[mi];
        if (!m || m->modifier.type != type) continue;
        if (j >= mods.size()) return false;
        value = mods[j];
        return true;
    }
    return false;
}

// The unit's tissue style on (bp, tl); NONE when unstyled or unknown.
df::tissue_style_type tissueStyle(const Ctx& c, int16_t bp, int16_t tl) {
    const auto& bpa = c.caste->bp_appearance;
    const auto& styles = *c.tissueStyle;
    for (size_t s = 0; s < bpa.style_part_idx.size() && s < bpa.style_layer_idx.size(); ++s) {
        if (bpa.style_part_idx[s] != bp || bpa.style_layer_idx[s] != tl) continue;
        if (s >= styles.size()) return df::tissue_style_type::NONE;
        return styles[s];
    }
    return df::tissue_style_type::NONE;
}

// The descriptor colours of the unit's colour pattern on (bp, tl); empty
// if no colour modifier covers that tissue.
void tissueColors(const Ctx& c, int16_t bp, int16_t tl, std::vector<int16_t>& out) {
    out.clear();
    const auto& cms = c.caste->color_modifiers;
    const auto& sel = *c.colors;
    for (size_t i = 0; i < cms.size(); ++i) {
        const df::color_modifier_raw* cm = cms[i];
        if (!cm) continue;
        bool covers = false;
        for (size_t j = 0; j < cm->body_part_id.size() && j < cm->tissue_layer_id.size(); ++j) {
            if (cm->body_part_id[j] == bp && cm->tissue_layer_id[j] == tl) { covers = true; break; }
        }
        if (!covers) continue;
        if (i >= sel.size()) return;
        const int32_t pi = sel[i];
        if (pi < 0 || static_cast<size_t>(pi) >= cm->pattern_index.size()) return;
        const int32_t pat = cm->pattern_index[pi];
        const auto& patterns = world->raws.descriptors.patterns;
        if (pat < 0 || static_cast<size_t>(pat) >= patterns.size()) return;
        for (int16_t col : patterns[pat]->colors) out.push_back(col);
        return;
    }
}

bool tissueEntryPasses(const Ctx& c, const df::cgl_tissue_layer_conditionst& cond, int16_t bp, int16_t tl,
                       const std::array<std::array<int32_t, 2>, 3>*& swap) {
    if (g_traceOut && g_traceToken == "*tissue") {
        int32_t len = -1, den = -1, curly = -1;
        bpModifier(c, bp, tl, df::appearance_modifier_type::LENGTH, len);
        bpModifier(c, bp, tl, df::appearance_modifier_type::DENSE, den);
        bpModifier(c, bp, tl, df::appearance_modifier_type::CURLY, curly);
        std::vector<int16_t> cols;
        tissueColors(c, bp, tl, cols);
        g_traceOut->print("      tissue bp {} tl {}: len {} dense {} curly {} style {} colors {} (cond len {}..{} shapes {} notshaped {} colors {})\n", bp, tl, len, den, curly,
                          static_cast<int>(tissueStyle(c, bp, tl)), cols.size(), cond.min_length, cond.max_length, cond.required_shape.size(),
                          cond.flags.bits.requires_not_shaped, cond.color_index.size());
    }
    if (!cond.color_index.empty()) {
        std::vector<int16_t> cols;
        tissueColors(c, bp, tl, cols);
        bool any = false;
        for (int16_t col : cols)
            if (std::find(cond.color_index.begin(), cond.color_index.end(), col) != cond.color_index.end()) { any = true; break; }
        if (!any) return false;
    }
    // Length / density windows. Unset bounds are 0 (min) and a large value
    // (max) in DF's parse; a zero max means "no maximum" too (calibrated
    // against `df3d appearance layersets`).
    if (cond.min_length > 0 || (cond.max_length > 0 && cond.max_length < 1000000000)) {
        int32_t len = 0;
        if (!bpModifier(c, bp, tl, df::appearance_modifier_type::LENGTH, len)) return false;
        if (cond.min_length > 0 && len < cond.min_length) return false;
        if (cond.max_length > 0 && cond.max_length < 1000000000 && len > cond.max_length) return false;
    }
    if (cond.min_density > 0 || (cond.max_density > 0 && cond.max_density < 1000000000)) {
        int32_t den = 0;
        if (!bpModifier(c, bp, tl, df::appearance_modifier_type::DENSE, den)) return false;
        if (cond.min_density > 0 && den < cond.min_density) return false;
        if (cond.max_density > 0 && cond.max_density < 1000000000 && den > cond.max_density) return false;
    }
    if (!cond.required_shape.empty() || cond.flags.bits.requires_not_shaped) {
        const df::tissue_style_type style = tissueStyle(c, bp, tl);
        if (cond.flags.bits.requires_not_shaped && style != df::tissue_style_type::NONE) return false;
        if (!cond.required_shape.empty() &&
            std::find(cond.required_shape.begin(), cond.required_shape.end(), style) == cond.required_shape.end())
            return false;
    }
    for (const df::cgl_tissue_layer_swapst* sw : cond.swap) {
        if (!sw) continue;
        if (sw->swap_condition == df::creature_graphics_tissue_layer_swap_condition_type::IF_MIN_CURLY) {
            int32_t curly = 0;
            if (bpModifier(c, bp, tl, df::appearance_modifier_type::CURLY, curly) && curly >= sw->swap_condition_lim) {
                swap = &sw->texpos;
                break;
            }
        }
    }
    return true;
}

bool tissueConditionPasses(const Ctx& c, const df::cgl_tissue_layer_conditionst& cond,
                           const std::array<std::array<int32_t, 2>, 3>*& swap) {
    const size_t n = std::min(cond.check_bp.size(), cond.check_tl.size());
    bool any = false, pass = false;
    forEachCasteEntry(cond.check_caste, n, c.casteIdx, [&](size_t k) {
        if (pass) return;
        any = true;
        if (tissueEntryPasses(c, cond, cond.check_bp[k], cond.check_tl[k], swap)) pass = true;
    });
    return any && pass;
}

bool bpConditionPasses(const Ctx& c, const df::cgl_bp_conditionst& cond) {
    const size_t n = cond.check_bp.size();
    if (n == 0) return true;
    bool any = false, pass = false;
    const auto& status = *c.bpStatus;
    forEachCasteEntry(cond.check_caste, n, c.casteIdx, [&](size_t k) {
        if (pass) return;
        any = true;
        const int16_t bp = cond.check_bp[k];
        bool missing = false;
        if (bp >= 0 && static_cast<size_t>(bp) < status.size()) missing = status[bp].bits.missing;
        if (cond.flags.bits.present && missing) return;
        if (cond.flags.bits.missing && !missing) return;
        if (cond.flags.bits.scarred) {
            // BP_SCARRED is an additional condition, not another spelling of
            // BP_PRESENT. Ignoring it paints the portrait's head/cheek scars
            // onto every intact face. Require an actual scar on this part.
            bool scarred = false;
            if (c.wounds) for (const auto* wound : *c.wounds) {
                if (!wound) continue;
                for (const auto* part : wound->parts) {
                    if (!part || part->body_part_id != bp) continue;
                    const auto& f = part->flags1.bits;
                    scarred |= f.scar_cut || f.scar_smashed || f.scar_edged_shake1 ||
                               f.scar_broken || f.scar_blunt_shake1 || f.scar_joint_bend1;
                }
            }
            if (!scarred) return;
        }
        for (size_t m = 0; m < cond.modifier.size() && m < cond.modifier_min.size() && m < cond.modifier_max.size(); ++m) {
            int32_t v = 0;
            if (!bpModifier(c, bp, -1, cond.modifier[m], v)) return;
            if (v < cond.modifier_min[m] || v > cond.modifier_max[m]) return;
        }
        pass = true;
    });
    return any && pass;
}

bool inventoryModeMatches(const df::cgl_itemst& c, df::inv_item_role_type mode) {
    using M = df::inv_item_role_type;
    if (c.flags.bits.any_held) return mode != M::NONE;
    if (c.flags.bits.wield) return mode == M::Weapon;
    if (c.flags.bits.any_hauled) return mode == M::Hauled;
    // "Worn" in the graphics raws covers everything on the body that is
    // not being hauled: worn clothing and armour, wielded weapons and
    // shields (mode Weapon), strapped / wrapped / pierced items. Verified
    // against DF's composite: a wielded shield lights CONDITION_ITEM_WORN.
    return mode == M::Worn || mode == M::Weapon || mode == M::Piercing || mode == M::Flask ||
           mode == M::WrappedAround || mode == M::Strapped || mode == M::SewnInto;
}

const df::unit_inventory_item* findItem(const Ctx& c, const df::cgl_itemst& cond) {
    if (!c.u) return nullptr;  // corpses carry no inventory
    for (const df::unit_inventory_item* inv : c.u->inventory) {
        if (!inv || !inv->item) continue;
        if (!inventoryModeMatches(cond, inv->mode)) continue;
        df::item* it = inv->item;
        if (cond.item_type != df::item_type::NONE && it->getType() != cond.item_type) continue;
        // PROCEDURAL_<kind> conditions match by the item's procedural
        // graphics family (weapon / shield shape), not by type/subtype.
        if (cond.procedural_item_graphics != df::procedural_item_graphics_type::NONE &&
            !it->has_procedural_item_graphics(cond.procedural_item_graphics))
            continue;
        if (!cond.item_subtype.empty() &&
            std::find(cond.item_subtype.begin(), cond.item_subtype.end(), static_cast<int32_t>(it->getSubtype())) ==
                cond.item_subtype.end())
            continue;
        if (!cond.check_bp.empty()) {
            bool bpOk = false;
            forEachCasteEntry(cond.check_caste, cond.check_bp.size(), c.casteIdx, [&](size_t k) {
                if (cond.check_bp[k] == inv->body_part_id) bpOk = true;
            });
            if (!bpOk) continue;
        }
        if (cond.max_qual >= 0 && cond.max_qual < 1000000 && (it->getQuality() < cond.min_qual || it->getQuality() > cond.max_qual))
            continue;
        if (cond.max_dam_level >= 0 && cond.max_dam_level < 1000000 &&
            (it->getWear() < cond.min_dam_level || it->getWear() > cond.max_dam_level))
            continue;
        return inv;
    }
    return nullptr;
}

// CONDITION_MATERIAL_FLAG / MATERIAL_TYPE on the item matched by the first
// CONDITION_ITEM_WORN. Stored as job_item flags; flags4/5 are DF's item
// flags for ARTIFACT / WOVEN / GROWN (not in df-structures yet);
// ARTIFACT is derived from the item's own flag.
bool materialConditionPasses(const df::creature_graphics_layer_materialst& m, df::item* it) {
    if (!it) return false;
    MaterialInfo mi(it->getMaterial(), it->getMaterialIndex());
    if (!mi.isValid() || !mi.material) return false;
    const auto& mf = mi.material->flags;
    auto matFlag = [&](df::material_flags f) { return mf.is_set(f); };
    // flags1 / flags2: DFHack's job-item matcher covers the material-class
    // bits DF stores there (plant, leather, bone, shell, silk, yarn, ...).
    df::job_item_flags1 ok1, mask1;
    df::job_item_flags2 ok2, mask2;
    mi.getMatchBits(ok1, mask1);
    mi.getMatchBits(ok2, mask2);
    if ((m.flags1.whole & mask1.whole) != (m.flags1.whole & ok1.whole)) return false;
    if ((m.flags2.whole & mask2.whole) != (m.flags2.whole & ok2.whole)) return false;
    // The category bits DFHack's mask does not cover, evaluated directly.
    const auto& f2 = m.flags2.bits;
    if (f2.plant && !mi.isPlant()) return false;
    if (f2.silk && !matFlag(df::material_flags::SILK)) return false;
    if (f2.leather && !matFlag(df::material_flags::LEATHER)) return false;
    if (f2.bone && !matFlag(df::material_flags::BONE)) return false;
    if (f2.shell && !matFlag(df::material_flags::SHELL)) return false;
    if (f2.horn && !matFlag(df::material_flags::HORN)) return false;
    if (f2.pearl && !matFlag(df::material_flags::PEARL)) return false;
    if (f2.ivory_tooth && !matFlag(df::material_flags::TOOTH)) return false;
    if (f2.yarn && !matFlag(df::material_flags::YARN)) return false;
    const auto& f3 = m.flags3.bits;
    const bool artifact = it->flags.bits.artifact;
    if (f3.crafted_artifact && !artifact) return false;
    if (f3.non_artifact && artifact) return false;
    if (f3.wood && !matFlag(df::material_flags::WOOD)) return false;
    if (f3.stone && !matFlag(df::material_flags::IS_STONE)) return false;
    if (f3.gem && !matFlag(df::material_flags::IS_GEM)) return false;
    if (f3.metal && !matFlag(df::material_flags::IS_METAL)) return false;
    if (f3.hard && !matFlag(df::material_flags::ITEMS_HARD)) return false;
    if (f3.woven && !mi.isAnyCloth()) return false;
    if (f3.grown_not_crafted && !it->flags2.bits.grown) return false;
    if (!m.subcat1.empty()) {
        bool any = false;
        for (size_t i = 0; i < m.subcat1.size(); ++i) {
            const int32_t sub2 = i < m.subcat2.size() ? m.subcat2[i] : -1;
            if (m.subcat1[i] == it->getMaterial() && (sub2 < 0 || sub2 == it->getMaterialIndex())) { any = true; break; }
        }
        if (!any) return false;
    }
    return true;
}

// CONDITION_RANDOM_PART_INDEX:<name>:<index>:<max>. DF's per-unit seed for
// this is not identified yet; this deterministic
// stand-in keeps the choice stable per unit and name so the stack is at
// least consistent frame to frame. `g_randomOverride` lets the survey
// diagnostic try every index against DF's composite.
uint32_t fnv(const std::string& s) {
    uint32_t h = 2166136261u;
    for (unsigned char ch : s) h = (h ^ ch) * 16777619u;
    return h;
}
struct RandomOverride {
    const std::string* name = nullptr;
    int32_t index = 0;
};
RandomOverride g_randomOverride;

int32_t randomPartIndex(const Ctx& c, const std::string& name, int32_t max) {
    if (max <= 0) return 1;
    if (g_randomOverride.name && *g_randomOverride.name == name) return g_randomOverride.index;
    const uint32_t h = (static_cast<uint32_t>(c.seedId) * 2654435761u) ^ fnv(name);
    return static_cast<int32_t>(h % static_cast<uint32_t>(max)) + 1;
}

// The standard palette (PALETTE:DEFAULT, palettes.png): the first
// texture->palette whose token is DEFAULT, else the first palette.
const df::palette_pagest* standardPalette() {
    if (!texture) return nullptr;
    for (const df::palette_pagest* p : texture->palette)
        if (p && p->token == "DEFAULT") return p;
    return texture->palette.empty() ? nullptr : texture->palette[0];
}

int32_t paletteRowForColor(const df::palette_pagest* pal, int32_t colorIdx) {
    if (!pal) return -1;
    const auto& colors = world->raws.descriptors.colors;
    if (colorIdx >= 0 && static_cast<size_t>(colorIdx) < colors.size()) {
        const std::string& tok = colors[colorIdx]->id;
        for (size_t i = 0; i < pal->color_token.size() && i < pal->color_row.size(); ++i)
            if (pal->color_token[i] && *pal->color_token[i] == tok) return pal->color_row[i];
    }
    return pal->default_row;
}

// Diagnostic trace: when set, every failing condition of layers whose
// token matches is printed (df3d appearance <id> trace <LAYER>).
bool layerPasses(const Ctx& c, const df::creature_graphics_layer_setst& set, const df::creature_graphics_layerst& L,
                 const std::array<std::array<int32_t, 2>, 3>*& swap, const df::unit_inventory_item*& matched) {
    const bool tracing = g_traceOut && (g_traceToken == "*" || L.token.find(g_traceToken) != std::string::npos);
    auto fail = [&](const char* why) {
        if (tracing) g_traceOut->print("    trace {}: FAIL {}\n", L.token.c_str(), why);
        return false;
    };
    if (L.flags.bits.suppressed_by_load_errors) return fail("suppressed by load errors");
    if (L.flags.bits.child && !(c.child || c.baby)) return fail("CONDITION_CHILD");
    if (L.flags.bits.not_child && (c.child || c.baby)) return fail("CONDITION_NOT_CHILD");
    if (L.flags.bits.ghost && !c.ghost) return fail("CONDITION_GHOST");
    if (!L.required_caste.empty() &&
        std::find(L.required_caste.begin(), L.required_caste.end(), c.casteIdx) == L.required_caste.end())
        return fail("CONDITION_CASTE");
    if (!L.required_profession.empty() &&
        std::find(L.required_profession.begin(), L.required_profession.end(), c.profession) ==
            L.required_profession.end())
        return fail("CONDITION_PROFESSION_CATEGORY");
    for (const std::string* cls : L.required_syn_class)
        if (cls && !hasSynClass(c, *cls)) return fail("CONDITION_SYN_CLASS");
    for (size_t i = 0; i < L.random_part_condition_string.size() && i < L.random_part_condition_index.size() &&
                       i < L.random_part_condition_max.size(); ++i) {
        const std::string* name = L.random_part_condition_string[i];
        if (!name) continue;
        if (randomPartIndex(c, *name, L.random_part_condition_max[i]) != L.random_part_condition_index[i])
            return fail("CONDITION_RANDOM_PART_INDEX");
    }
    if (L.haul_min_count > 0 && c.haulCount < L.haul_min_count) return fail("CONDITION_HAUL_COUNT_MIN");
    if (L.haul_max_count > 0 && c.haulCount > L.haul_max_count) return fail("CONDITION_HAUL_COUNT_MAX");
    if (L.body_size_min > 0 && c.sizeCur < L.body_size_min) return fail("CONDITION_BODY_SIZE_MIN");
    // Item conditions. Measured against DF's composites: several
    // CONDITION_ITEM_WORN lines on one layer are alternatives (a hood
    // layer listing a cloak and a hood item draws for a cloak alone), and
    // several SHUT_OFF_IF_ITEM_PRESENT lines all have to hold to shut the
    // layer off (a cloak alone does not hide the hair that lists helms
    // and cloaks).
    if (!L.required_item.empty()) {
        bool any = false;
        for (const df::cgl_itemst* ic : L.required_item) {
            if (!ic) continue;
            const df::unit_inventory_item* inv = findItem(c, *ic);
            if (inv) {
                any = true;
                if (!matched) matched = inv;
                break;
            }
            if (tracing) {
                std::string sub, bps;
                for (int32_t v : ic->item_subtype) sub += std::to_string(v) + ",";
                for (size_t k = 0; k < ic->check_bp.size(); ++k)
                    bps += (k < ic->check_caste.size() ? std::to_string(ic->check_caste[k]) + ":" : "") + std::to_string(ic->check_bp[k]) + ",";
                g_traceOut->print("      item condition: type {} subtypes [{}] bps [{}] proc {} flags w{} h{} hl{} qual {}..{} dam {}..{}\n",
                                  static_cast<int>(ic->item_type), sub.c_str(), bps.c_str(), static_cast<int>(ic->procedural_item_graphics),
                                  ic->flags.bits.wield, ic->flags.bits.any_held, ic->flags.bits.any_hauled, ic->min_qual, ic->max_qual,
                                  ic->min_dam_level, ic->max_dam_level);
            }
        }
        if (!any) return fail("CONDITION_ITEM_WORN");
    }
    if (!L.forbidden_item.empty()) {
        bool all = true;
        for (const df::cgl_itemst* ic : L.forbidden_item) {
            if (!ic) continue;
            if (!findItem(c, *ic)) { all = false; break; }
        }
        if (all) return fail("SHUT_OFF_IF_ITEM_PRESENT");
    }
    if (L.mat && !materialConditionPasses(*L.mat, matched ? matched->item : nullptr)) return fail("CONDITION_MATERIAL_*");
    if (!L.dye_color_index.empty()) {
        if (!matched || !matched->item->isDyed()) return fail("CONDITION_DYE (not dyed)");
        const int32_t col = matched->item->getColorWhetherDyedOrNot();
        if (std::find(L.dye_color_index.begin(), L.dye_color_index.end(), col) == L.dye_color_index.end()) return fail("CONDITION_DYE");
    }
    for (const df::cgl_tissue_layer_conditionst* tc : L.tl_condition) {
        if (!tc) continue;
        if (!tissueConditionPasses(c, *tc, swap)) return fail("CONDITION_TISSUE_LAYER");
    }
    for (const df::cgl_bp_conditionst* bc : L.bp_condition) {
        if (!bc) continue;
        if (!bpConditionPasses(c, *bc)) return fail("CONDITION_BP");
    }
    // Layer-group-level body part conditions (LG_CONDITION_BP).
    for (const df::cgl_bp_conditionst* bc : set.lg_bp_condition) {
        if (!bc || bc->layer_group != L.layer_group) continue;
        if (!bpConditionPasses(c, *bc)) return fail("LG_CONDITION_BP");
    }
    if (tracing) g_traceOut->print("    trace {}: PASS\n", L.token.c_str());
    return true;
}

// Roles to try, in order: a corpse item draws through CORPSE only; a unit
// through GHOST / ANIMATED by state, then DEFAULT.
std::vector<df::creature_graphics_role> rolesFor(const Ctx& c) {
    using R = df::creature_graphics_role;
    std::vector<R> roles;
    if (c.corpse) {
        roles.push_back(R::CORPSE);
        return roles;
    }
    if (c.ghost) roles.push_back(R::GHOST);
    if (c.undead) roles.push_back(R::ANIMATED);
    roles.push_back(R::DEFAULT);
    return roles;
}

// The profession key a layer set / simple sprite is looked up by: the
// unit's profession; for a corpse the dead unit's CHILD / BABY key when
// it was one (the CORPSE sets only key on those), else none.
int32_t setProfessionKey(const Ctx& c) {
    if (!c.corpse) return c.profession;
    if (c.baby) return static_cast<int32_t>(df::profession::BABY);
    if (c.child) return static_cast<int32_t>(df::profession::CHILD);
    return -1;
}

// Chooses the layer set for the subject: role by state, then the set whose
// profession key matches the subject's key, else the unkeyed one.
const df::creature_graphics_layer_setst* chooseSet(const Ctx& c, int32_t& roleOut, int32_t& profOut, bool portrait = false) {
    using R = df::creature_graphics_role;
    const std::vector<R> roles = rolesFor(c);
    const int32_t profKey = setProfessionKey(c);
    for (R role : roles) {
        const df::creature_graphics_layer_setst* fallback = nullptr;
        for (const df::creature_graphics_layer_setst* s : c.g->graphics_layer_set) {
            if (!s || s->role != role) continue;
            if (bool(s->flags.bits.portrait) != portrait) continue;
            if (s->el >= 0 || s->sl >= 0) continue;
            if (static_cast<int32_t>(s->prof) == profKey) {
                roleOut = static_cast<int32_t>(role);
                profOut = static_cast<int32_t>(s->prof);
                return s;
            }
            if (static_cast<int32_t>(s->prof) < 0 && !fallback) fallback = s;
        }
        if (fallback) {
            roleOut = static_cast<int32_t>(role);
            profOut = static_cast<int32_t>(fallback->prof);
            return fallback;
        }
    }
    return nullptr;
}

bool resolveSimple(const Ctx& c, Result& out) {
    using R = df::creature_graphics_role;
    const std::vector<R> roles = rolesFor(c);
    const int32_t prof = setProfessionKey(c);
    for (R role : roles) {
        const size_t ri = static_cast<size_t>(role);
        Layer l;
        if (prof >= 0 && static_cast<size_t>(prof) < c.g->profession_texpos[0][ri].size() &&
            cellsToLayer(c.g->profession_texpos[0][ri][prof], l)) {
            out.layers.push_back(l);
            out.role = static_cast<int32_t>(role);
            out.prof = prof;
            return true;
        }
        if (cellsToLayer(c.g->creature_texture_texpos[0][ri], l)) {
            out.layers.push_back(l);
            out.role = static_cast<int32_t>(role);
            return true;
        }
    }
    return false;
}

}  // namespace

namespace {
void freePaletteSurfaces();
}

void reset() {
    g_texmap.clear();
    g_texmapRaws = 0;
    // Palette surfaces are keyed by df::palette_pagest*, which a reload
    // reallocates: free them so neither the surfaces leak nor the keys dangle.
    freePaletteSurfaces();
}

namespace {
bool resolveCtx(const Ctx& c, Result& out, bool portrait = false);
}

bool resolve(df::unit* u, Result& out) {
    out = Result{};
    Ctx c;
    if (!buildCtx(u, c)) return false;
    return resolveCtx(c, out);
}

bool resolvePortrait(df::unit* u, Result& out) {
    out = Result{};
    Ctx c;
    return buildCtx(u, c) && resolveCtx(c, out, true);
}

bool resolveCorpse(df::item* it, Result& out) {
    out = Result{};
    if (!it || it->getType() != df::item_type::CORPSE) return false;  // pieces: hardcoded art, no stack
    Ctx c;
    if (!buildCorpseCtx(static_cast<df::item_body_component*>(it), c)) return false;
    return resolveCtx(c, out);
}

namespace {
bool resolveCtx(const Ctx& c, Result& out, bool portrait) {
    ensureTexposMap();
    const df::creature_graphics_layer_setst* set = chooseSet(c, out.role, out.prof, portrait);
    if (!set) return !portrait && resolveSimple(c, out);
    out.layered = true;
    // Named vanilla map pieces can reflect anatomy even though vanilla's map
    // raws omit presence conditions. Portraits retain their own explicit rules.
    uint16_t missing=0;
    if(!portrait && !c.baby && c.raw->creature_id=="DWARF" && c.u && c.u->body.body_plan) {
        const auto& parts=c.u->body.body_plan->body_parts;
        missing=anatomy::missingRegions(parts.size(),[&](size_t i) {
            const auto* p=parts[i];
            return anatomy::Part{p?std::string_view(p->token):std::string_view{},p?p->con_part_id:-1,
                i<c.bpStatus->size() && (*c.bpStatus)[i].bits.missing};
        });
    }
    // Layer group -1 is "no LAYER_GROUP": DF draws every passing layer in
    // it. The CORPSE sets carry no LAYER_GROUP token at all, so all their
    // layers are -1, while the DEFAULT sets number their groups from 0.
    // Groups >= 0 draw their first passing layer only.
    int32_t curGroup = -2;
    bool groupDone = false;
    for (const df::creature_graphics_layerst* L : set->graphics_layer) {
        if (!L) continue;
        if (L->layer_group != curGroup) {
            curGroup = L->layer_group;
            groupDone = false;
        }
        if (groupDone && L->layer_group >= 0) continue;
        const std::array<std::array<int32_t, 2>, 3>* swap = nullptr;
        const df::unit_inventory_item* matched = nullptr;
        if (!layerPasses(c, *set, *L, swap, matched)) continue;
        groupDone = true;
        Layer l;
        if (!cellsToLayer(swap ? *swap : L->texpos, l)) continue;  // no art loaded for it
        // Consume the winning group even when hidden; do not fall through to
        // another skin/caste variant and accidentally regrow a missing part.
        if(missing) {
            const bool explicitBp=!L->bp_condition.empty() || std::any_of(set->lg_bp_condition.begin(),set->lg_bp_condition.end(),
                [&](const auto* bp){return bp && bp->layer_group==L->layer_group;});
            if(anatomy::hideNamedLayer(missing,l.page->token,L->token,explicitBp)) continue;
        }
        l.token = &L->token;
        l.offX = static_cast<int8_t>(std::max(-128, std::min(127, L->offset_x)));
        l.offY = static_cast<int8_t>(std::max(-128, std::min(127, L->offset_y)));
        if (!L->use_palette_index.empty() && !L->use_palette_row.empty()) {
            const int32_t pi = L->use_palette_index[0];
            if (pi >= 0 && static_cast<size_t>(pi) < set->palette_page.size() && set->palette_page[pi]) {
                l.palette = set->palette_page[pi];
                l.row = static_cast<int16_t>(L->use_palette_row[0]);
                l.keyRow = static_cast<int16_t>(l.palette->default_row);
            }
        } else if (L->flags.bits.use_standard_item_palette) {
            const df::palette_pagest* pal = standardPalette();
            if (pal) {
                const int32_t col = matched && matched->item ? matched->item->getColorWhetherDyedOrNot() : -1;
                l.palette = pal;
                l.row = static_cast<int16_t>(paletteRowForColor(pal, col));
                l.keyRow = static_cast<int16_t>(pal->default_row);
            }
        }
        out.layers.push_back(l);
    }
    return true;
}
}  // namespace

uint32_t corpseFingerprint(const df::item* it) {
    uint32_t h = 2166136261u;
    auto mix = [&](uint32_t v) { h = (h ^ v) * 16777619u; h ^= h >> 15; };
    if (!it) return h;
    const df::item_type type = const_cast<df::item*>(it)->getType();  // virtual getter, not const in df-structures
    mix(static_cast<uint32_t>(type));
    mix(it->flags.bits.rotten ? 1u : 0u);
    if (type != df::item_type::CORPSE && type != df::item_type::CORPSEPIECE) return h;
    const auto* c = static_cast<const df::item_body_component*>(it);
    mix(static_cast<uint32_t>(c->race));
    mix(static_cast<uint32_t>(c->caste));
    mix(static_cast<uint32_t>(c->unit_id));
    mix(c->corpse_flags.whole);
    mix(static_cast<uint32_t>(c->body.size_info.size_cur / 1000));
    mix(static_cast<uint32_t>(c->appearance.tissue_style.size()));
    for (df::tissue_style_type s : c->appearance.tissue_style) mix(static_cast<uint32_t>(s));
    mix(static_cast<uint32_t>(c->body.components.body_part_status.size()));
    for (const df::body_part_status& s : c->body.components.body_part_status) mix(s.bits.missing ? 1u : 0u);
    return h;
}

uint32_t fingerprint(const df::unit* u) {
    uint32_t h = 2166136261u;
    auto mix = [&](uint32_t v) { h = (h ^ v) * 16777619u; h ^= h >> 15; };
    mix(static_cast<uint32_t>(u->profession));
    mix(static_cast<uint32_t>(u->caste));
    mix(static_cast<uint32_t>(u->race));
    mix(u->flags3.bits.ghostly ? 1u : 0u);
    mix(u->enemy.undead ? 1u : 0u);
    mix(static_cast<uint32_t>(u->inventory.size()));
    for (const df::unit_inventory_item* inv : u->inventory) {
        if (!inv) continue;
        mix(static_cast<uint32_t>(inv->item ? inv->item->id : -1));
        mix(static_cast<uint32_t>(inv->mode));
        mix(static_cast<uint32_t>(inv->body_part_id));
    }
    mix(static_cast<uint32_t>(u->syndromes.active.size()));
    for (const df::unit_syndrome* s : u->syndromes.active) mix(static_cast<uint32_t>(s ? s->type : -1));
    for (df::tissue_style_type s : u->appearance.tissue_style) mix(static_cast<uint32_t>(s));
    anatomy::fingerprintMissing(u->body.components.body_part_status,mix);
    mix(static_cast<uint32_t>(u->body.size_info.size_cur / 1000));
    return h;
}

const std::string& pageToken(const df::tile_pagest* page) {
    static const std::string empty;
    return page ? page->token : empty;
}

namespace {
std::string forwardSlashes(std::string s) {
    for (char& ch : s)
        if (ch == '\\') ch = '/';
    return s;
}

// A path relative to the DF install root. DF records palette/page files
// as graphics_dir + filename; both are under the install (data/vanilla/...
// or data/installed_mods/...). Prefer std::filesystem::relative against
// DFHack's install dir; fall back to cutting at "/data/".
std::string installRelative(const std::filesystem::path& dir, const std::filesystem::path& file) {
    std::filesystem::path full = file.is_absolute() ? file : (dir / file);
    std::error_code ec;
    std::filesystem::path root = Filesystem::getInstallDir();
    if (!root.empty()) {
        std::filesystem::path rel = std::filesystem::relative(full, root, ec);
        if (!ec && !rel.empty() && rel.native().rfind(L"..", 0) != 0) return forwardSlashes(rel.generic_string());
    }
    std::string s = forwardSlashes(full.generic_string());
    const size_t at = s.find("/data/");
    if (at != std::string::npos) return s.substr(at + 1);
    // Last resort: the relative form as DF holds it.
    return forwardSlashes((dir / file).generic_string());
}
}  // namespace

std::string paletteInstallPath(const df::palette_pagest* palette) {
    if (!palette) return {};
    return installRelative(palette->graphics_dir, palette->filename);
}

// ---------------------------------------------------------------- diagnostics

namespace {

// Minimal SDL2 views (the plugin does not have SDL headers; layouts are
// SDL 2.x x64: SDL_Surface {Uint32 flags; SDL_PixelFormat* format; int w,
// h, pitch; void* pixels; ...}, SDL_PixelFormat {Uint32 format;
// SDL_Palette* palette; Uint8 BitsPerPixel, BytesPerPixel, pad[2]; Uint32
// Rmask, Gmask, Bmask, Amask; ...}).
struct SdlPixelFormatView {
    uint32_t format;
    void* palette;
    uint8_t bitsPerPixel;
    uint8_t bytesPerPixel;
    uint8_t pad[2];
    uint32_t rmask, gmask, bmask, amask;
};
struct SdlSurfaceView {
    uint32_t flags;
    SdlPixelFormatView* format;
    int w, h;
    int pitch;
    void* pixels;
};

struct Rgba {
    uint8_t r = 0, g = 0, b = 0, a = 0;
    bool operator==(const Rgba& o) const { return r == o.r && g == o.g && b == o.b && a == o.a; }
};

uint32_t maskShift(uint32_t m) {
    if (!m) return 0;
    uint32_t s = 0;
    while (!(m & 1u)) { m >>= 1; ++s; }
    return s;
}
uint32_t maskScale(uint32_t m) {
    if (!m) return 0;
    m >>= maskShift(m);
    uint32_t bits = 0;
    while (m & 1u) { m >>= 1; ++bits; }
    return bits;
}

bool readPixel(const SdlSurfaceView* s, int x, int y, Rgba& out) {
    if (!s || !s->format || !s->pixels || x < 0 || y < 0 || x >= s->w || y >= s->h) return false;
    const SdlPixelFormatView* f = s->format;
    if (f->palette || (f->bytesPerPixel != 4 && f->bytesPerPixel != 3)) return false;
    const uint8_t* p = static_cast<const uint8_t*>(s->pixels) + static_cast<size_t>(y) * s->pitch + static_cast<size_t>(x) * f->bytesPerPixel;
    uint32_t v = 0;
    std::memcpy(&v, p, f->bytesPerPixel);
    auto chan = [&](uint32_t mask) -> uint8_t {
        if (!mask) return 255;
        const uint32_t bits = maskScale(mask);
        const uint32_t raw = (v & mask) >> maskShift(mask);
        return static_cast<uint8_t>(bits >= 8 ? raw : (raw * 255) / ((1u << bits) - 1));
    };
    out.r = chan(f->rmask);
    out.g = chan(f->gmask);
    out.b = chan(f->bmask);
    out.a = f->amask ? chan(f->amask) : 255;
    return true;
}

const SdlSurfaceView* surfaceAt(int32_t texpos) {
    if (!enabler || texpos < 0 || static_cast<size_t>(texpos) >= enabler->textures.raws.size()) return nullptr;
    return static_cast<const SdlSurfaceView*>(enabler->textures.raws[texpos]);
}

// Palette images loaded through DF's SDL_image for the diagnostic only.
std::map<const df::palette_pagest*, void*> g_paletteSurfaces;

void freePaletteSurfaces() {
    for (auto& [pal, surface] : g_paletteSurfaces)
        if (surface) DFSDL::DFSDL_FreeSurface(static_cast<SDL_Surface*>(surface));
    g_paletteSurfaces.clear();
}

const SdlSurfaceView* paletteSurface(const df::palette_pagest* pal) {
    auto it = g_paletteSurfaces.find(pal);
    if (it != g_paletteSurfaces.end()) return static_cast<const SdlSurfaceView*>(it->second);
    std::filesystem::path full = pal->filename.is_absolute() ? pal->filename : (pal->graphics_dir / pal->filename);
    void* s = DFSDL::DFIMG_Load(full.string().c_str());
    g_paletteSurfaces[pal] = s;
    return static_cast<const SdlSurfaceView*>(s);
}

struct Canvas {
    int w = 0, h = 0, originX = 0, originY = 0;
    std::vector<Rgba> px;
    void init(int cw, int ch) { w = cw; h = ch; px.assign(static_cast<size_t>(cw) * ch, Rgba{}); }
    Rgba& at(int x, int y) { return px[static_cast<size_t>(y) * w + x]; }
};

void blendOver(Rgba& dst, const Rgba& src) {
    if (src.a == 0) return;
    if (src.a == 255 || dst.a == 0) { dst = src; return; }
    const int sa = src.a, da = dst.a;
    const int oa = sa + da * (255 - sa) / 255;
    auto mixc = [&](int s, int d) { return static_cast<uint8_t>((s * sa + d * da * (255 - sa) / 255) / (oa ? oa : 1)); };
    dst.r = mixc(src.r, dst.r);
    dst.g = mixc(src.g, dst.g);
    dst.b = mixc(src.b, dst.b);
    dst.a = static_cast<uint8_t>(oa);
}

// Composites the stack on a cellsX x cellsY tile canvas (tile = the first
// layer's page tile dims): each layer's cells at (offX, offY), palette
// keys of keyRow swapped for row, alpha-over. Returns false if any
// surface could not be read.
bool composite(const Result& r, int cellsX, int cellsY, Canvas& canvas, std::string& why) {
    if (r.layers.empty()) { why = "no layers"; return false; }
    const int tw = r.layers[0].page->tile_dim_x, th = r.layers[0].page->tile_dim_y;
    const int bodyW = cellsX * tw, bodyH = cellsY * th;
    const auto wieldable = [](const Layer& l) {
        const auto& p = l.page->token;
        return p == "WIELDABLES" || p == "WIELDABLES_TALL" || p == "WIELDABLES_WIDE";
    };
    int minX = 0, minY = 0, maxX = bodyW, maxY = bodyH;
    for (const Layer& l : r.layers) {
        if (!wieldable(l)) continue;
        const int w = l.cellsX * l.page->tile_dim_x, h = l.cellsY * l.page->tile_dim_y;
        const int x = bodyW - w + l.offX, y = bodyH - h + l.offY;
        minX = std::min(minX,x); minY = std::min(minY,y);
        maxX = std::max(maxX,x+w); maxY = std::max(maxY,y+h);
    }
    canvas.init(maxX-minX,maxY-minY); canvas.originX=minX; canvas.originY=minY;
    for (const Layer& l : r.layers) {
        const SdlSurfaceView* pal = l.palette ? paletteSurface(l.palette) : nullptr;
        if (l.palette && !pal) { why = "palette image failed to load"; return false; }
        const int ltw = l.page->tile_dim_x, lth = l.page->tile_dim_y;
        const int imgW = l.cellsX * ltw, imgH = l.cellsY * lth;
        const int fx = (imgW + bodyW - 1) / bodyW, fy = (imgH + bodyH - 1) / bodyH;
        const bool overflow = wieldable(l);
        const int f = overflow ? 1 : std::max(1, std::max(fx, fy));
        for (int cy = 0; cy < l.cellsY; ++cy) {
            for (int cx = 0; cx < l.cellsX; ++cx) {
                const int idx = (l.tileY + cy) * l.page->page_dim_x + (l.tileX + cx);
                if (idx < 0 || static_cast<size_t>(idx) >= l.page->texpos.size()) { why = "cell outside page"; return false; }
                const SdlSurfaceView* s = surfaceAt(static_cast<int32_t>(l.page->texpos[idx]));
                if (!s) { why = "tile surface missing"; return false; }
                for (int y = 0; y < lth; ++y) {
                    for (int x = 0; x < ltw; ++x) {
                        const int ix = cx * ltw + x, iy = cy * lth + y;
                        if (ix % f != 0 || iy % f != 0) continue;
                        Rgba p;
                        if (!readPixel(s, x, y, p)) { why = "unreadable tile pixel format"; return false; }
                        if (pal && p.a != 0) {
                            for (int col = 0; col < pal->w; ++col) {
                                Rgba key;
                                if (!readPixel(pal, col, l.keyRow, key)) break;
                                if (key.r == p.r && key.g == p.g && key.b == p.b) {
                                    Rgba rep;
                                    if (readPixel(pal, col, l.row, rep)) { rep.a = p.a; p = rep; }
                                    break;
                                }
                            }
                        }
                        const int dx = ix / f + l.offX - minX + (overflow ? bodyW-imgW : 0),
                                  dy = iy / f + l.offY - minY + (overflow ? bodyH-imgH : 0);
                        if (dx < 0 || dy < 0 || dx >= canvas.w || dy >= canvas.h) continue;
                        blendOver(canvas.at(dx, dy), p);
                    }
                }
            }
        }
    }
    return true;
}

// Compares the canvas cell (cx, cy) with DF's cached surface for that
// cell. Returns the number of differing pixels, -1 if unreadable.
int diffCell(Canvas& canvas, int cx, int cy, int32_t dfTexpos, int tw, int th, int tolerance) {
    const SdlSurfaceView* s = surfaceAt(dfTexpos);
    if (!s) return -1;
    int bad = 0;
    for (int y = 0; y < th; ++y) {
        for (int x = 0; x < tw; ++x) {
            Rgba d;
            if (!readPixel(s, x, y, d)) return -1;
            const int ox = cx * tw + x - canvas.originX, oy = cy * th + y - canvas.originY;
            Rgba o = (ox < canvas.w && oy < canvas.h) ? canvas.at(ox, oy) : Rgba{};
            if (d.a < 8 && o.a < 8) continue;
            if (std::abs(int(d.r) - o.r) > tolerance || std::abs(int(d.g) - o.g) > tolerance ||
                std::abs(int(d.b) - o.b) > tolerance || std::abs(int(d.a) - o.a) > tolerance)
                ++bad;
        }
    }
    return bad;
}

const char* roleName(int32_t role) {
    using R = df::creature_graphics_role;
    switch (static_cast<R>(role)) {
    case R::DEFAULT: return "DEFAULT";
    case R::LAW_ENFORCE: return "LAW_ENFORCE";
    case R::TAX_ESCORT: return "TAX_ESCORT";
    case R::ANIMATED: return "ANIMATED";
    case R::ADVENTURER: return "ADVENTURER";
    case R::GHOST: return "GHOST";
    case R::CORPSE: return "CORPSE";
    default: return "NONE";
    }
}

std::string describeTexpos(int32_t t) {
    if (t < 0) return "(none)";
    const df::tile_pagest* page = nullptr;
    int32_t x = 0, y = 0;
    char buf[128];
    if (texposToTile(t, page, x, y)) {
        std::snprintf(buf, sizeof(buf), "%d = page %s (%d,%d)", t, page->token.c_str(), x, y);
    } else {
        const SdlSurfaceView* s = surfaceAt(t);
        if (s && s->format)
            std::snprintf(buf, sizeof(buf), "%d = runtime surface %dx%d (%u bpp), not a page tile", t, s->w, s->h, s->format->bitsPerPixel);
        else
            std::snprintf(buf, sizeof(buf), "%d = not a page tile (raws size %zu)", t, enabler ? enabler->textures.raws.size() : 0);
    }
    return buf;
}

// Verify one unit: composite ours, diff against DF's cells; returns the
// worst cell mismatch as a percentage (or -1). Prints per-cell detail when
// `out` is given.
// Diagnostic image dumps (P6 PPM, alpha composited over magenta) so the
// composite and DF's can be looked at side by side.
std::string g_imageDir;

void writePpm(const std::string& path, int w, int h, const std::function<bool(int, int, Rgba&)>& px) {
    std::ofstream f(path, std::ios::binary);
    if (!f) return;
    f << "P6\n" << w << " " << h << "\n255\n";
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            Rgba p;
            if (!px(x, y, p)) p = Rgba{};
            const int a = p.a;
            const unsigned char rgb[3] = {static_cast<unsigned char>((p.r * a + 255 * (255 - a)) / 255),
                                          static_cast<unsigned char>((p.g * a + 0 * (255 - a)) / 255),
                                          static_cast<unsigned char>((p.b * a + 255 * (255 - a)) / 255)};
            f.write(reinterpret_cast<const char*>(rgb), 3);
        }
    }
}

// The unit's cell in the main map viewport (DFHack layout: index =
// (x - window_x) * dim_y + (y - window_y), z == window_z), or -1.
int viewportIndex(const df::unit* u) {
    using namespace df::global;
    if (!gps || !gps->main_viewport || !window_x || !window_y || !window_z) return -1;
    const df::graphic_viewportst* vp = gps->main_viewport;
    if (u->pos.z != *window_z) return -1;
    const int x = u->pos.x - *window_x, y = u->pos.y - *window_y;
    if (x < 0 || y < 0 || x >= vp->dim_x || y >= vp->dim_y) return -1;
    return x * vp->dim_y + y;
}

// Verify one unit against what DF is drawing for it right now: DF
// composites a layered unit into one runtime texture per screen cell
// (graphic_viewportst::screentexpos for the unit's tile, *_up_creature /
// *_left_creature / *_right_creature for the cells a large image spills
// into). The unit must be on screen at the current z. Returns the worst
// cell mismatch as a percentage, -1 if not verifiable.
double verifyUnit(color_ostream* out, df::unit* u, const Result& r) {
    if (r.layers.empty()) return -1;
    const int cellsX = r.layers[0].cellsX, cellsY = r.layers[0].cellsY;
    const int index = viewportIndex(u);
    if (index < 0) {
        if (out) out->print("    verify: unit not in the main viewport at the current z (window {},{},{}); center the view on it first\n",
                            df::global::window_x ? *df::global::window_x : -1, df::global::window_y ? *df::global::window_y : -1,
                            df::global::window_z ? *df::global::window_z : -1);
        return -1;
    }
    const df::graphic_viewportst* vp = df::global::gps->main_viewport;
    Canvas canvas;
    std::string why;
    if (!composite(r, cellsX, cellsY, canvas, why)) {
        if (out) out->print("    verify: cannot composite ({})\n", why.c_str());
        return -1;
    }
    const int tw = r.layers[0].page->tile_dim_x, th = r.layers[0].page->tile_dim_y;
    double worst = 0;
    bool any = false;
    // The unit's own tile is the bottom row of the canvas (large images
    // extend upwards / sideways); the alternative anchor is reported too so
    // the convention can be read off the numbers.
    struct Probe { const char* name; int32_t texpos; int cx, cy; };
    const int bottom = cellsY - 1;
    std::vector<Probe> probes{{"tile", vp->screentexpos[index], 0, bottom}};
    if (cellsY > 1) {
        probes.push_back({"up", vp->screentexpos_up_creature[index], 0, bottom - 1});
        probes.push_back({"tile-vs-top-row", vp->screentexpos[index], 0, 0});
    }
    if (cellsX > 1) {
        probes.push_back({"right", vp->screentexpos_right_creature[index], 1, bottom});
        if (cellsX > 2) probes.push_back({"left", vp->screentexpos_left_creature[index], 2, bottom});
    }
    if (!g_imageDir.empty()) {
        const std::string base = g_imageDir + "/appearance_unit_" + std::to_string(u->id);
        writePpm(base + "_ours.ppm", canvas.w, canvas.h, [&](int x, int y, Rgba& p) { p = canvas.at(x, y); return true; });
        for (const Probe& pr : probes) {
            if (pr.texpos <= 0 || std::strcmp(pr.name, "tile-vs-top-row") == 0) continue;
            const SdlSurfaceView* sv = surfaceAt(pr.texpos);
            if (!sv) continue;
            writePpm(base + "_df_" + pr.name + ".ppm", sv->w, sv->h, [&](int x, int y, Rgba& p) { return readPixel(sv, x, y, p); });
        }
        if (out) out->print("    verify: images written to {}\n", base.c_str());
    }
    for (const Probe& pr : probes) {
        if (pr.texpos <= 0) {
            if (out) out->print("    verify: {}: DF draws nothing there (texpos {})\n", pr.name, pr.texpos);
            continue;
        }
        const int bad = diffCell(canvas, pr.cx, pr.cy, pr.texpos, tw, th, 8);
        if (bad < 0) {
            if (out) out->print("    verify: {}: DF texpos {} unreadable\n", pr.name, describeTexpos(pr.texpos).c_str());
            continue;
        }
        const double pct = 100.0 * bad / (tw * th);
        if (std::strcmp(pr.name, "tile-vs-top-row") != 0) { any = true; worst = std::max(worst, pct); }
        if (out) out->print("    verify: {} (our cell {},{}) vs DF {}: {}/{} pixels differ ({:.1f}%)\n", pr.name, pr.cx, pr.cy, describeTexpos(pr.texpos).c_str(), bad, tw * th, pct);
    }
    return any ? worst : -1;
}

void printLayer(color_ostream& out, const Layer& l, size_t i) {
    out.print("    [{:2}] {:<28} page {} ({},{}) {}x{}", i, l.token ? l.token->c_str() : "(simple)", l.page->token.c_str(), l.tileX, l.tileY, l.cellsX, l.cellsY);
    if (l.palette)
        out.print(" palette {} row {} key {}", paletteInstallPath(l.palette).c_str(), l.row, l.keyRow);
    if (l.offX || l.offY) out.print(" offset ({},{})", l.offX, l.offY);
    out.print("\n");
}

}  // namespace

void trace(color_ostream& out, df::unit* u, const std::string& token) {
    g_traceOut = &out;
    g_traceToken = token;
    Result r;
    resolve(u, r);
    g_traceOut = nullptr;
    g_traceToken.clear();
    out.print("  ({} layers resolved)\n", r.layers.size());
}

void dump(color_ostream& out, df::unit* u, bool verify, const std::string& imageDir) {
    g_imageDir = imageDir;
    Result r;
    const bool ok = resolve(u, r);
    const df::creature_raw* raw = df::creature_raw::find(u->race);
    out.print("unit {} race {} caste {} profession {} child={} ghost={} undead={} inventory {} haul {}\n", u->id,
              raw ? raw->creature_id.c_str() : "?", u->caste, static_cast<int>(u->profession), Units::isChild(u) ? 1 : 0,
              Units::isGhost(u) ? 1 : 0, u->enemy.undead ? 1 : 0, u->inventory.size(),
              [&] { int n = 0; for (auto* inv : u->inventory) if (inv && inv->mode == df::inv_item_role_type::Hauled) ++n; return n; }());
    out.print("  resolved: {}, role {}, set prof {}, {} layers\n", ok ? (r.layered ? "layered" : "simple") : "no graphics", roleName(r.role), r.prof, r.layers.size());
    out.print("  appearance fingerprint: {}\n", fingerprint(u));
    for (size_t i = 0; i < r.layers.size(); ++i) printLayer(out, r.layers[i], i);
    out.print("  DF cached unit texpos (unit.texpos[dx][dy], in_use):\n");
    for (int dy = 0; dy < 2; ++dy)
        for (int dx = 0; dx < 3; ++dx)
            if (u->texpos[dx][dy] >= 0 || u->texpos_currently_in_use[dx][dy])
                out.print("    ({},{}) in_use={} {}\n", dx, dy, u->texpos_currently_in_use[dx][dy] ? 1 : 0, describeTexpos(u->texpos[dx][dy]).c_str());
    out.print("    sheet_icon {}; portrait {}\n", describeTexpos(u->sheet_icon_texpos).c_str(), describeTexpos(u->portrait_texpos).c_str());
    Result portrait;
    if (resolvePortrait(u, portrait)) {
        out.print("  portrait: {} layers\n", portrait.layers.size());
        for (size_t i = 0; i < portrait.layers.size(); ++i) printLayer(out, portrait.layers[i], i);
    }
    out.print("  inventory:\n");
    for (const df::unit_inventory_item* inv : u->inventory) {
        if (!inv || !inv->item) continue;
        df::item* it = inv->item;
        MaterialInfo mi(it->getMaterial(), it->getMaterialIndex());
        out.print("    item {} type {} subtype {} mode {} bp {} mat {} artifact {} grown {} dyed {} color {} wear {} quality {}\n", it->id,
                  static_cast<int>(it->getType()), it->getSubtype(), static_cast<int>(inv->mode), inv->body_part_id,
                  mi.isValid() ? mi.getToken().c_str() : "?", it->flags.bits.artifact ? 1 : 0, it->flags2.bits.grown ? 1 : 0,
                  it->isDyed() ? 1 : 0, it->getColorWhetherDyedOrNot(), it->getWear(), it->getQuality());
    }
    out.print("  appearance: colors {} tissue_style {} bp_modifiers {}; job.random_appearance_number {}\n",
              u->appearance.colors.size(), u->appearance.tissue_style.size(), u->appearance.bp_modifiers.size(), u->job.random_appearance_number);
    if (verify && ok) {
        const double worst = verifyUnit(&out, u, r);
        out.print("  verify: worst cell mismatch {:.1f}%\n", worst);
    }
}

void dumpLayerSet(color_ostream& out, df::unit* u, int maxLayers, const std::string& tokenFilter) {
    Ctx c;
    if (!buildCtx(u, c)) { out.printerr("no creature/caste/graphics for unit\n"); return; }
    ensureTexposMap();
    out.print("graphics block: {} layer sets; simple DEFAULT texpos {} add_color={}\n", c.g->graphics_layer_set.size(),
              describeTexpos(c.g->creature_texture_texpos[0][static_cast<size_t>(df::creature_graphics_role::DEFAULT)][0][0]).c_str(),
              c.g->creature_texture_add_color[static_cast<size_t>(df::creature_graphics_role::DEFAULT)] ? 1 : 0);
    for (size_t si = 0; si < c.g->graphics_layer_set.size(); ++si) {
        const df::creature_graphics_layer_setst* s = c.g->graphics_layer_set[si];
        if (!s) continue;
        out.print("  set {}: role {} prof {} el {} sl {} portrait={} layers {} palettes {} lg_bp_conditions {} template '{}'\n", si, roleName(static_cast<int32_t>(s->role)),
                  static_cast<int>(s->prof), s->el, s->sl, s->flags.bits.portrait ? 1 : 0, s->graphics_layer.size(), s->palette_page.size(),
                  s->lg_bp_condition.size(), s->layer_set_template_token.c_str());
        for (size_t pi = 0; pi < s->palette_page.size(); ++pi) {
            const df::palette_pagest* p = s->palette_page[pi];
            if (!p) continue;
            out.print("    palette {}: token {} file {} default_row {} rows {} row_width {} colors {}\n", pi, p->token.c_str(),
                      paletteInstallPath(p).c_str(), p->default_row, p->row.size(), p->row_width, p->color_token.size());
        }
    }
    int32_t role = -1, prof = -1;
    const df::creature_graphics_layer_setst* set = chooseSet(c, role, prof);
    if (!set) { out.print("  (no layer set chosen for this unit)\n"); return; }
    out.print("  chosen set: role {} prof {}; first {} layers:\n", roleName(role), prof, maxLayers);
    int n = 0;
    for (const df::creature_graphics_layerst* L : set->graphics_layer) {
        if (!L) continue;
        if (!tokenFilter.empty() && L->token.find(tokenFilter) == std::string::npos) continue;
        if (n++ >= maxLayers) break;
        out.print("    g{:<3} {:<28} tex {} cells[1][0]={} [0][1]={} flags c{} nc{} g{} sp{} supp{} caste {} prof {} syn {} rnd {} haul {}..{} size {} items {}/{} dye {} mat {} tl {} bp {} pal {}/{} off ({},{}) pcg {}\n",
                  L->layer_group, L->token.c_str(), describeTexpos(L->texpos[0][0]).c_str(), L->texpos[1][0], L->texpos[0][1],
                  L->flags.bits.child, L->flags.bits.not_child, L->flags.bits.ghost, L->flags.bits.use_standard_item_palette, L->flags.bits.suppressed_by_load_errors,
                  L->required_caste.size(), L->required_profession.size(), L->required_syn_class.size(), L->random_part_condition_string.size(),
                  L->haul_min_count, L->haul_max_count, L->body_size_min, L->required_item.size(), L->forbidden_item.size(), L->dye_color_index.size(),
                  L->mat ? "yes" : "no", L->tl_condition.size(), L->bp_condition.size(), L->use_palette_index.size(), L->use_palette_row.size(),
                  L->offset_x, L->offset_y, L->pcg_layering);
        for (const df::cgl_tissue_layer_conditionst* tc : L->tl_condition) {
            if (!tc) continue;
            out.print("         tl: castes {} bp {} tl {} len {}..{} dens {}..{} shapes {} notshaped {} colors {} swaps {}\n", tc->check_caste.size(), tc->check_bp.size(),
                      tc->check_tl.size(), tc->min_length, tc->max_length, tc->min_density, tc->max_density, tc->required_shape.size(),
                      tc->flags.bits.requires_not_shaped, tc->color_index.size(), tc->swap.size());
        }
        for (const df::cgl_itemst* ic : L->required_item) {
            if (!ic) continue;
            out.print("         item: type {} subtypes {} castes {} bp {} flags w{} h{} hl{} qual {}..{} dam {}..{}\n", static_cast<int>(ic->item_type), ic->item_subtype.size(),
                      ic->check_caste.size(), ic->check_bp.size(), ic->flags.bits.wield, ic->flags.bits.any_held, ic->flags.bits.any_hauled, ic->min_qual, ic->max_qual,
                      ic->min_dam_level, ic->max_dam_level);
        }
        if (L->mat)
            out.print("         mat: subcat {} flags1 {:#x} flags2 {:#x} flags3 {:#x} flags4 {:#x} flags5 {:#x}\n", L->mat->subcat1.size(), L->mat->flags1.whole, L->mat->flags2.whole,
                      L->mat->flags3.whole, L->mat->flags4, L->mat->flags5);
        for (size_t i = 0; i < L->random_part_condition_string.size(); ++i)
            out.print("         random: {} index {} max {}\n", L->random_part_condition_string[i] ? L->random_part_condition_string[i]->c_str() : "?",
                      i < L->random_part_condition_index.size() ? L->random_part_condition_index[i] : -1, i < L->random_part_condition_max.size() ? L->random_part_condition_max[i] : -1);
    }
}

void survey(color_ostream& out, int maxUnits) {
    ensureTexposMap();
    int n = 0, layered = 0, simple = 0, none = 0, verified = 0, exact = 0;
    out.print("id      race        prof  layers kind     dfTexpos      worst%  random-fit(name: best idx / max, id, ran)\n");
    for (df::unit* u : world->units.active) {
        if (!Units::isActive(u) || Units::isDead(u)) continue;
        if (n++ >= maxUnits) break;
        Result r;
        const bool ok = resolve(u, r);
        const df::creature_raw* raw = df::creature_raw::find(u->race);
        if (!ok) ++none; else if (r.layered) ++layered; else ++simple;
        const double worst = ok ? verifyUnit(nullptr, u, r) : -1;
        if (worst >= 0) { ++verified; if (worst == 0) ++exact; }
        const int vi = viewportIndex(u);
        const char* kind = vi < 0 ? "offscreen" : (gps->main_viewport->screentexpos[vi] > 0 ? "on-screen" : "no-draw");
        out.print("{:<7} {:<11} {:<5} {:<6} {:<8} {:<13} {:6.1f}", u->id, raw ? raw->creature_id.c_str() : "?", static_cast<int>(u->profession), r.layers.size(),
                  ok ? (r.layered ? "layered" : "simple") : "none", kind, worst);
        // Random-part calibration: for each random name in the chosen set,
        // try every index and report the one whose composite matches best.
        if (ok && r.layered && worst >= 0) {
            Ctx c;
            buildCtx(u, c);
            int32_t role = -1, prof = -1;
            const df::creature_graphics_layer_setst* set = chooseSet(c, role, prof);
            std::map<std::string, int32_t> names;
            if (set)
                for (const df::creature_graphics_layerst* L : set->graphics_layer)
                    if (L)
                        for (size_t i = 0; i < L->random_part_condition_string.size() && i < L->random_part_condition_max.size(); ++i)
                            if (L->random_part_condition_string[i]) names[*L->random_part_condition_string[i]] = std::max(names[*L->random_part_condition_string[i]], L->random_part_condition_max[i]);
            for (const auto& [name, max] : names) {
                int32_t best = -1;
                double bestPct = 1e9;
                for (int32_t idx = 1; idx <= max; ++idx) {
                    g_randomOverride = RandomOverride{&name, idx};
                    Result rr;
                    resolve(u, rr);
                    const double pct = verifyUnit(nullptr, u, rr);
                    if (pct >= 0 && pct < bestPct) { bestPct = pct; best = idx; }
                }
                g_randomOverride = RandomOverride{};
                out.print("  {}: {}/{} ({:.1f}%) id {} ran {}", name.c_str(), best, max, bestPct, u->id, u->job.random_appearance_number);
            }
        }
        out.print("\n");
    }
    out.print("units {}: layered {} simple {} none {}; verified {}, pixel-exact {}\n", n, layered, simple, none, verified, exact);
}

// The item's cell in the main map viewport (index as viewportIndex).
// Exported (appearance.h): the console's `corpse first` picks the first
// whole corpse on screen with it.
int viewportIndexAt(const df::coord& pos) {
    using namespace df::global;
    if (!gps || !gps->main_viewport || !window_x || !window_y || !window_z) return -1;
    const df::graphic_viewportst* vp = gps->main_viewport;
    if (pos.z != *window_z) return -1;
    const int x = pos.x - *window_x, y = pos.y - *window_y;
    if (x < 0 || y < 0 || x >= vp->dim_x || y >= vp->dim_y) return -1;
    return x * vp->dim_y + y;
}

namespace {

// Verify one corpse item against what DF drew for it: the item's own
// cached composite (item_corpsest::texpos, in use once DF drew it) when
// present, else the viewport's item cell (screentexpos_item) when the
// item is on screen at the current z (a cell shows the top item of the
// tile, so a corpse under other items reads as "no draw"). Returns the
// worst cell mismatch percentage, -1 if not verifiable.
double verifyCorpse(color_ostream* out, df::item* it, const Result& r) {
    if (r.layers.empty()) return -1;
    const int cellsX = r.layers[0].cellsX, cellsY = r.layers[0].cellsY;
    Canvas canvas;
    std::string why;
    if (!composite(r, cellsX, cellsY, canvas, why)) {
        if (out) out->print("    verify: cannot composite ({})\n", why.c_str());
        return -1;
    }
    const int tw = r.layers[0].page->tile_dim_x, th = r.layers[0].page->tile_dim_y;
    struct Probe { const char* name; int32_t texpos; int cx, cy; };
    std::vector<Probe> probes;
    const int bottom = cellsY - 1;
    if (it->getType() == df::item_type::CORPSE) {
        const auto* c = static_cast<const df::item_corpsest*>(it);
        for (int dy = 0; dy < 2; ++dy)
            for (int dx = 0; dx < 3; ++dx)
                if (c->texpos_currently_in_use[dx][dy] && c->texpos[dx][dy] > 0)
                    probes.push_back({dx == 0 && dy == 0 ? "cache" : "cache-cell", c->texpos[dx][dy], dx, bottom - dy});
    }
    const int index = viewportIndexAt(it->pos);
    if (index >= 0) {
        const df::graphic_viewportst* vp = df::global::gps->main_viewport;
        probes.push_back({"item-cell", vp->screentexpos_item[index], 0, bottom});
    }
    if (!g_imageDir.empty()) {
        const std::string base = g_imageDir + "/appearance_corpse_" + std::to_string(it->id);
        writePpm(base + "_ours.ppm", canvas.w, canvas.h, [&](int x, int y, Rgba& p) { p = canvas.at(x, y); return true; });
        for (const Probe& pr : probes) {
            if (pr.texpos <= 0) continue;
            const SdlSurfaceView* sv = surfaceAt(pr.texpos);
            if (!sv) continue;
            writePpm(base + "_df_" + pr.name + ".ppm", sv->w, sv->h, [&](int x, int y, Rgba& p) { return readPixel(sv, x, y, p); });
        }
        if (out) out->print("    verify: images written to {}\n", base.c_str());
    }
    if (probes.empty()) {
        if (out) out->print("    verify: no cached corpse texture and not in the main viewport at the current z; center the view on it first\n");
        return -1;
    }
    double worst = 0;
    bool any = false;
    for (const Probe& pr : probes) {
        if (pr.texpos <= 0) {
            if (out) out->print("    verify: {}: DF draws nothing there (texpos {})\n", pr.name, pr.texpos);
            continue;
        }
        if (pr.cx < 0 || pr.cy < 0 || pr.cx >= cellsX || pr.cy >= cellsY) continue;
        const int bad = diffCell(canvas, pr.cx, pr.cy, pr.texpos, tw, th, 8);
        if (bad < 0) {
            if (out) out->print("    verify: {}: DF texpos {} unreadable\n", pr.name, describeTexpos(pr.texpos).c_str());
            continue;
        }
        const double pct = 100.0 * bad / (tw * th);
        any = true;
        worst = std::max(worst, pct);
        if (out) out->print("    verify: {} (our cell {},{}) vs DF {}: {}/{} pixels differ ({:.1f}%)\n", pr.name, pr.cx, pr.cy, describeTexpos(pr.texpos).c_str(), bad, tw * th, pct);
    }
    return any ? worst : -1;
}

std::string corpseFlagsText(const df::item_body_component_flag& f) {
    std::string s;
    auto add = [&](bool b, const char* n) { if (b) { if (!s.empty()) s += ','; s += n; } };
    add(f.bits.unbutchered, "unbutchered");
    add(f.bits.plant, "plant");
    add(f.bits.silk, "silk");
    add(f.bits.leather, "leather");
    add(f.bits.bone, "bone");
    add(f.bits.shell, "shell");
    add(f.bits.wood, "wood");
    add(f.bits.soap, "soap");
    add(f.bits.tooth, "tooth");
    add(f.bits.horn, "horn");
    add(f.bits.pearl, "pearl");
    add(f.bits.rottable, "rottable");
    add(f.bits.skull, "skull");
    add(f.bits.use_blood_color, "use_blood_color");
    add(f.bits.hair_wool, "hair_wool");
    add(f.bits.yarn, "yarn");
    add(f.bits.must_rot_body, "must_rot_body");
    add(f.bits.must_refresh_texture, "must_refresh_texture");
    return s.empty() ? "-" : s;
}

}  // namespace

void dumpCorpse(color_ostream& out, df::item* it, bool verify, const std::string& imageDir) {
    g_imageDir = imageDir;
    const df::item_type type = it->getType();
    if (type != df::item_type::CORPSE && type != df::item_type::CORPSEPIECE) {
        out.printerr("item {} is not a corpse or corpse piece (type {})\n", it->id, static_cast<int>(type));
        return;
    }
    auto* c = static_cast<df::item_body_component*>(it);
    const df::creature_raw* raw = df::creature_raw::find(c->race);
    MaterialInfo mi(it->getMaterial(), it->getMaterialIndex());
    out.print("item {} {} race {} caste {} unit {} hf {} at {},{},{} mat {} flags rotten={} on_ground={} corpse_flags [{}] rot_timer {} size {}\n",
              it->id, type == df::item_type::CORPSE ? "CORPSE" : "CORPSEPIECE", raw ? raw->creature_id.c_str() : "?", c->caste,
              c->unit_id, c->hist_figure_id, it->pos.x, it->pos.y, it->pos.z, mi.isValid() ? mi.getToken().c_str() : "?",
              it->flags.bits.rotten ? 1 : 0, it->flags.bits.on_ground ? 1 : 0, corpseFlagsText(c->corpse_flags).c_str(), c->rot_timer,
              c->body.size_info.size_cur);
    out.print("  appearance copies: colors {} tissue_style {} bp_modifiers {} body_part_status {}; largest tissue {}/{} unrottable {}/{}\n",
              c->appearance.colors.size(), c->appearance.tissue_style.size(), c->body.bp_modifiers.size(),
              c->body.components.body_part_status.size(), c->largest_tissue.mat_type, c->largest_tissue.mat_index,
              c->largest_unrottable_tissue.mat_type, c->largest_unrottable_tissue.mat_index);
    Result r;
    const bool ok = resolveCorpse(it, r);
    Ctx cx;
    const bool ctxOk = buildCorpseCtx(c, cx);
    out.print("  subject: child={} baby={} profession {} (unit found {}); resolved: {}, role {}, set prof {}, {} layers\n",
              cx.child ? 1 : 0, cx.baby ? 1 : 0, cx.profession, (c->unit_id >= 0 && df::unit::find(c->unit_id)) ? 1 : 0,
              ok ? (r.layered ? "layered" : "simple") : (ctxOk ? "no graphics" : "no creature/caste/graphics"), roleName(r.role), r.prof,
              r.layers.size());
    for (size_t i = 0; i < r.layers.size(); ++i) printLayer(out, r.layers[i], i);
    if (ctxOk) {
        int32_t role = -1, prof = -1;
        if (const df::creature_graphics_layer_setst* set = chooseSet(cx, role, prof)) {
            int32_t gmin = 0, gmax = 0, zero = 0;
            size_t n = 0, distinct = 0;
            int32_t last = -1;
            std::string firstGroups;
            for (const df::creature_graphics_layerst* L : set->graphics_layer) {
                if (!L) continue;
                if (n == 0 || L->layer_group < gmin) gmin = L->layer_group;
                if (n == 0 || L->layer_group > gmax) gmax = L->layer_group;
                if (L->layer_group == 0) ++zero;
                if (n == 0 || L->layer_group != last) { ++distinct; last = L->layer_group; }
                if (n < 12) firstGroups += (n ? "," : "") + std::to_string(L->layer_group);
                ++n;
            }
            out.print("  layer set: {} layers, groups {}..{} ({} runs, {} in group 0; first: {}), current_layer_group {} next_layer_group {}, lg_bp_condition {}\n",
                      n, gmin, gmax, distinct, zero, firstGroups.c_str(), set->current_layer_group, set->next_layer_group, set->lg_bp_condition.size());
        }
    }
    if (type == df::item_type::CORPSE) {
        const auto* cc = static_cast<const df::item_corpsest*>(it);
        out.print("  DF cached corpse texpos (item_corpsest.texpos[dx][dy], in_use):\n");
        for (int dy = 0; dy < 2; ++dy)
            for (int dx = 0; dx < 3; ++dx)
                if (cc->texpos[dx][dy] > 0 || cc->texpos_currently_in_use[dx][dy])
                    out.print("    ({},{}) in_use={} {}\n", dx, dy, cc->texpos_currently_in_use[dx][dy] ? 1 : 0, describeTexpos(cc->texpos[dx][dy]).c_str());
        out.print("    sheet_icon {}\n", describeTexpos(cc->sheet_icon_texpos).c_str());
    }
    const int vi = viewportIndexAt(it->pos);
    if (vi >= 0) {
        const df::graphic_viewportst* vp = df::global::gps->main_viewport;
        out.print("  viewport item cell: {}; creature cell: {}\n", describeTexpos(vp->screentexpos_item[vi]).c_str(), describeTexpos(vp->screentexpos[vi]).c_str());
    } else {
        out.print("  viewport: item not on screen at the current z\n");
    }
    if (verify && ok) {
        const double worst = verifyCorpse(&out, it, r);
        out.print("  verify: worst cell mismatch {:.1f}%\n", worst);
    }
}

void surveyCorpses(color_ostream& out, int maxItems) {
    ensureTexposMap();
    int n = 0, layered = 0, simple = 0, none = 0, pieces = 0, verified = 0, exact = 0, under10 = 0, onScreen = 0;
    // Items in the main viewport at the current z first (they are the
    // ones with an oracle: DF has drawn them), then the rest of the vector.
    std::vector<df::item*> order;
    for (int pass = 0; pass < 2 && static_cast<int>(order.size()) < maxItems; ++pass) {
        for (df::item* it : world->items.other.IN_PLAY) {
            if (!it || !it->flags.bits.on_ground) continue;
            const df::item_type type = it->getType();
            if (type != df::item_type::CORPSE && type != df::item_type::CORPSEPIECE) continue;
            const bool inView = viewportIndexAt(it->pos) >= 0;
            if (inView != (pass == 0)) continue;
            if (static_cast<int>(order.size()) >= maxItems) break;
            order.push_back(it);
            if (inView) ++onScreen;
        }
    }
    // Items sharing a tile: the viewport cell shows one of them, so the
    // oracle is only trusted for an item alone on its tile.
    std::unordered_map<uint64_t, int> tileItems;
    auto tileKey = [](const df::coord& p) {
        return (static_cast<uint64_t>(static_cast<uint16_t>(p.z)) << 32) | (static_cast<uint64_t>(static_cast<uint16_t>(p.x)) << 16) |
               static_cast<uint16_t>(p.y);
    };
    for (df::item* it : world->items.other.IN_PLAY)
        if (it && it->flags.bits.on_ground) ++tileItems[tileKey(it->pos)];
    out.print("id      type        race         flags                              tissue          layers kind     df-cache      tile-items missing worst%  item-cell\n");
    for (df::item* it : order) {
        const df::item_type type = it->getType();
        ++n;
        auto* c = static_cast<df::item_body_component*>(it);
        const int onTile = tileItems[tileKey(it->pos)];
        int missing = 0;
        for (const auto& st : c->body.components.body_part_status)
            if (st.bits.missing) ++missing;
        std::string tissue = "-";
        if (c->largest_tissue.mat_type >= 0) {
            MaterialInfo mi(c->largest_tissue.mat_type, c->largest_tissue.mat_index);
            if (mi.isValid()) {
                tissue = mi.getToken();
                if (const size_t colon = tissue.find(':', tissue.find(':') + 1); colon != std::string::npos) tissue = tissue.substr(colon + 1);
            }
        }
        const df::creature_raw* raw = df::creature_raw::find(c->race);
        Result r;
        const bool ok = resolveCorpse(it, r);
        if (type == df::item_type::CORPSEPIECE) ++pieces;
        else if (!ok) ++none;
        else if (r.layered) ++layered;
        else ++simple;
        const double worst = ok && onTile == 1 ? verifyCorpse(nullptr, it, r) : -1;
        if (worst >= 0) { ++verified; if (worst == 0) ++exact; if (worst < 10) ++under10; }
        std::string cache = "-";
        if (type == df::item_type::CORPSE) {
            const auto* cc = static_cast<const df::item_corpsest*>(it);
            cache = "not-drawn";
            for (int dy = 0; dy < 2 && cache == "not-drawn"; ++dy)
                for (int dx = 0; dx < 3; ++dx)
                    if (cc->texpos_currently_in_use[dx][dy] || cc->texpos[dx][dy] > 0) {
                        cache = std::to_string(cc->texpos[dx][dy]) + (cc->texpos_currently_in_use[dx][dy] ? "*" : "");
                        break;
                    }
        }
        const int vi = viewportIndexAt(it->pos);
        std::string cell = vi < 0 ? "offscreen" : describeTexpos(df::global::gps->main_viewport->screentexpos_item[vi]);
        out.print("{:<7} {:<11} {:<12} {:<34} {:<15} {:<6} {:<8} {:<13} {:<10} {:<7} {:6.1f}  {}\n", it->id, type == df::item_type::CORPSE ? "CORPSE" : "CORPSEPIECE",
                  raw ? raw->creature_id.substr(0, 12).c_str() : "?", corpseFlagsText(c->corpse_flags).substr(0, 34).c_str(), tissue.substr(0, 15).c_str(),
                  r.layers.size(), type == df::item_type::CORPSEPIECE ? "piece" : (ok ? (r.layered ? "layered" : "simple") : "none"), cache.c_str(),
                  onTile, missing, worst, cell.c_str());
    }
    out.print("corpse items {} ({} in the viewport): layered {} simple {} none {} pieces {}; verified (alone on the tile) {}, pixel-exact {}, under 10% {}\n",
              n, onScreen, layered, simple, none, pieces, verified, exact, under10);
}

bool dumpTexture(color_ostream& out, int32_t texpos, const std::string& prefix) {
    const std::filesystem::path base(prefix);
    std::error_code ec;
    if (prefix.empty() || prefix.size() > 4096 || !base.is_absolute() ||
        base.filename().empty() || base.filename() == "." || base.filename() == ".." ||
        !std::filesystem::is_directory(base.parent_path(), ec) || ec) {
        out.printerr("texture dump requires an absolute output prefix in an existing directory\n");
        return false;
    }
    for (const char* suffix : {".rgba", ".json", ".ppm"}) {
        const bool exists = std::filesystem::exists(prefix + suffix, ec);
        if (ec || exists) {
            out.printerr("texture dump: output prefix already exists or cannot be checked\n");
            return false;
        }
    }
    const SdlSurfaceView* s = surfaceAt(texpos);
    if (!s || !s->format || !s->pixels || s->w <= 0 || s->h <= 0 ||
        s->w > 256 || s->h > 256 || s->format->palette ||
        (s->format->bytesPerPixel != 3 && s->format->bytesPerPixel != 4) ||
        s->pitch < s->w * s->format->bytesPerPixel || s->pitch > 16384) {
        out.printerr("texture dump: invalid id or unsupported/bounds-exceeding surface\n");
        return false;
    }
    std::vector<uint8_t> rgba, rgb;
    rgba.reserve(static_cast<size_t>(s->w) * s->h * 4);
    rgb.reserve(static_cast<size_t>(s->w) * s->h * 3);
    for (int y = 0; y < s->h; ++y) for (int x = 0; x < s->w; ++x) {
        Rgba p;
        if (!readPixel(s, x, y, p)) return false;
        rgba.insert(rgba.end(), {p.r, p.g, p.b, p.a});
        rgb.push_back(static_cast<uint8_t>((p.r * p.a + 255 * (255 - p.a)) / 255));
        rgb.push_back(static_cast<uint8_t>(p.g * p.a / 255));
        rgb.push_back(static_cast<uint8_t>((p.b * p.a + 255 * (255 - p.a)) / 255));
    }
    std::ofstream raw(prefix + ".rgba", std::ios::binary);
    std::ofstream metadata(prefix + ".json", std::ios::binary);
    std::ofstream preview(prefix + ".ppm", std::ios::binary);
    if (!raw || !metadata || !preview) {
        out.printerr("texture dump: cannot open output files\n");
        return false;
    }
    raw.write(reinterpret_cast<const char*>(rgba.data()), rgba.size());
    metadata << "{\"texpos\":" << texpos << ",\"width\":" << s->w
             << ",\"height\":" << s->h << ",\"format\":\"RGBA8\",\"bytes\":"
             << rgba.size() << "}\n";
    preview << "P6\n" << s->w << " " << s->h << "\n255\n";
    preview.write(reinterpret_cast<const char*>(rgb.data()), rgb.size());
    raw.close(); metadata.close(); preview.close();
    if (!raw || !metadata || !preview) {
        out.printerr("texture dump: output write failed\n");
        return false;
    }
    out.print("DF3D_TEXTURE_DUMP_PASS id={} width={} height={} bytes={}\n",
              texpos, s->w, s->h, rgba.size());
    return true;
}

void dumpPages(color_ostream& out) {
    ensureTexposMap();
    if (!texture || !enabler) { out.printerr("texture/enabler globals unavailable\n"); return; }
    size_t mapped = 0;
    for (const TexRef& r : g_texmap) if (r.page >= 0) ++mapped;
    out.print("tile pages {}, palettes {}, texture raws {} ({} mapped to page tiles)\n", texture->page.size(), texture->palette.size(), enabler->textures.raws.size(), mapped);
    for (size_t i = 0; i < texture->page.size() && i < 8; ++i) {
        const df::tile_pagest* p = texture->page[i];
        if (!p) continue;
        out.print("  page {} {}: {} tile {}x{} dims {}x{} texpos {} (first {}) loaded={}\n", i, p->token.c_str(), installRelative(p->graphics_dir, p->filename).c_str(),
                  p->tile_dim_x, p->tile_dim_y, p->page_dim_x, p->page_dim_y, p->texpos.size(), p->texpos.empty() ? -1L : p->texpos[0], p->loaded ? 1 : 0);
    }
    for (const df::tile_pagest* p : texture->page) {
        if (!p || p->token != "DWARF_BODY") continue;
        out.print("  DWARF_BODY: {} tile {}x{} dims {}x{} texpos {} (expected {})\n", installRelative(p->graphics_dir, p->filename).c_str(), p->tile_dim_x, p->tile_dim_y,
                  p->page_dim_x, p->page_dim_y, p->texpos.size(), p->page_dim_x * p->page_dim_y);
    }
    const df::palette_pagest* std_ = standardPalette();
    if (std_)
        out.print("  standard palette: token {} file {} default_row {} rows {} row_width {} colors {}\n", std_->token.c_str(), paletteInstallPath(std_).c_str(), std_->default_row,
                  std_->row.size(), std_->row_width, std_->color_token.size());
}

}  // namespace df3d_appearance
