// Validate live recordings through the engine-independent replay API.
#include "fixture_io.h"
#include "wm/world_model.h"
#include <algorithm>
#include <iostream>
#include <stdexcept>

static void require(bool value, const std::string& message) {
    if (!value) throw std::runtime_error(message);
}
static void inspect(wm::WorldModel& model, const char* path, wm::TilePos tile,
                    wm::UnitId unit, int priority) {
    std::string error;
    df3d::mirror::FixtureStream recording;
    require(df3d::mirror::loadFixtureFile(path, recording, error), error);
    require(recording.snapshots.size() >= 2, "recording needs Full and mutation publications");
    size_t full = 0, delta = 0;
    for (const auto* snapshot : recording.snapshots) {
        full += snapshot->terrain_scope() == df3d::mirror::TerrainScope::Full;
        delta += snapshot->terrain_scope() == df3d::mirror::TerrainScope::Delta;
    }
    require(full > 0 && delta > 0, "recording lacks Full/Delta terrain evidence");
    require(wm::loadFixtureFile(model, path, error), error);
    const auto observed = model.tileAt(tile);
    require(observed.has_value(), "recorded tile unavailable");
    require(observed->designationPriority == priority && observed->designationMarker,
            "designation priority/marker disagrees with native expected state");
    require(observed->designation == wm::DesignationKind::Dig, "designation is not the native Mine/Default kind");
    const auto ids = model.unitIds();
    require(std::find(ids.begin(), ids.end(), unit) != ids.end(), "known native unit missing");
    std::cout << "FIXTURE_OBSERVATION snapshots=" << recording.snapshots.size()
              << " schema=" << recording.snapshots.front()->schema_version()
              << " full=" << full << " delta=" << delta << " units=" << ids.size()
              << " priority=" << int(observed->designationPriority) << " marker=1\n";
}
int main(int argc, char** argv) {
    if (argc != 7) {
        std::cerr << "fixture_evidence before.df3dfix after.df3dfix x y z unit_id\n";
        return 2;
    }
    try {
        const wm::TilePos tile{std::stoi(argv[3]), std::stoi(argv[4]), std::stoi(argv[5])};
        const auto unit = static_cast<wm::UnitId>(std::stoll(argv[6]));
        wm::WorldModel model;
        inspect(model, argv[1], tile, unit, 2);
        const auto oldGeneration = model.sessionGeneration();
        model.resetSession();
        require(!model.hasData() && model.unitIds().empty() && !model.tileAt(tile),
                "session reset retained old recorded state");
        require(model.sessionGeneration() != oldGeneration, "session generation did not change");
        inspect(model, argv[2], tile, unit, 3);
        std::cout << "RECORDED_FIXTURE_PASS\n";
    } catch (const std::exception& error) {
        std::cerr << "RECORDED_FIXTURE_FAIL: " << error.what() << '\n';
        return 1;
    }
}
