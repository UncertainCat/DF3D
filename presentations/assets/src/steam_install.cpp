#include "df3d_assets/steam_install.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>

#include "df3d_assets/raw_tokens.h"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace fs = std::filesystem;

namespace df3d::assets {

// --- VDF ---

const VdfNode* VdfNode::child(std::string_view key) const {
  auto it = children.find(std::string(key));
  return it == children.end() ? nullptr : it->second.get();
}

std::string VdfNode::value(std::string_view key, std::string fallback) const {
  auto it = values.find(std::string(key));
  return it == values.end() ? fallback : it->second;
}

namespace {

struct VdfLexer {
  std::string_view s;
  size_t i = 0;
  enum Kind { Str, Open, Close, End };

  void skipWs() {
    while (i < s.size()) {
      const char c = s[i];
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
        ++i;
      } else if (c == '/' && i + 1 < s.size() && s[i + 1] == '/') {
        while (i < s.size() && s[i] != '\n') ++i;
      } else {
        break;
      }
    }
  }
  Kind next(std::string& text) {
    skipWs();
    if (i >= s.size()) return End;
    const char c = s[i];
    if (c == '{') {
      ++i;
      return Open;
    }
    if (c == '}') {
      ++i;
      return Close;
    }
    text.clear();
    if (c == '"') {
      ++i;
      while (i < s.size() && s[i] != '"') {
        if (s[i] == '\\' && i + 1 < s.size()) {
          ++i;
          const char e = s[i];
          text.push_back(e == 'n' ? '\n' : e == 't' ? '\t' : e);
        } else {
          text.push_back(s[i]);
        }
        ++i;
      }
      if (i < s.size()) ++i;  // closing quote
      return Str;
    }
    while (i < s.size() && s[i] != ' ' && s[i] != '\t' && s[i] != '\r' && s[i] != '\n' &&
           s[i] != '{' && s[i] != '}') {
      text.push_back(s[i++]);
    }
    return Str;
  }
};

bool parseVdfBlock(VdfLexer& lx, VdfNode& node, int depth, std::string& err) {
  std::string key, val;
  while (true) {
    const VdfLexer::Kind k = lx.next(key);
    if (k == VdfLexer::End) {
      if (depth == 0) return true;
      err = "vdf: unexpected end of input inside a block";
      return false;
    }
    if (k == VdfLexer::Close) {
      if (depth == 0) {
        err = "vdf: unexpected '}' at top level";
        return false;
      }
      return true;
    }
    if (k != VdfLexer::Str) {
      err = "vdf: expected a key";
      return false;
    }
    const VdfLexer::Kind v = lx.next(val);
    if (v == VdfLexer::Str) {
      node.values[key] = val;
    } else if (v == VdfLexer::Open) {
      auto child = std::make_unique<VdfNode>();
      if (!parseVdfBlock(lx, *child, depth + 1, err)) return false;
      node.children[key] = std::move(child);
    } else {
      err = "vdf: key '" + key + "' has no value";
      return false;
    }
  }
}

}  // namespace

bool parseVdf(std::string_view text, VdfNode& root, std::string& err) {
  VdfLexer lx{text};
  return parseVdfBlock(lx, root, 0, err);
}

std::vector<SteamLibrary> parseLibraryFolders(const VdfNode& root) {
  std::vector<SteamLibrary> out;
  const VdfNode* lf = root.child("libraryfolders");
  if (!lf) return out;
  // Keys are "0", "1", ...; keep numeric order.
  std::vector<std::pair<int, const VdfNode*>> ordered;
  for (const auto& [k, v] : lf->children) {
    int idx = 0;
    if (!parseInt(k, idx)) idx = 1 << 30;
    ordered.emplace_back(idx, v.get());
  }
  std::sort(ordered.begin(), ordered.end(),
            [](const auto& a, const auto& b) { return a.first < b.first; });
  for (const auto& [idx, node] : ordered) {
    SteamLibrary lib;
    lib.path = node->value("path");
    if (lib.path.empty()) continue;
    if (const VdfNode* apps = node->child("apps")) {
      for (const auto& [app, size] : apps->values) lib.apps.push_back(app);
    }
    out.push_back(std::move(lib));
  }
  return out;
}

std::optional<AppManifest> parseAppManifest(const VdfNode& root) {
  const VdfNode* st = root.child("AppState");
  if (!st) return std::nullopt;
  AppManifest m;
  m.appId = st->value("appid");
  m.name = st->value("name");
  m.installDir = st->value("installdir");
  m.buildId = st->value("buildid");
  if (m.installDir.empty()) return std::nullopt;
  return m;
}

