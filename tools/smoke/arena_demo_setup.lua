-- Development-only owned no-save capture entry point.
local output,scenario,diagnostics_path,population_scale=...
local directory=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
assert(loadfile(directory..'arena_setup.lua'))()(output,scenario,diagnostics_path,population_scale)
