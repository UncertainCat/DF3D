// Fixture container I/O (mirror layer).
//
// File format: 8-byte magic "DF3DFIX1", then a sequence of
// size-prefixed FlatBuffers Snapshot messages, matching how snapshots will
// arrive from shared memory.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "mirror_generated.h"

namespace df3d::mirror {

inline constexpr char kFixtureMagic[8] = {'D', 'F', '3', 'D', 'F', 'I', 'X', '1'};

// A loaded fixture: owns the raw bytes; `snapshots` point into them.
struct FixtureStream {
  std::vector<uint8_t> data;
  std::vector<const Snapshot*> snapshots;
};

// Parses fixture bytes. Verifies magic and every message with the FlatBuffers
// verifier. On failure returns false and sets `error`.
bool parseFixture(std::vector<uint8_t> bytes, FixtureStream& out, std::string& error);

// Reads and parses a fixture file. On failure returns false and sets `error`.
bool loadFixtureFile(const std::string& path, FixtureStream& out, std::string& error);

// Serializes size-prefixed snapshot buffers (each produced by
// FlatBufferBuilder::FinishSizePrefixed) into fixture bytes with magic.
std::vector<uint8_t> assembleFixture(const std::vector<std::vector<uint8_t>>& snapshotBuffers);

bool writeFixtureFile(const std::string& path, const std::vector<uint8_t>& fixtureBytes,
                      std::string& error);

}  // namespace df3d::mirror
