# Data Crash

Godot 4.7 (GDScript, Jolt physics) prototype of the game in `PLAN.md` (design), `ENEMIES.md`, `WEAPONS.md`.

## Engine and tests

- Local editor binary (git-ignored, has a `.gdignore`): `Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`. Use the `_console.exe` next to it for CLI runs.
- Tests are scenes extending `TestCase` (`tests/test_case.gd`): exit code 0 = pass. An `ErrorLog` (Godot 4.5+ `Logger`) fails the run on any engine or script error, and a game-time watchdog fails hung runs. `--fixed-fps 60` runs game time faster than real time:
  `./Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/<name>.tscn`
  - `smoke_test`: Phase 2 (fence ram, C4, collapse, district heals)
  - `defense_test`: navmesh, guard fire, treats, placement rules, one full wave
  - `units_test`: police shields/EMP, FROST abduct and rescue, Orange Hat pickets and talk-down, townsperson and player repair
  - `weapons_test`: shotgun, rifle, ammo, molotov fire, rock lure, knockback (uses `Player.aim_at()` + `fire()`)
  - `boss_test`: Felsa ram and EMP hack, Elmo truck, then Elmo on foot, then Phase 3
  - `activism_test`: Phase 1 deeds (water main, scout, strays, supply van), noise-scaled trust, breach into Phase 2, all three bribes
  - `balance_sim` (slow, about 30s real per run; run several times, it's random): scripted builder with no player help plays every wave and prints a table. Tuning target: hands-off loses somewhere in waves 3-5. Tests that skip to Phase 3 set `level.boss_enabled = false` before adding the level.
- Screenshots (opens a window, writes `tests/output/*.png`): `--path . res://tests/capture.tscn` (no `--headless`).
- Run the three fast tests after gameplay changes, and the sim after balance changes. Under `--fixed-fps`, threaded work (navmesh bakes) finishes in real time, so tests await `NavBaker.navmesh_ready` instead of fixed delays. Tests are scenes, not `--script`, because `--script` mode doesn't compile autoload references (`Game`).
- After script edits, run `--headless --path . --import` and check for `SCRIPT ERROR` before running tests.

## Conventions

- **GDScript uses tabs** (overrides the global 2-space rule). Godot's editor and style guide use tabs, and mixing tabs and spaces is a parse error. See `.editorconfig`.
- Static typing everywhere. Call duck-typed methods with `node.call(&"apply_damage", ...)` after `has_method`.
- Input actions are registered in code (`scripts/autoload/game.gd`), not in `project.godot`.
- Anything damageable implements `apply_damage(amount: float, from: Vector3, kind: StringName)`. `from` is the **attacker's position** (riot shields and debris direction depend on it). Kinds: `bullet`, `explosive`, `fire`, `impact`, `bite`, `taser`, `melee`, `shockwave`, `emp`. Riot shields don't block `explosive` or `fire`. Things that can be shoved implement `apply_knockback(impulse)`.
- Physics layers: 1 world, 2 player, 3 vehicles, 4 debris, 5 destructible, 6 enemies (bits 1/2/4/8/16/32, constants in `Game`). `@tool` scripts can't use the `Game` autoload, so they hardcode the numbers with a comment.
- Adding bodies inside physics callbacks is not allowed: defer (see `Destructible.shatter`).
- Parameters that may receive freed nodes (timer/tween callbacks, target checks) are `Variant` and check `is_instance_valid`. A typed `Node3D` parameter errors on a freed object.
- A `const` can't hold class references (`{"guard": SecurityGuard}`): use `static var`.

## Architecture

- `Game` (autoload): cash, objective, current `DistrictState`, input map, `reset()` per level load, `set_info(key, text)` for HUD lines ("deeds", "boss", "wave", "core", "build", "bribe"), `bribes` (pending one-shot favors: `has_bribe` / `consume_bribe`).
- `BribeMenu` ([V], then [1-3]): Municipal delay (no police/FROST next wave), Supply blockade (next wave x0.7, floored), Zoning permit (4 free barricades around the core at Phase 3 start, or immediately if bought during Phase 3). Consumed by `WaveSpawner._apply_bribes` and the level.
- Phase 1 props: `WaterMain` (group `fixables`, hold [F]: `Player._repair` falls back to fixables), `ScoutPoint` (stand in the ring: marks cooling units through walls), `SupplyVan` (FelsaCar on a waypoint loop that hunts nobody), and the `StrayDog1/2` nodes.
- `DistrictState` (Resource): smog/noise/water_table/trust, 0..1. `EnvironmentDriver` eases fog/sky/sun/ground color toward it. `DistrictAudio` is a procedural drone (AudioStreamGenerator) whose volume follows `noise`.
- `Destructible` (@tool StaticBody3D): builds its own box mesh/collider from `size` (origin at bottom center). HP, `damage_threshold`, `repair()` / `needs_repair()`, and shatters into box chunks or a `fractured_scene` (Blender pre-fractured model). Debris is in group `debris`, capped at 400, and shrinks away after `debris_lifetime`.
- `FenceLine`, `Datacenter` (@tool): procedural builders made of Destructibles. Datacenter collapses when all cooling units die, then heals the district and pays cash.
- `Explosive`: C4 (sphere query, falloff, pushes rigid bodies). `Explosive.spawn_flash()` is reusable VFX; `Fx.tracer()` draws shot lines.
- `Player` (CharacterBody3D, third person): E = talk down protester, else enter car; F = repair (costs $1 per 5 hp); T = treat; G = C4; Q or the mouse wheel = switch weapon. `aim_at(point)` and `fire()` are public (tests).
- `Weapon` (RefCounted data, `default_loadout()`): Pistol, Shotgun (8 pellets), Hunting rifle, Molotov, and Rocks; HITSCAN or THROWN. Ammo refills at the defense start and after each wave. `Throwable` (RigidBody3D): a molotov leaves a `FireZone` (burns hostiles, scatters protesters unharmed); a rock deals light damage and calls `Enemy.investigate()` on nearby hostiles. `Car` (VehicleBody3D, +Z forward, ram damage = speed x 9).
- `NavBaker` (NavigationRegion3D): runtime bake from static colliders (layers 1+16) under group `nav_source` (the level root). Debounced rebake via `get_tree().call_group(&"nav_baker", &"request_rebake")`, fired when a Destructible dies or a Structure is placed. Use StaticBody + mesh for level geometry, not CSG (CSG forces slow GPU mesh readback while parsing). Vehicles are invisible to the navmesh; `Enemy._unstick()` sidesteps anything blocking.
- `Enemy` (CharacterBody3D base): builds its own body, NavigationAgent3D, 0.25s think tick. Hooks: `_faction_group()`, `_candidates()`, `_idle()`, `_attack()`, `_modify_damage()`, `_on_death()`, `_decorate()`. Structures are engaged from `structure_engage_range` (9m), so ranged units walk into turret range. `rushing` (set by WaveSpawner after `rush_after`) sends hostiles straight at the core. `defeated` fires once on death, conversion, escape, or going home; waves count that.
  - `FelsaCar` (driverless EV, overrides `_build_body`/`_physics_process` with car steering; rams by speed, reverses when blocked; EMP = battery fire, then it burns out and explodes). `ElmoTruck` (boss A, extends FelsaCar: 1200 hp, a telegraphed "Beta Feature" shockwave, EMP only stalls it, emits `wrecked`). `ElmoOnFoot` (boss B: flamethrower cone; stops to post every 10s and takes 2.5x damage while posting).
  - Groups: `hostiles` (guards, dogs, police, FROST, Felsa cars, bosses), `allies` (befriended dogs), `protesters` (Orange Hats: turrets and dogs ignore them), `townspeople`.
  - `SecurityGuard` (hitscan, distance accuracy). `Dog` (bite and slow, `befriend()`). `Police` (riot shield: 35% frontal leak on non-explosive damage; a stun drops it for 5s; taser slows). `Frost` (bullet armor 50%, abducts townspeople to its spawn for a trust loss; killing it frees the captive). `OrangeHat` (pickets structures, turrets within 6m hold fire, body-blocks bullets; harming one costs trust, talking down earns it, goes home after `patience`). `Townsperson` (repair crew; won't repair within 10m of a hostile).
- `Structure` (extends Destructible, group `structures`): `Barricade`, `Turret` (shoots over barricades, holds fire when picketed), `SolarPanel` (income), `GreenCore` (1500 hp). `EmpTrap` is a non-solid Node3D (group `traps`).
- `BuildController`: B toggles, 1-4 select, R rotate, LMB place, RMB exit. `place(index, point, rotation_steps)` is also the test API.
- `WaveSpawner`: `waves` = Array[Dictionary] of unit key to count (`static var unit_types`), spawning at child Marker3Ds.
- Level phases (`test_block.gd`): ACTIVISM (deeds; trust rewards x (1 - 0.5 x noise); all four deeds pay a bonus; the first fence breach ends it), then ASSAULT, then BOSS (after collapse + `boss_delay`, if `boss_enabled`), then BUILD (townspeople join by trust), then WAVE, then WON or LOST. `start_boss()` and `start_defense()` jump ahead. The boss bar is the "boss" info line. From wave `breach_from_wave` (3), a fence breach is planned during the prior build phase (HUD intel + red flare) and cut when the wave starts.

## Status (2026-09-25)

- Done: Phase 1 activism + bribery; Phase 2 slice; full standard enemy roster incl. Felsa cars; first boss (Elmo Mushbrains, 2 phases); Level 1-2 weapons; navmesh; Phase 3 build mode, 5 waves, win/lose; townspeople repair crew; player repair and talk-down; announced fence breaches; procedural drone audio; balance pass via `balance_sim`.
- Known: Jolt occasionally logs "job system exceeded the maximum number of jobs" when many bodies shatter in one frame (a warning; it waits).
- Next ideas: hand-playtest the balance; remaining bosses (Fark Suckerbush, Harry Perckerson, Sham Crapman, Crapya Butella); Level 3 weapons (grenades, machine gun, rocket launcher, bulldozer); recon/FPV drones; garden and fire hoses.
