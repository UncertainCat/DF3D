#pragma once
#include <cstdint>
#include <array>
namespace DFHack {
class color_ostream;
}
namespace df3d_management {
void update(DFHack::color_ostream& out, uint64_t worldEpoch, bool saving);
void stop();
void printTiming(DFHack::color_ostream& out);
// Read-only diagnostic; caller holds the DF safe point. Coordinates are seed xyz, target xyz.
bool printMaterialDistances(DFHack::color_ostream& out, const std::array<int32_t,6>& positions, int32_t tileLimit);
bool printTrackMaterialCandidates(DFHack::color_ostream& out, const std::array<int32_t,6>& positions, int32_t maximumCandidates, int32_t tileLimit = 0);
bool takeMutation();
bool takeTerrainHint(int32_t& x, int32_t& y, int32_t& z);
}  // namespace df3d_management
