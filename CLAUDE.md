# Outlaws of Sherwood

Godot 4.7 / GDScript mobile game (portrait 360x640, pixel art). Design: docs/design-plan.md.

- Keep rules in `core/` free of UI so they can be tested headlessly; screens in `scenes/` only call into core.
- Content (heroes, enemies, abilities, encounters, later missions/traps) is data in `data/*.json`.
- All randomness goes through the battle's seeded RandomNumberGenerator so fights replay identically.
- Family tone: enemies are knocked out or flee, never killed; heroes are captured, never die.
- Use `preload` constants rather than `class_name` for cross-script references (headless test runs don't need an editor import).
- Avoid `:=` when the right side is untyped (Variant); GDScript fails to parse it.
- Run tests: `GODOT=/path/to/godot tests/run.sh` (fails on any SCRIPT ERROR).
