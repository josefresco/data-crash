class_name WeaponModels
extends RefCounted
## Low-poly held weapons, built from primitives. Each faces -Z (barrel
## forward) with the grip at the origin, and has a "Muzzle" Marker3D where
## shots and flashes come from and, for two-handed guns, a "Grip" marker for
## the off hand. Static only.


## `model` is Weapon.model; returns null for bare hands.
static func build(model: StringName) -> Node3D:
	var root := Node3D.new()
	var black := Models.mat(Color(0.08, 0.08, 0.09), &"metal")
	var steel := Models.mat(Color(0.35, 0.36, 0.38), &"metal")
	var wood := Models.mat(Color(0.45, 0.28, 0.15), &"rough")
	var muzzle := 0.0
	var grip := Vector3.ZERO
	match model:
		&"pistol":
			Models.box(root, Vector3(0.05, 0.07, 0.24), Vector3(0.0, 0.07, -0.08), black)  # slide
			Models.box(root, Vector3(0.045, 0.13, 0.06), Vector3(0.0, -0.01, 0.0), black).rotation.x = 0.25  # grip
			muzzle = -0.21
			root.scale = Vector3.ONE * 1.4  # chunky hands need a chunkier pistol
		&"shotgun":
			Models.cylinder(root, 0.028, 0.78, Vector3(0.0, 0.07, -0.42), steel, 8).rotation.x = PI * 0.5
			Models.box(root, Vector3(0.07, 0.08, 0.26), Vector3(0.0, 0.04, -0.02), black)  # receiver
			Models.box(root, Vector3(0.07, 0.07, 0.2), Vector3(0.0, 0.02, -0.46), wood)  # pump
			Models.box(root, Vector3(0.06, 0.12, 0.34), Vector3(0.0, -0.02, 0.26), wood).rotation.x = -0.15  # stock
			muzzle = -0.82
			grip = Vector3(0.0, 0.02, -0.46)
		&"rifle":
			Models.box(root, Vector3(0.06, 0.08, 0.7), Vector3(0.0, 0.03, -0.1), wood)  # stock and body
			Models.cylinder(root, 0.018, 0.55, Vector3(0.0, 0.07, -0.66), steel, 8).rotation.x = PI * 0.5
			Models.cylinder(root, 0.03, 0.3, Vector3(0.0, 0.14, -0.12), black, 10).rotation.x = PI * 0.5  # scope
			muzzle = -0.94
			grip = Vector3(0.0, 0.0, -0.36)
		&"mg":
			Models.box(root, Vector3(0.1, 0.14, 0.46), Vector3(0.0, 0.05, -0.08), black)  # receiver
			Models.cylinder(root, 0.045, 0.5, Vector3(0.0, 0.07, -0.55), steel, 10).rotation.x = PI * 0.5  # shroud
			Models.cylinder(root, 0.02, 0.2, Vector3(0.0, 0.07, -0.88), black, 8).rotation.x = PI * 0.5
			Models.cylinder(root, 0.1, 0.08, Vector3(0.0, -0.08, -0.1), black, 12)  # drum
			Models.box(root, Vector3(0.07, 0.12, 0.25), Vector3(0.0, 0.0, 0.26), black)  # stock
			muzzle = -0.98
			grip = Vector3(0.0, 0.0, -0.45)
		&"rocket":
			Models.cylinder(root, 0.08, 1.1, Vector3(0.0, 0.12, -0.2), Models.mat(Color(0.3, 0.36, 0.22), &"paint"), 12).rotation.x = PI * 0.5
			Models.box(root, Vector3(0.05, 0.14, 0.06), Vector3(0.0, 0.0, 0.0), black)
			Models.box(root, Vector3(0.08, 0.1, 0.12), Vector3(0.06, 0.2, -0.1), black)  # sight
			muzzle = -0.76
			grip = Vector3(0.0, 0.04, -0.4)
		&"shovel":
			Models.cylinder(root, 0.025, 1.1, Vector3(0.0, 0.0, -0.35), wood, 8).rotation.x = PI * 0.5
			var blade := Models.box(root, Vector3(0.24, 0.03, 0.3), Vector3(0.0, 0.0, -1.02), steel)
			blade.rotation.x = 0.15
			Models.box(root, Vector3(0.14, 0.03, 0.03), Vector3(0.0, 0.0, 0.22), black)  # D-handle
			muzzle = -1.1
			grip = Vector3(0.0, 0.0, -0.45)
		&"rock":
			Models.ball(root, 0.09, Vector3(0.0, 0.03, -0.05), Models.mat(Color(0.5, 0.48, 0.45), &"rough"))
		&"molotov":
			Models.cylinder(root, 0.045, 0.22, Vector3(0.0, 0.08, -0.03), Models.glass(Color(0.3, 0.55, 0.25, 0.8)), 8)
			Models.cylinder(root, 0.018, 0.08, Vector3(0.0, 0.22, -0.03), Models.glass(Color(0.3, 0.55, 0.25, 0.8)), 6)
			Models.box(root, Vector3(0.05, 0.1, 0.03), Vector3(0.0, 0.3, -0.03), Models.mat(Color(0.9, 0.85, 0.7), &"cloth"))  # rag
		&"grenade":
			Models.ball(root, 0.06, Vector3(0.0, 0.03, -0.04), Models.mat(Color(0.25, 0.3, 0.18), &"metal"))
			Models.box(root, Vector3(0.02, 0.05, 0.06), Vector3(0.0, 0.1, -0.04), steel)
		_:
			return null
	var marker := Marker3D.new()
	marker.name = "Muzzle"
	marker.position = Vector3(0.0, 0.07, muzzle)
	root.add_child(marker)
	if grip != Vector3.ZERO:
		var hold := Marker3D.new()
		hold.name = "Grip"
		hold.position = grip
		root.add_child(hold)
	Models.set_gi_mode(root, GeometryInstance3D.GI_MODE_DYNAMIC)
	return root