// --- PE timestamp ---

uint32_t peTimestampOf(std::string_view b) {
  auto u16 = [&](size_t o) -> uint32_t {
    return static_cast<uint8_t>(b[o]) | (static_cast<uint8_t>(b[o + 1]) << 8);
  };
  auto u32 = [&](size_t o) -> uint32_t {
    return u16(o) | (u16(o + 2) << 16);
  };
  if (b.size() < 0x40 || b[0] != 'M' || b[1] != 'Z') return 0;
  const uint32_t pe = u32(0x3C);
  if (pe + 12 > b.size()) return 0;
  if (b[pe] != 'P' || b[pe + 1] != 'E' || b[pe + 2] != 0 || b[pe + 3] != 0) return 0;
  return u32(pe + 8);
}

uint32_t readPeTimestamp(const std::string& exePath) {
  std::ifstream in(exePath, std::ios::binary);
  if (!in) return 0;
  std::string head(4096, '\0');
  in.read(head.data(), static_cast<std::streamsize>(head.size()));
  head.resize(static_cast<size_t>(in.gcount()));
  return peTimestampOf(head);
}

// --- paths ---

std::string joinPath(std::string_view a, std::string_view b) {
  std::string s(a);
  while (!s.empty() && (s.back() == '/' || s.back() == '\\')) s.pop_back();
  s.push_back('/');
  size_t i = 0;
  while (i < b.size() && (b[i] == '/' || b[i] == '\\')) ++i;
  s.append(b.substr(i));
  for (char& c : s)
    if (c == '\\') c = '/';
  return s;
}

std::string parentPath(std::string_view p) {
  std::string s(p);
  for (char& c : s)
    if (c == '\\') c = '/';
  while (!s.empty() && s.back() == '/') s.pop_back();
  const size_t k = s.find_last_of('/');
  return k == std::string::npos ? std::string() : s.substr(0, k);
}

bool fileExists(const std::string& path) {
  std::error_code ec;
  return fs::is_regular_file(fs::path(path), ec);
}

bool dirExists(const std::string& path) {
  std::error_code ec;
  return fs::is_directory(fs::path(path), ec);
}

// --- discovery ---

