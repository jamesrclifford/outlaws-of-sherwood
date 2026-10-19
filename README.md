# Outlaws of Sherwood

A turn-based Robin Hood RPG for Android and iOS, built with Godot 4 and GDScript, in pixel art.

Lead Robin's band across a strategic map of Nottinghamshire, rob tax wagons, rescue captured friends, recruit heroes from the old stories, and outwit the Sheriff of Nottingham and Sir Guy of Gisborne.

The full design and roadmap are in [docs/design-plan.md](docs/design-plan.md).

## Running

1. Install [Godot 4.7](https://godotengine.org/download).
2. Open this folder in Godot and press Play, or run `godot --path .`.

## Layout

| Folder | What lives there |
|---|---|
| `core/` | Game rules with no UI: combat, units, mission generation and mission play, data loading. Deterministic for a given seed. |
| `data/` | Heroes, enemies, abilities, encounters, locations, mission templates and traps as JSON. New content goes here, not in code. |
| `scenes/` | Screens: menu, mission path, battle (later map and camp). |
| `tests/` | Headless tests: `GODOT=/path/to/godot tests/run.sh`. `tests/mission_smoke.gd` clicks through whole missions in the real UI. |
