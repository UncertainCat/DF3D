#include "df3d_assets/raw_tokens.h"

#include <fstream>
#include <sstream>

namespace df3d::assets {

std::vector<RawToken> tokenizeRaw(std::string_view text) {
  std::vector<RawToken> out;
  uint32_t line = 1;
  size_t i = 0;
  const size_t n = text.size();
  while (i < n) {
    const char c = text[i];
    if (c == '\n') {
      ++line;
      ++i;
      continue;
    }
    if (c != '[') {
      ++i;
      continue;
    }
    const size_t close = text.find(']', i + 1);
    if (close == std::string_view::npos) break;
    // A stray '[' before the closing bracket starts a new token instead.
    const size_t nextOpen = text.find('[', i + 1);
    if (nextOpen != std::string_view::npos && nextOpen < close) {
      for (size_t k = i; k < nextOpen; ++k)
        if (text[k] == '\n') ++line;
      i = nextOpen;
      continue;
    }
    RawToken tok;
    tok.line = line;
    std::string_view body = text.substr(i + 1, close - i - 1);
    size_t start = 0;
    while (true) {
      const size_t colon = body.find(':', start);
      if (colon == std::string_view::npos) {
        tok.args.emplace_back(body.substr(start));
        break;
      }
      tok.args.emplace_back(body.substr(start, colon - start));
      start = colon + 1;
    }
    // Strip a trailing CR from the last argument of bracket-per-line files.
    for (auto& a : tok.args) {
      while (!a.empty() && (a.back() == '\r' || a.back() == '\n')) a.pop_back();
    }
    for (size_t k = i; k < close; ++k)
      if (text[k] == '\n') ++line;
    if (!tok.args.empty() && !tok.args[0].empty()) out.push_back(std::move(tok));
    i = close + 1;
  }
  return out;
}

std::string rawObjectType(const std::vector<RawToken>& tokens) {
  for (const RawToken& t : tokens) {
    if (t.name() == "OBJECT" && t.argc() >= 2) return t.args[1];
  }
  return {};
}

bool readTextFile(const std::string& path, std::string& out, std::string& err) {
  std::ifstream in(path, std::ios::binary);
  if (!in) {
    err = "cannot open " + path;
    return false;
  }
  std::ostringstream ss;
  ss << in.rdbuf();
  out = ss.str();
  return true;
}

bool parseInt(std::string_view s, int& out) {
  if (s.empty()) return false;
  size_t i = 0;
  bool neg = false;
  if (s[0] == '-') {
    neg = true;
    i = 1;
    if (s.size() == 1) return false;
  }
  long v = 0;
  for (; i < s.size(); ++i) {
    const char c = s[i];
    if (c < '0' || c > '9') return false;
    v = v * 10 + (c - '0');
    if (v > 1000000000L) return false;
  }
  out = static_cast<int>(neg ? -v : v);
  return true;
}

uint64_t fnv1a64(std::string_view bytes, uint64_t seed) {
  uint64_t h = seed;
  for (unsigned char c : bytes) {
    h ^= c;
    h *= 1099511628211ull;
  }
  return h;
}

}  // namespace df3d::assets
