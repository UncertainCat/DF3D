#pragma once
#include "paint_water.h"
#include "paint_material.h"
#include "paint_counts.h"
namespace df3d_area {
// Safe-point semantic read. No native UI, mutations, allocation of map blocks,
// or revelation of hidden terrain. Unsupported observations remain Unknown.
PaintWaterEligibility observeNativePaintWater(int32_t x,int32_t y,int32_t z);
PaintBaseEligibility observeNativePaintBase(int32_t x,int32_t y,int32_t z);
PaintMaterialEligibility observeNativePaintMaterial(int32_t x,int32_t y,int32_t z);
// One safe-point observation of the supplied local draft and preview. Re-reads
// all predicate dependencies, including adjacent/lower water and soil geology.
// Unsupported zone types and invalid geometry return valid=false.
PaintCounts observeNativePaintCounts(int32_t zoneType,int32_t z,
    const std::vector<Span>& draft,const std::vector<Span>& preview);
}
