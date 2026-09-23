#pragma once
#include "Console.h"
#include <cstdint>
namespace df3d_session {
bool start(DFHack::color_ostream& out);
void stop();
void update(bool mapLoaded,uint64_t epoch=0);
bool saving();
}