namespace {

std::vector<std::string> steamRootCandidates(const LocateOptions& opts, std::string& log) {
  std::vector<std::string> out;
  if (!opts.steamRoot.empty()) {
    out.push_back(opts.steamRoot);
    return out;
  }
  if (const char* e = std::getenv("DF3D_STEAM_ROOT"); e && *e) {
    out.emplace_back(e);
    log += "  DF3D_STEAM_ROOT=" + std::string(e) + "\n";
  }
#ifdef _WIN32
  for (HKEY hive : {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
    char buf[1024];
    DWORD size = sizeof(buf);
    const LSTATUS st = RegGetValueA(hive, "Software\\Valve\\Steam",
                                    hive == HKEY_CURRENT_USER ? "SteamPath" : "InstallPath",
                                    RRF_RT_REG_SZ, nullptr, buf, &size);
    if (st == ERROR_SUCCESS && size > 1) {
      out.emplace_back(buf);
      log += std::string("  registry ") + (hive == HKEY_CURRENT_USER ? "HKCU" : "HKLM") +
             " Steam path: " + buf + "\n";
    }
  }
  out.emplace_back("C:/Program Files (x86)/Steam");
#else
  if (const char* home = std::getenv("HOME"); home && *home) {
    out.push_back(joinPath(home, ".steam/steam"));
    out.push_back(joinPath(home, ".local/share/Steam"));
  }
#endif
  return out;
}

bool readManifestFor(const std::string& steamappsDir, AppManifest& out, std::string& log) {
  const std::string manifest =
      joinPath(steamappsDir, std::string("appmanifest_") + kDfSteamAppId + ".acf");
  std::string text, err;
  if (!readTextFile(manifest, text, err)) return false;
  VdfNode root;
  if (!parseVdf(text, root, err)) {
    log += "  " + manifest + ": " + err + "\n";
    return false;
  }
  auto m = parseAppManifest(root);
  if (!m) {
    log += "  " + manifest + ": no AppState/installdir\n";
    return false;
  }
  out = *m;
  return true;
}

}  // namespace

std::optional<InstallInfo> locateInstall(const LocateOptions& opts, std::string& err) {
  std::string log;
  InstallInfo info;

  std::string override = opts.installOverride;
  if (override.empty()) {
    if (const char* e = std::getenv("DF3D_DF_PATH"); e && *e) override = e;
  }
  if (!override.empty()) {
    info.root = joinPath(override, "");
    info.root.pop_back();
    info.via = "explicit path override";
    if (!dirExists(info.root)) {
      err = "Dwarf Fortress install override does not exist: " + info.root +
            "\nSet DF3D_DF_PATH (or the override option) to the directory containing "
            "'Dwarf Fortress.exe' and data/vanilla, or unset it to use Steam discovery.";
      return std::nullopt;
    }
    // A Steam library layout puts the manifest two levels up.
    AppManifest m;
    const std::string steamapps = parentPath(parentPath(info.root));
    if (!steamapps.empty() && readManifestFor(steamapps, m, log)) info.buildId = m.buildId;
  } else {
    const auto roots = steamRootCandidates(opts, log);
    bool found = false;
    for (const std::string& root : roots) {
      const std::string lfPath = joinPath(root, "steamapps/libraryfolders.vdf");
      std::string text, perr;
      if (!readTextFile(lfPath, text, perr)) {
        log += "  no " + lfPath + "\n";
        continue;
      }
      VdfNode lfRoot;
      if (!parseVdf(text, lfRoot, perr)) {
        log += "  " + lfPath + ": " + perr + "\n";
        continue;
      }
      const auto libs = parseLibraryFolders(lfRoot);
      log += "  " + lfPath + ": " + std::to_string(libs.size()) + " libraries\n";
      for (const SteamLibrary& lib : libs) {
        const bool listed =
            std::find(lib.apps.begin(), lib.apps.end(), kDfSteamAppId) != lib.apps.end();
        const std::string steamapps = joinPath(lib.path, "steamapps");
        AppManifest m;
        if (!readManifestFor(steamapps, m, log)) {
          if (listed) log += "  library " + lib.path + " lists app but has no manifest\n";
          continue;
        }
        info.root = joinPath(joinPath(steamapps, "common"), m.installDir);
        info.buildId = m.buildId;
        info.via = "Steam library " + lib.path + (listed ? "" : " (manifest only)");
        found = true;
        break;
      }
      if (found) break;
    }
    if (!found) {
      err = "Dwarf Fortress (Steam app " + std::string(kDfSteamAppId) +
            ") was not found in any Steam library.\nSearched:\n" + log +
            "DF3D requires the Steam edition; Classic and itch.io layouts are not "
            "supported. Install it through Steam, or point DF3D_DF_PATH at the install directory.";
      return std::nullopt;
    }
  }

  if (!dirExists(info.root)) {
    err = "Steam manifest names an install directory that does not exist: " + info.root +
          "\nVerify the game files in Steam.";
    return std::nullopt;
  }
  const std::string exe = joinPath(info.root, "Dwarf Fortress.exe");
  info.peTimestamp = readPeTimestamp(exe);
  if (!dirExists(joinPath(info.root, "data/vanilla"))) {
    err = "The install at " + info.root +
          " has no data/vanilla directory; it is not a recognizable Dwarf Fortress Steam "
          "install (found via " + info.via + ").";
    return std::nullopt;
  }
  return info;
}

bool verifyInstallBuild(const InstallInfo& info, std::string_view pinnedBuildId,
                        uint32_t pinnedPeTimestamp, std::string& err) {
  if (!info.buildId.empty()) {
    if (info.buildId == pinnedBuildId) return true;
    char ts[32];
    std::snprintf(ts, sizeof ts, "0x%08X", info.peTimestamp);
    err = "Dwarf Fortress build mismatch: the install at " + info.root + " is Steam build " +
          info.buildId + " (PE timestamp " + ts + "), but DF3D is pinned to build " +
          std::string(pinnedBuildId) +
          " (PINS.md).\nDF3D reads art and interface layouts that change between game builds, so "
          "it only works with the build it was made for. Install that Dwarf Fortress build, or "
          "wait for a DF3D release that supports this one.";
    return false;
  }
  if (info.peTimestamp != 0 && info.peTimestamp == pinnedPeTimestamp) return true;
  char ts[32], pin[32];
  std::snprintf(ts, sizeof ts, "0x%08X", info.peTimestamp);
  std::snprintf(pin, sizeof pin, "0x%08X", pinnedPeTimestamp);
  err = "Cannot verify the Dwarf Fortress build at " + info.root +
        ": no Steam manifest was found next to it and 'Dwarf Fortress.exe' has PE timestamp " +
        ts + " (pinned: " + pin + ", Steam build " + std::string(pinnedBuildId) +
        ").\nUse the Steam install (discovered automatically) or a copy of the pinned build.";
  return false;
}

}  // namespace df3d::assets
