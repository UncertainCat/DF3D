// DF raw-file tokenizer (layer 4 shared infrastructure, engine-agnostic).
//
// DF raws are plain text where everything outside square brackets is a
// comment and every `[A:B:C]` is a token with colon-separated arguments.
// Plant and creature identifiers may contain spaces and apostrophes
// (`[PLANT_GRAPHICS:DOG'S TOOTH GRASS]`), so arguments are taken verbatim.
#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace df3d::assets {

struct RawToken {
  std::vector<std::string> args;  // args[0] is the token name
  uint32_t line = 0;              // 1-based line of the opening bracket

  const std::string& name() const { return args[0]; }
  size_t argc() const { return args.size(); }
  // Argument i or "" when absent.
  std::string_view arg(size_t i) const {
    return i < args.size() ? std::string_view(args[i]) : std::string_view();
  }
};

// Tokenizes a whole raw file. Unterminated brackets are dropped.
std::vector<RawToken> tokenizeRaw(std::string_view text);

// The `[OBJECT:X]` header of a raw file ("" when none).
std::string rawObjectType(const std::vector<RawToken>& tokens);

// Whole-file read; false (with err set) on failure.
bool readTextFile(const std::string& path, std::string& out, std::string& err);

// Parses a non-negative integer argument; false when not a number.
bool parseInt(std::string_view s, int& out);

// FNV-1a 64 over bytes, continuing from `seed`.
uint64_t fnv1a64(std::string_view bytes, uint64_t seed = 14695981039346656037ull);

}  // namespace df3d::assets
