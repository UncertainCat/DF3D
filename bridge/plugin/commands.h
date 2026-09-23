#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <string>

#include "mirror_generated.h"

namespace df3d_commands {

struct Result {
    uint64_t seq = 0;
    df3d::mirror::CommandStatus status = df3d::mirror::CommandStatus::Ok;
    std::string message;
};

// Hooks into the bridge's change detection so the effect of a command
// reaches the mirror on the next update instead of the next rescan: the
// touched terrain blocks go into the immediate scan (terrain hints), the
// touched item / building is re-visited (entity hints).
struct Hooks {
    void (*hintBlock)(int32_t bx, int32_t by, int32_t bz) = nullptr;
    void (*hintItem)(int32_t id) = nullptr;
    void (*hintBuilding)(int32_t id) = nullptr;
};

struct Stats {
    uint64_t executed = 0, ok = 0, rejected = 0, unknown = 0;
    uint64_t tilesVisited = 0, tilesApplied = 0, plantsMarked = 0, entitiesChanged = 0;
    double execUsLast = 0, execUsEma = 0, execUsMax = 0;  // per command
    std::string lastMessage;
};

void setHooks(const Hooks& hooks);
const Stats& stats();
void resetStatsMax();
void reset();  // map load: also abandons any partially executed command

// Once per command drain (one update): the designation job index is built
// lazily from DF's job list for every command of the drain.
void beginDrain();

// Executes one already-verified Command (any payload but SetPause, which
// the bridge handles itself). `buf`/`len` are the command's bytes (copied
// when the work outlives this call). Returns true with `out` filled when the
// command finished; false when the deadline passed mid-walk of a dig /
// smooth rectangle: the work stays pending here, and resume() continues it
// on later updates until it returns true with the result. Sent is not
// succeeded: no result is produced before the walk completed. Requires a
// loaded map (else Rejected).
bool execute(const uint8_t* buf, size_t len, const df3d::mirror::Command& cmd,
             std::chrono::steady_clock::time_point deadline, Result& out);
bool pending();
bool resume(std::chrono::steady_clock::time_point deadline, Result& out);

}  // namespace df3d_commands
