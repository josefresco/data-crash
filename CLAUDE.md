# Data Crash

Godot 4.7 (GDScript, Jolt physics) prototype of the game in `PLAN.md` (design), `ENEMIES.md`, `WEAPONS.md`.

## Engine

- Local editor binary (git-ignored, has a `.gdignore`): `Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`. Use the `_console.exe` next to it for CLI runs.
- Tests (headless, exit code 0 = pass). `--fixed-fps 60` runs game time faster than real time:
  `./Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/smoke_test.tscn`
  `... res://tests/defense_test.tscn` (enemies, treats, build mode, one full wave)
- Screenshots (opens a window, writes `tests/output/*.png`): same exe, `--path . res://tests/capture.tscn`
- Run both tests after gameplay changes. Under `--fixed-fps`, threaded work (navmesh bakes) finishes in real time, so tests await `NavBaker.navmesh_ready` instead of fixed delays. Tests are scenes, not `--script`, because `--script` mode doesn't compile autoload references (`Game`).

## Conventions

- **GDScript uses tabs** (overrides the global 2-space rule). Godot's editor and style guide use tabs, and mixing tabs and spaces is a parse error. See `.editorconfig`.
- Static typing everywhere. Call duck-typed methods with `node.call(&"apply_damage", ...)` after `has_method`.
- Input actions are registered in code (`scripts/autoload/game.gd`), not in `project.godot`.
- Anything damageable implements `apply_damage(amount: float, from: Vector3, kind: StringName)`.
- Physics layers: 1 world, 2 player, 3 vehicles, 4 debris, 5 destructible, 6 enemies (bits 1/2/4/8/16/32, constants in `Game`). `@tool` scripts can't use the `Game` autoload, so they hardcode the numbers with a comment.
- Adding bodies inside physics callbacks is not allowed: defer (see `Destructible.shatter`).
- Timer/tween callbacks bound to nodes that may be freed take `Variant` parameters and check `is_instance_valid`.

## Architecture

- `Game` (autoload): cash, objective, current `DistrictState`, input map.
- `DistrictState` (Resource): smog/noise/water_table/trust, 0..1. `EnvironmentDriver` eases fog/sky/sun/ground color toward it.
- `Destructible` (@tool StaticBody3D): builds its own box mesh/collider from `size` (origin at bottom center). HP + `damage_threshold`, shatters into box chunks or a `fractured_scene` (Blender pre-fractured model). Debris is in group `debris`, capped at 400, and shrinks away after `debris_lifetime`.
- `FenceLine`, `Datacenter` (@tool): procedural builders made of Destructibles. Datacenter collapses when all cooling units die, then heals the district and pays cash.
- `Explosive`: C4 (sphere query, falloff, pushes rigid bodies). `Explosive.spawn_flash()` is a reusable VFX.
- `Player` (CharacterBody3D, third person), `Car` (VehicleBody3D, +Z forward, ram damage = speed x 9).
- `Hud`: built in code. `Game.set_info(key, text)` drives the "wave", "core", and "build" lines.
- `NavBaker` (NavigationRegion3D): runtime bake from static colliders (layers 1+16) under group `nav_source` (the level root). Debounced rebake via `get_tree().call_group(&"nav_baker", &"request_rebake")`, fired when a Destructible dies or a Structure is placed. Use StaticBody + mesh for level geometry, not CSG (CSG forces slow GPU mesh readback while parsing).
- `Enemy` (CharacterBody3D base): builds its own body, NavigationAgent3D, faction (HOSTILE/ALLY via groups `hostiles`/`allies`), 0.25s think tick, `_attack()` override. `SecurityGuard` (hitscan, distance-based accuracy), `Dog` (fast bite and slow; `befriend()` converts it to an ally that follows the player). Hostile targets: player (or their car), allies, `structures`. `defeated` fires on death or conversion; waves count that.
- `Structure` (extends Destructible, group `structures`): `Barricade`, `Turret` (shoots over barricades), `SolarPanel` (income), `GreenCore`. `EmpTrap` is a non-solid Node3D (group `traps`).
- `BuildController`: B toggles, 1-4 select, R rotate, LMB place, RMB exit. `place(index, point, rotation_steps)` is also the test API.
- `WaveSpawner`: `waves` = Array[Vector2i(guards, dogs)], spawns at child Marker3Ds.
- Level phases (`test_block.gd`): ASSAULT, then BUILD (after collapse + `core_delay`), then WAVE, then WON or LOST. `start_defense()` skips to Phase 3.

## Status (2026-09-25)

- Done: Phase 2 slice (fence ram, C4, collapse, district heals), enemies (guards, dogs, treats), navmesh, Phase 3 build mode + 5 waves with win/lose. Both tests pass.
- Known: Jolt occasionally logs "job system exceeded the maximum number of jobs" when many bodies shatter in one frame (a warning; it waits). Debris cap is 400.
- Next ideas: balance pass (wave sizes, costs, turret DPS), police/FROST/Orange Hat enemies, repair action, audio driven by `noise`, bosses.
