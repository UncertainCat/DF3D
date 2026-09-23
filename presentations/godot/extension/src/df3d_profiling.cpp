#include "df3d_world.h"
#include "submission_uploads.h"
#include "submission_details.h"
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/classes/time.hpp>
#include <atomic>
#include <cstdlib>
#include <cstring>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

namespace df3d_godot {
godot::Dictionary Df3dWorld::engine_submission_stats() const {
    godot::Dictionary result;
    const auto& stats = submission::counters();
    if (!stats.enabled()) return result;
    submission::MeshCounts total;
    const auto writeMesh = [&](const godot::String& prefix, const submission::MeshCounts& value) {
        result[prefix + godot::String("mesh_surface_calls")] = int64_t(value.calls);
        result[prefix + godot::String("mesh_vertices")] = int64_t(value.vertices);
        result[prefix + godot::String("mesh_indices")] = int64_t(value.indices);
        result[prefix + godot::String("mesh_payload_bytes")] = int64_t(value.bytes);
        result[prefix + godot::String("mesh_resources")] = int64_t(value.resources);
        result[prefix + godot::String("mesh_unknown_channels")] = int64_t(value.unknownChannels);
    };
    for (std::size_t i = 0; i < stats.meshes.size(); ++i) {
        const auto& value = stats.meshes[i];
        writeMesh(godot::String(submission::meshNames[i]) + godot::String("_"), value);
        total.calls += value.calls; total.vertices += value.vertices; total.indices += value.indices;
        total.bytes += value.bytes; total.resources += value.resources; total.unknownChannels += value.unknownChannels;
    }
    writeMesh("", total);
    submission::TextureCounts textures;
    for (std::size_t i = 0; i < stats.textures.size(); ++i) {
        const auto& value = stats.textures[i];
        const godot::String prefix = godot::String(submission::textureNames[i]) + godot::String("_");
        result[prefix + godot::String("texture_create_calls")] = int64_t(value.calls);
        result[prefix + godot::String("texture_payload_bytes")] = int64_t(value.bytes);
        textures.calls += value.calls; textures.bytes += value.bytes;
    }
    result["texture_create_calls"] = int64_t(textures.calls);
    result["texture_payload_bytes"] = int64_t(textures.bytes);
    const auto& detail=submission::details();
    result["detail_building_events"]=int64_t(detail.buildingEvents);
    result["detail_building_window_events"]=int64_t(detail.reasons[0]);
    result["detail_building_semantic_events"]=int64_t(detail.reasons[1]);
    result["detail_building_layout_events"]=int64_t(detail.reasons[2]);
    result["detail_building_visibility_events"]=int64_t(detail.reasons[3]);
    result["detail_building_identical_events"]=int64_t(detail.identicalEvents);
    result["detail_building_identical_bytes"]=int64_t(detail.identicalBytes);
    result["detail_building_y_only_events"]=int64_t(detail.yOnlyEvents);
    result["detail_building_hash_us"]=int64_t(detail.buildingHashUs);
    result["detail_batch_copied_bytes"]=int64_t(detail.batchCopiedBytes);
    result["detail_batch_record_us"]=int64_t(detail.batchRecordUs);
    result["detail_batch_unchanged_copied_bytes"]=int64_t(detail.batchUnchangedCopiedBytes);
    result["detail_batch_changed_sources"]=int64_t(detail.batchChangedSources);
    result["detail_batch_unchanged_sources"]=int64_t(detail.batchUnchangedSources);
    result["detail_batch_new_sources"]=int64_t(detail.batchNewSources);
    result["detail_batch_cancelled"]=int64_t(detail.batchCancelled);
    result["detail_batch_cancelled_copy_bytes"]=int64_t(detail.batchCancelledCopyBytes);
    result["detail_batch_cancelled_upload_bytes"]=int64_t(detail.batchCancelledUploadBytes);
    result["detail_batch_cached_array_hits"]=int64_t(detail.batchCachedArrayHits);
    result["detail_batch_array_readbacks"]=int64_t(detail.batchArrayReadbacks);
    return result;
}

godot::Dictionary Df3dWorld::engine_submission_details() {
    auto& detail=submission::details();
    godot::Dictionary result;
    result["enabled"]=detail.enabled;result["poll"]=int64_t(detail.poll);
    result["buildings"]=detail.buildings;result["batches"]=detail.batches;
    result["building_dropped"]=int64_t(detail.buildingDropped);result["batch_dropped"]=int64_t(detail.batchDropped);
    detail.buildings=godot::Array();detail.batches=godot::Array();
    detail.buildingDropped=0;detail.batchDropped=0;
    return result;
}

namespace {
double currentThreadCpuMs() {
#ifdef _WIN32
    FILETIME creation{}, exit{}, kernel{}, user{};
    if (!GetThreadTimes(GetCurrentThread(), &creation, &exit, &kernel, &user)) return -1.0;
    const auto ticks = [](const FILETIME& value) {
        return (uint64_t(value.dwHighDateTime) << 32) | uint64_t(value.dwLowDateTime);
    };
    return double(ticks(kernel) + ticks(user)) / 10000.0;
#else
    return -1.0;
#endif
}

// Opt-in nonblocking queue marker. At most one callback is outstanding. Request
// and completion sequences publish the plain payload across threads; only the
// main thread requests/reads, and never rewrites an outstanding request.
struct RenderBoundary {
    std::atomic<uint64_t> requested{0}, completed{0};
    uint64_t requestedUs{}, reachedUs{}, thread{};
    double cpuMs{-1}, previousCpuMs{-1}, intervalCpuMs{-1};
    int64_t cycles{-1}, previousCycles{-1}, intervalCycles{-1};
    uint64_t previousUs{}, intervalUs{};
};
RenderBoundary renderBoundary;
void renderBoundaryCheckpoint() {
    auto& b = renderBoundary;
    const auto sequence = b.requested.load(std::memory_order_acquire);
    const auto now = godot::Time::get_singleton()->get_ticks_usec();
    const auto thread = df3d::profiling::Profiler::currentThreadId();
    const bool sameThread = b.thread == thread && b.previousUs != 0;
    b.cpuMs = currentThreadCpuMs();
    b.cycles = -1;
#ifdef _WIN32
    ULONG64 cycles = 0;
    if (QueryThreadCycleTime(GetCurrentThread(), &cycles)) b.cycles = int64_t(cycles);
#endif
    b.intervalCpuMs = sameThread && b.previousCpuMs >= 0 && b.cpuMs >= b.previousCpuMs
        ? b.cpuMs - b.previousCpuMs : -1;
    b.intervalCycles = sameThread && b.previousCycles >= 0 && b.cycles >= b.previousCycles
        ? b.cycles - b.previousCycles : -1;
    b.intervalUs = sameThread ? now - b.previousUs : 0;
    b.reachedUs = now; b.thread = thread;
    b.previousUs = now; b.previousCpuMs = b.cpuMs; b.previousCycles = b.cycles;
    b.completed.store(sequence, std::memory_order_release);
}

// No scene objects or captured pointers cross onto the render thread. One
// bounded checkpoint survives between calls; force_sync completes its callback
// before the main thread reads the release-published sequence.
std::atomic<uint64_t> syncCheckpointSequence{0}, syncCheckpointThread{0};
std::atomic<double> syncCheckpointCpu{-1.0}, syncCheckpointDelta{-1.0}, syncCheckpointTime{0.0};

void renderSyncCheckpoint() {
    auto& profiler = df3d::profiling::global();
    const auto thread = df3d::profiling::Profiler::currentThreadId();
    const double cpu = currentThreadCpuMs();
    const double timestamp = profiler.nowUs();
    const auto previousThread = syncCheckpointThread.load(std::memory_order_relaxed);
    const double previousCpu = syncCheckpointCpu.load(std::memory_order_relaxed);
    const double delta = previousThread == thread && previousCpu >= 0.0 && cpu >= previousCpu
        ? cpu - previousCpu : -1.0;
    syncCheckpointCpu.store(cpu, std::memory_order_relaxed);
    syncCheckpointDelta.store(delta, std::memory_order_relaxed);
    syncCheckpointTime.store(timestamp, std::memory_order_relaxed);
    syncCheckpointThread.store(thread, std::memory_order_relaxed);
    profiler.record("render.sync_checkpoint", timestamp, 0.0);
    syncCheckpointSequence.fetch_add(1, std::memory_order_release);
}
}

godot::Dictionary Df3dWorld::profiling_cpu_clock() const {
    const char* boundaries = std::getenv("DF3D_FRAME_BOUNDARIES");
    if (df3d::profiling::global().mode() != df3d::profiling::Mode::Deep &&
        (!boundaries || std::strcmp(boundaries, "1") != 0)) return {};
    godot::Dictionary result;
    result["thread_cpu_ms"]=currentThreadCpuMs();
    result["thread_cycles"]=int64_t(-1);
#ifdef _WIN32
    ULONG64 cycles=0;
    if(QueryThreadCycleTime(GetCurrentThread(),&cycles))result["thread_cycles"]=int64_t(cycles);
#endif
    return result;
}

godot::Dictionary Df3dWorld::profiling_render_boundary(bool enqueue) {
    const char* requested = std::getenv("DF3D_FRAME_BOUNDARIES");
    if (!requested || std::strcmp(requested, "1") != 0) return {};
    auto* os = godot::OS::get_singleton();
    auto* server = godot::RenderingServer::get_singleton();
    if (!os || !server || os->get_thread_caller_id() != os->get_main_thread_id()) return {};
    auto& b = renderBoundary;
    const auto sequence = b.requested.load(std::memory_order_acquire);
    if (b.completed.load(std::memory_order_acquire) != sequence) return {};
    godot::Dictionary result;
    if (enqueue) {
        b.requestedUs = godot::Time::get_singleton()->get_ticks_usec();
        b.requested.store(sequence + 1, std::memory_order_release);
        server->call_on_render_thread(callable_mp_static(&renderBoundaryCheckpoint));
        result["sequence"] = int64_t(sequence + 1);
    } else if (sequence != 0) {
        result["sequence"] = int64_t(sequence);
        result["requested_us"] = int64_t(b.requestedUs);
        result["reached_us"] = int64_t(b.reachedUs);
        result["queue_delay_ms"] = double(b.reachedUs - b.requestedUs) / 1000.0;
        result["checkpoint_interval_ms"] = b.intervalUs ? double(b.intervalUs)/1000.0 : -1.0;
        result["render_thread_cpu_ms"] = b.intervalCpuMs;
        result["render_thread_cycles"] = b.intervalCycles;
        result["separate_thread"] = b.thread != df3d::profiling::Profiler::currentThreadId();
    }
    return result;
}

godot::Dictionary Df3dWorld::profiling_render_sync() {
    auto& profiler = df3d::profiling::global();
    const char* requested = std::getenv("DF3D_SYNC_PROBE");
    if (profiler.mode() != df3d::profiling::Mode::Deep || !requested || std::strcmp(requested, "1") != 0)
        return {};
    auto* os = godot::OS::get_singleton();
    if (!os || os->get_thread_caller_id() != os->get_main_thread_id()) return {};
    auto* server = godot::RenderingServer::get_singleton();
    if (!server) return {};
    const auto sequence = syncCheckpointSequence.load(std::memory_order_acquire);
    server->call_on_render_thread(callable_mp_static(&renderSyncCheckpoint));
    const double cpuBefore = currentThreadCpuMs();
    const double start = profiler.nowUs();
    server->force_sync();
    const double end = profiler.nowUs();
    const double cpuAfter = currentThreadCpuMs();
    profiler.record("engine.explicit_render_sync", start, end - start);
    const bool completed = syncCheckpointSequence.load(std::memory_order_acquire) != sequence;
    godot::Dictionary result;
    result["wall_ms"] = (end - start) / 1000.0;
    result["main_cpu_ms"] = cpuBefore >= 0.0 && cpuAfter >= cpuBefore ? cpuAfter - cpuBefore : -1.0;
    // Whole render-thread CPU interval since the prior checkpoint, not CPU
    // consumed only during this force_sync wall interval.
    result["render_cpu_ms"] = completed
        ? syncCheckpointDelta.load(std::memory_order_relaxed) : -1.0;
    result["render_thread_id"] = int64_t(completed ? syncCheckpointThread.load(std::memory_order_relaxed) : 0);
    result["checkpoint_time_us"] = completed ? syncCheckpointTime.load(std::memory_order_relaxed) : 0.0;
    return result;
}

double Df3dWorld::profiling_clock_usec() const {
    auto& profiler = df3d::profiling::global();
    return profiler.mode() == df3d::profiling::Mode::Off ? 0.0 : profiler.nowUs();
}

godot::Dictionary Df3dWorld::profiling_trace() const {
    godot::Dictionary result;
    const auto& profiler = df3d::profiling::global();
    result["mode"] = df3d::profiling::modeName(profiler.mode());
    result["thread_id"] = int64_t(df3d::profiling::Profiler::currentThreadId());
    godot::Array events;
    if (profiler.mode() == df3d::profiling::Mode::Deep) {
        const auto snapshot = profiler.snapshot();
        for (const auto& event : snapshot.events) {
            godot::Dictionary record;
            record["name"] = godot::String(event.name.c_str());
            record["cat"] = "native";
            record["ph"] = "X";
            record["pid"] = 1;
            record["tid"] = int64_t(event.thread);
            record["ts"] = event.startUs;
            record["dur"] = event.durationUs;
            events.append(record);
        }
        result["dropped_events"] = int64_t(snapshot.dropped);
        result["native_evicted_through_us"] = snapshot.evictedThroughUs;
    } else result["dropped_events"] = int64_t(0);
    result["traceEvents"] = events;
    return result;
}
}
