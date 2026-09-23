// Standalone, engine-free test executable; compile with C++17 and threading.
#ifdef NDEBUG
#undef NDEBUG // This standalone test also checks assertions in Release builds.
#endif
#include "../src/profiling.h"
#include "../src/submission_metrics.h"
#include <cassert>
#include <set>
#include <thread>
using namespace df3d::profiling;
namespace {
double currentUs = 0;
int clockCalls = 0;
double fakeClock() { ++clockCalls; return currentUs; }
}
int main() {
    {
        using namespace df3d_godot::submission;
        Counters off(false);
        const int clocksBefore = clockCalls;
        for (int i = 0; i < 1000; ++i) {
            off.mesh(MeshSite::Terrain, 4, 6, 216);
            off.resource(MeshSite::Terrain);
            off.texture(TextureSite::Atlas, 4096);
        }
        assert(clockCalls == clocksBefore);
        for (const auto& mesh : off.meshes)
            assert(mesh.calls == 0 && mesh.bytes == 0 && mesh.resources == 0);
        for (const auto& texture : off.textures) assert(texture.calls == 0 && texture.bytes == 0);
        Counters deep(true);
        deep.resource(MeshSite::Terrain);
        deep.mesh(MeshSite::Terrain, 4, 6, 216);
        deep.mesh(MeshSite::Terrain, 3, 0, 144);
        deep.mesh(MeshSite::Batch, 7, 9, 400, 1);
        deep.texture(TextureSite::Atlas, uint64_t(1) << 33);
        deep.texture(TextureSite::Atlas, 12);
        const auto& terrain = deep.meshes[std::size_t(MeshSite::Terrain)];
        assert(terrain.calls == 2 && terrain.vertices == 7 && terrain.indices == 6);
        assert(terrain.bytes == 360 && terrain.resources == 1 && terrain.unknownChannels == 0);
        assert(deep.meshes[std::size_t(MeshSite::Batch)].unknownChannels == 1);
        assert(deep.meshes[std::size_t(MeshSite::Building)].calls == 0);
        assert(deep.textures[std::size_t(TextureSite::Atlas)].bytes == (uint64_t(1) << 33) + 12);
        assert(deep.textures[std::size_t(TextureSite::Atlas)].calls == 2);
        constexpr uint64_t seed=14695981039346656037ULL;
        const std::array<float,3> first{1,2,3}, depthChanged{1,7,3}, shapeChanged{2,7,3};
        const auto full=hashBytes(seed,first.data(),sizeof(first));
        const auto xz=[](const auto& value) {
            return hashBytes(hashBytes(seed,&value[0],sizeof(float)),&value[2],sizeof(float));
        };
        GeometryFingerprint previous{full,xz(first),true};
        assert(std::strcmp(streamRelation(previous,full,xz(first),true),"identical")==0);
        assert(std::strcmp(streamRelation(previous,hashBytes(seed,depthChanged.data(),sizeof(depthChanged)),xz(depthChanged),true),"y_only")==0);
        assert(std::strcmp(streamRelation(previous,hashBytes(seed,shapeChanged.data(),sizeof(shapeChanged)),xz(shapeChanged),true),"changed")==0);
        assert(std::strcmp(streamRelation(previous,full,xz(first),false),"unavailable")==0);
        assert(std::strcmp(streamRelation({},full,xz(first),true),"first")==0);
    }
    {
        Profiler deep(Mode::Deep, 4, fakeClock);
        double total = 0;
        currentUs = 0;
        { Scope fast("fast", &total, deep, 100); currentUs = 99; }
        { Scope slow("slow", &total, deep, 100); currentUs = 199; }
        const auto captured = deep.snapshot();
        assert(captured.events.size() == 1 && captured.events[0].name == "slow");
        assert(total == 0.199);
        clockCalls = 0;
    }
    assert(modeFromValues(nullptr, nullptr) == Mode::Off);
    assert(modeFromValues(nullptr, "1") == Mode::Basic);
    assert(modeFromValues("off", "1") == Mode::Off);
    assert(modeFromValues("", "1") == Mode::Off);
    assert(modeFromValues("invalid", "1") == Mode::Off);
    assert(modeFromValues("basic", nullptr) == Mode::Basic);
    assert(modeFromValues("deep", "1") == Mode::Deep);
    {
        Profiler off(Mode::Off, 4, fakeClock);
        double total = 17;
        { Scope scope("off", total, off); }
        assert(clockCalls == 0 && total == 17);
        assert(off.snapshot().events.empty());
    }
    {
        Profiler basic(Mode::Basic, 4, fakeClock);
        double total = 1;
        currentUs = 1000;
        { Scope scope("basic", total, basic); currentUs = 3500; }
        assert(clockCalls == 2 && total == 3.5);
        assert(basic.snapshot().events.empty());
    }
    {
        Profiler deep(Mode::Deep, 2, fakeClock);
        double total = 0;
        currentUs = 100;
        {
            Scope outer("outer", total, deep);
            currentUs = 200;
            { Scope inner("inner", nullptr, deep); currentUs = 400; }
            currentUs = 600;
        }
        { Scope overflow("overflow", total, deep); currentUs = 1600; }
        auto snapshot = deep.snapshot();
        assert(snapshot.events.size() == 2 && snapshot.dropped == 1);
        assert(snapshot.evictedThroughUs == 400);
        assert(snapshot.events[0].name == "outer" && snapshot.events[0].startUs == 100);
        assert(snapshot.events[0].durationUs == 500 && total == 1.5);
        assert(snapshot.events[1].name == "overflow" && snapshot.events[1].durationUs == 1000);
        assert(snapshot.events[0].thread == snapshot.events[1].thread);
        deep.clear();
        assert(deep.snapshot().events.empty() && deep.snapshot().dropped == 0);
        assert(deep.snapshot().evictedThroughUs == 0);
        assert(snapshot.events.size() == 2); // exported snapshot owns its data
        deep.record("after clear", 10, 5);
        assert(deep.snapshot().events.size() == 1 && deep.snapshot().events[0].name == "after clear");
    }
    {
        Profiler deep(Mode::Deep, 64);
        auto writer = [&] { for (int i = 0; i < 100; ++i) { Scope scope("worker", nullptr, deep); } };
        std::thread first(writer), second(writer);
        // Concurrent snapshot must be safe while workers append.
        auto intermediate = deep.snapshot();
        assert(intermediate.events.size() <= 64);
        first.join(); second.join();
        const auto snapshot = deep.snapshot();
        assert(snapshot.events.size() == 64 && snapshot.dropped == 136);
        for (const auto& event : snapshot.events) assert(event.thread != 0 && event.durationUs >= 0);
        for (size_t i = 1; i < snapshot.events.size(); ++i)
            assert(snapshot.events[i-1].startUs <= snapshot.events[i].startUs);
    }
    {
        Profiler deep(Mode::Deep, 2);
        std::thread first([&] { Scope scope("first", nullptr, deep); });
        first.join();
        std::thread second([&] { Scope scope("second", nullptr, deep); });
        second.join();
        const auto snapshot = deep.snapshot();
        assert(snapshot.events.size() == 2);
        assert(snapshot.events[0].thread != snapshot.events[1].thread);
    }
    {
        Profiler bounded(Mode::Deep, Profiler::MaxEvents + 5, fakeClock);
        for (size_t i = 0; i < Profiler::MaxEvents + 5; ++i) bounded.record("bounded", double(i), 2);
        const auto snapshot = bounded.snapshot();
        assert(snapshot.events.size() == Profiler::MaxEvents && snapshot.dropped == 5);
        assert(snapshot.events.front().startUs == 5);
        assert(snapshot.events.back().startUs == double(Profiler::MaxEvents + 4));
        Profiler zero(Mode::Deep, 0, fakeClock);
        zero.record("zero", 1, 2);
        assert(zero.snapshot().events.empty() && zero.snapshot().dropped == 1);
    }
    {
        // Multiple wraps of a non-power-of-two ring; equal timestamps retain
        // recording order and out-of-order completed scopes sort on export.
        Profiler deep(Mode::Deep, 3, fakeClock);
        for (int i = 0; i < 8; ++i) deep.record("discarded", double(i), 1);
        deep.record("late-start", 30, 1);
        deep.record("first-tie", 20, 1);
        deep.record("second-tie", 20, 2);
        const auto snapshot = deep.snapshot();
        assert(snapshot.events.size() == 3 && snapshot.dropped == 8);
        assert(snapshot.events[0].name == "first-tie");
        assert(snapshot.events[1].name == "second-tie");
        assert(snapshot.events[2].name == "late-start");
    }
}
