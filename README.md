# DF3D

DF3D is an experimental 3D frontend for Dwarf Fortress. Explore your fortress in Godot while
Dwarf Fortress runs the simulation, with DFHack connecting the two.

It has three pieces: the **bridge** (a DFHack plugin running inside Dwarf Fortress that publishes
game state), the **core** (`schema/` and `worldmodel/`, engine-independent C++), and the
**viewer** (a Godot project plus a native extension).

**Status.** The viewer loads a fortress from a running game and renders its terrain, creatures,
items and animations; you can pause, unpause and save. The toolbar exposes Dig, Chop trees, Gather
plants, Smooth, Remove, Inspect and Inspect buildings, plus read-only Residents, Work Details and
Work orders panels; build, stockpile and zone editors exist but are hidden, and other management
screens are not implemented. There is no installer: you build from source, for Windows x64 with the
Steam release of Dwarf Fortress only.

## Build from source

### What you need

- Git, and CMake 3.20 or later.
- MSYS2 with `mingw-w64-x86_64-gcc` and `mingw-w64-x86_64-make`: builds the core and the Godot extension.
- Visual Studio 2022 C++ build tools with the Windows SDK: builds the DFHack fork (MSVC is
  required for ABI compatibility with the game).
- Strawberry Perl with `XML::LibXML`: DFHack's df-structures code generation.
- Python 3.12: the test suite.
- Dwarf Fortress 53.16 and Godot 4.7.2 (editor build), both from Steam.
- PowerShell 7 (`pwsh`) or Windows PowerShell 5.1.

The exact supported builds are listed in [PINS.md](PINS.md). DFHack and godot-cpp are pinned Git
submodules; a source ZIP does not include them.

### Get the source

Run everything below in one PowerShell session from the repository directory. The path assignments are
the standard install locations; edit them if yours differ:

```powershell
git clone --recurse-submodules https://github.com/UncertainCat/DF3D.git
cd DF3D
$mingwBin = 'C:\msys64\mingw64\bin'
$godotExe = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$dfPath = 'C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress'
$env:Path = "$mingwBin;$env:Path"
```

The same paths can be set once as environment variables instead: `DF3D_DF_PATH`, `DF3D_GODOT` and
`DF3D_MINGW_BIN` are read by the viewer, the QA gate and the smoke scripts.

### Build the core and viewer

The core and its tests need only Git, CMake, MSYS2 and the submodules.

```powershell
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build -j
ctest --test-dir build --output-on-failure

cmake -S presentations/godot/extension -B build/godot-ext -G "MinGW Makefiles" `
    -DCMAKE_BUILD_TYPE=RelWithDebInfo `
    "-DCMAKE_CXX_COMPILER=$mingwBin/g++.exe" `
    "-DCMAKE_MAKE_PROGRAM=$mingwBin/mingw32-make.exe"
cmake --build build/godot-ext -j
& $godotExe --headless --editor --path presentations/godot/project --import --quit
```

The import step registers the extension's native classes; run it after every extension build,
with Godot closed.

### Build and install the bridge

Register DF3D as a DFHack plugin (once), then with Dwarf Fortress closed build and install the
DFHack fork and DF3D plugin into your game installation (`-SkipInstall` builds only):

```powershell
New-Item -ItemType Directory -Force external/dfhack/plugins/external | Out-Null
'add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../../../bridge/plugin" df3d-plugin)' |
    Set-Content -Encoding ascii external/dfhack/plugins/external/CMakeLists.txt
./tools/build_bridge.ps1 -DfPath $dfPath
```

## Play

With Dwarf Fortress closed, start the viewer and choose a fortress in the selector; it opens paused:

```powershell
./Play.cmd -DfPath $dfPath -GodotExe $godotExe
```

This launcher starts a temporary game session on a hidden desktop. **Closing the viewer or
launcher ends that session without saving**, so save through Settings first. Sessions also end
after 120 minutes by default; pass `-MaxMinutes` to change that.

### Recovering by hand

A session rewrites `prefs/init.txt` in the Dwarf Fortress folder (backup: `prefs/init.txt.df3d-backup`)
and adds `dfhack-config/init/dfhackzzz_df3d_menu.init` (`enable df3d`), reverting both on exit.
If a session is interrupted, the next launch restores the backup unless you changed settings since.
To recover by hand, copy the backup over `prefs/init.txt` and delete the menu init file while the
game is closed.

### Attach to a running game

To use a game you have already started, run `enable df3d` in its DFHack console, then attach:

```powershell
./Play.cmd -Attach -DfPath $dfPath -GodotExe $godotExe
```

Attach mode requires exactly one running Dwarf Fortress process. It preserves the game's pause
state and leaves the game running when you close the viewer.

## Tests and known problems

There is no CI; all checks run locally and most need the game installed. The core C++ tests run
with the `ctest` command above. For the broader suite:

```powershell
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tools/qa -p "test_*.py"
python tools/qa/verify.py
```

Results and logs go in `build/qa/`; missing prerequisites are reported as incomplete.
`python tools/qa/verify.py --help` covers GPU and live-game checks; the
[test manifest](tools/qa/checks.json) lists what each group covers. Known Godot engine warnings
are reported as `passed_with_known_issues` (rules in [tools/qa/diagnostics.py](tools/qa/diagnostics.py));
they are recognized only by the Steam build's version string, so the official Godot download
runs the viewer but fails those checks. One known failure: the GPU combat test reports a
misaligned billboard hit effect.

## Development

Game state flows one way through the repository:

```
DF  ->  bridge (bridge/)  ->  mirror (schema/)  ->  world model (worldmodel/)  ->  viewer (presentations/godot/)
                                   \-> debug consumer (consumers/)
```

- `bridge/`: the DFHack plugin (bridge) and its build glue.
- `schema/`: the FlatBuffers mirror format shared between processes (core).
- `worldmodel/`: the engine-independent game state model (core).
- `presentations/godot/`: the Godot project and native extension (viewer);
  `project/scripts/ui_availability.gd` is the registry of exposed UI surfaces.
- `consumers/`: the inspector, a debug consumer of the mirror kept working as a check.
- `fixtures/`: recorded and synthetic mirror captures used by tests.
- `third_party/`: vendored FlatBuffers and doctest.
- `external/`: the DFHack fork and godot-cpp submodules.
- `tools/`: QA gate, launch scripts and smoke lanes.

Engineering rules, also read by AI coding agents through `CLAUDE.md`:
[AGENT_INSTRUCTIONS.md](AGENT_INSTRUCTIONS.md) (section 2 is the architecture contract, section 6
covers submodules). The bridge builds against a DFHack fork (github.com/UncertainCat/dfhack, branch
`df3d/53.16`) plus the df-structures and dfhooks forks listed in [PINS.md](PINS.md). `tools/smoke`
holds profiling and debugging lanes; see each script's header.

## Reporting bugs and contributing

Open a GitHub issue using the bug report template; do not upload game assets or saves.
Pull requests describe the problem, the change and the local checks run.

## License

Original DF3D code is [MIT licensed](LICENSE); FlatBuffers is Apache-2.0, doctest and godot-cpp are
MIT, and DFHack is primarily Zlib with component notices. DF3D contains no Dwarf Fortress code, text
or art, only numeric offsets into the supported executable; Dwarf Fortress is a trademark of Bay 12
Games, and DF3D and its DFHack forks are independent projects endorsed by neither Bay 12 nor DFHack.
