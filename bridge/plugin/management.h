#pragma once
#include <cstdint>
namespace DFHack {
class color_ostream;
}
namespace df3d_management {
void update(DFHack::color_ostream& out, uint64_t worldEpoch, bool saving);
void stop();
void printTiming(DFHack::color_ostream& out);
bool takeMutation();
bool takeTerrainHint(int32_t& x, int32_t& y, int32_t& z);
}  // namespace df3d_management
