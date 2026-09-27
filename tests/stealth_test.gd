extends TestCase
## Stealth at the quiet ForProfitSI compound, with a guard of our own pinned
## in place: outside the fence you're ignored, crouched behind him you're
## unnoticed, standing in front of him he grows suspicious (the HUD shows a
## meter) and raises the alarm. Then a guard dog sniffs out a crouched
## trespasser up close.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/stealth_test.tscn

const MAIN_SCENE := preload("res://scenes/levels/test_block.tscn")

var level: Node3D
var player: Player


func _run() -> void:
	level = MAIN_SCENE.instantiate()
	add_child(level)
	player = level.get_node("Player") as Player
	await seconds(2.0)
	await _test_guard()
	await _test_dog()


## Keeps `unit` standing still, facing `facing` (world).
func _pin(unit: Enemy, facing: Vector3) -> void:
	unit.set("_wander_timer", 9999.0)
	unit.set("_investigate_left", 0.0)
	unit.velocity = Vector3.ZERO
	(unit.get("_nav") as NavigationAgent3D).target_position = unit.global_position
	(unit.get("_visual") as Node3D).global_rotation.y = atan2(-facing.x, -facing.z)


func _test_guard() -> void:
	var site := level.get_node("ForProfitSite") as DatacenterSite
	check(not Game.is_alarmed(site.site_id), "ForProfitSI is quiet")
	var edge := site.compound.y * 0.5
	var guard := SecurityGuard.new()
	guard.site = site.site_id
	guard.position = site.at(Vector3(-22, 0.1, edge - 3.0))
	level.add_child(guard)
	await seconds(0.3)
	var outward := site.global_basis.z

	# 1. Outside the fence, in plain view: none of their business.
	player.global_position = site.at(Vector3(-22, 0.2, edge + 5.0))
	for i in 12:
		_pin(guard, outward)
		await seconds(0.25)
	check(guard.suspicion == 0.0 and not Game.is_alarmed(site.site_id), "a guard ignores you outside the fence")

	# 2. Inside, crouched behind him.
	player.set_crouching(true)
	player.global_position = site.at(Vector3(-22, 0.2, edge - 9.0))
	for i in 12:
		_pin(guard, outward)
		await seconds(0.25)
	var model := player.get("_rig") as CharacterModel
	check(player.crouching and model.stance_clip() == &"crouch_idle", "the player crouches")
	check(guard.suspicion < 0.05 and not Game.is_alarmed(site.site_id),
		"crouched behind a guard inside the compound, you go unnoticed (%.2f)" % guard.suspicion)

	# 3. Standing in front of him, inside.
	player.set_crouching(false)
	var hud := level.get_node("Hud") as Hud
	var marked := false
	var elapsed := 0.0
	for i in 24:
		_pin(guard, -outward)
		await seconds(0.25)
		elapsed += 0.25
		if guard in hud.overlay().suspicious_units():
			marked = true
		if Game.is_alarmed(site.site_id):
			break
	check(marked, "the HUD shows the guard's suspicion")
	check(Game.is_alarmed(site.site_id), "a guard who sees you inside raises the alarm (%.1f s)" % elapsed)
	check(elapsed >= 1.0, "…but not instantly")
	guard.queue_free()


## Guard dogs smell a trespasser all around, crouched or not, up close.
func _test_dog() -> void:
	var site := level.get_node("ScgrewgleSite") as DatacenterSite
	check(not Game.is_alarmed(site.site_id), "Scgrewgle is quiet")
	var edge := site.compound.y * 0.5
	var dog := Dog.new()
	dog.site = site.site_id
	dog.position = site.at(Vector3(-22, 0.1, edge - 6.0))
	level.add_child(dog)
	await seconds(0.3)
	player.set_crouching(true)
	player.global_position = dog.global_position - site.global_basis.z * 3.0 + Vector3.UP * 0.1
	var noticed := false
	for i in 32:
		_pin(dog, site.global_basis.z)  # facing away
		await seconds(0.25)
		if dog.suspicion > 0.1:
			noticed = true
		if Game.is_alarmed(site.site_id):
			break
	check(noticed, "a guard dog smells you behind it, even crouched")
	check(Game.is_alarmed(site.site_id), "…and gives you away")
	player.set_crouching(false)
	dog.queue_free()
