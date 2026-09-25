# Data Crash

Godot 4.7 (GDScript, Jolt physics) prototype of the game in `PLAN.md` (design), `ENEMIES.md`, `WEAPONS.md`.

## Engine

- Local editor binary (git-ignored, has a `.gdignore`): `Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`. Use the `_console.exe` next to it for CLI runs.
- Smoke test (headless, exit code 0 = pass):
  `./Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/smoke_test.tscn`
- Screenshots (opens a window, writes `tests/output/*.png`): same exe, `--path . res://tests/capture.tscn`
- Run the smoke test after gameplay changes. Tests are scenes, not `--script`, because `--script` mode doesn't compile autoload references (`Game`).

## Conventions

- **GDScript uses tabs** (overrides the global 2-space rule). Godot's editor and style guide use tabs, and mixing tabs and spaces is a parse error. See `.editorconfig`.
- Static typing everywhere. Call duck-typed methods with `node.call(&"apply_damage", ...)` after `has_method`.
- Input actions are registered in code (`scripts/autoload/game.gd`), not in `project.godot`.
- Anything damageable implements `apply_damage(amount: float, from: Vector3, kind: StringName)`.
- Physics layers: 1 world, 2 player, 3 vehicles, 4 debris, 5 destructible (bits 1/2/4/8/16, constants in `Game`). `@tool` scripts can't use the `Game` autoload, so they hardcode the numbers with a comment.
- Adding bodies inside physics callbacks is not allowed: defer (see `Destructible.shatter`).
- Timer/tween callbacks bound to nodes that may be freed take `Variant` parameters and check `is_instance_valid`.

## Architecture

- `Game` (autoload): cash, objective, current `DistrictState`, input map.
- `DistrictState` (Resource): smog/noise/water_table/trust, 0..1. `EnvironmentDriver` eases fog/sky/sun/ground color toward it.
- `Destructible` (@tool StaticBody3D): builds its own box mesh/collider from `size` (origin at bottom center). HP + `damage_threshold`, shatters into box chunks or a `fractured_scene` (Blender pre-fractured model). Debris is in group `debris`, capped at 600, and shrinks away after `debris_lifetime`.
- `FenceLine`, `Datacenter` (@tool): procedural builders made of Destructibles. Datacenter collapses when all cooling units die, then heals the district and pays cash.
- `Explosive`: C4 (sphere query, falloff, pushes rigid bodies). `Explosive.spawn_flash()` is a reusable VFX.
- `Player` (CharacterBody3D, third person), `Car` (VehicleBody3D, +Z forward, ram damage = speed x 9).
- `Hud`: built in code.

## Status (2026-09-25)

Vertical slice step 1 done: ram fence, plant C4 on 3 cooling units, building collapses, sky and ground turn green. Smoke test passes.

Next up: enemies (Private Security, Dogs + treats), Phase 3 build mode (grid placement of solar datacenter and turrets), wave spawner with nav agents, noise-driven audio.
