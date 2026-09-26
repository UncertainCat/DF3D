# DF3D

This is a Godot visualization and input layer for Dwarf Fortress. It requires an existing
Dwarf Fortress installation to operate. It is currently primarily a novel way to visualize
and experience a Dwarf Fortress map live, although some level of gameplay is available.
More work is required on panels, data pipelines, and playtesting to complete the gameplay side.

This project is a fan mod and not associated with Bay 12, Kitfox, or DFHack

## Architecture

During runtime, assets are collected from the installation and rendered. Game data is piped
over a shared memory buffer using a shared serialization format. This is intended to maximize
performance and decouple Godot render times from native DF. Inputs are handled via a shared
buffer read by DFHack as an input queue.

## Methodology

All original source and documentation in this repository outside of this README have been
authored, in part or in whole, through the use of AI agentic workflows. The code has been
extensively reviewed. This includes static analysis, as well as extensive benchmarking and
deep performance visibility to root out hitches and stalls. This catches technical issues
well but can easily miss gameplay problems. There's no substitute for human playtesting here.

## Links

- [Build, run, and test instructions](ENGINEERING.md)
- [Supported versions and dependencies](PINS.md)
- [Architecture and agent contribution rules](AGENT_INSTRUCTIONS.md)
- [Our DFHack fork](https://github.com/UncertainCat/dfhack/tree/df3d/53.16)
- [License](LICENSE)
