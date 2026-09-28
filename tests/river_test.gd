extends TestCase
## The riverside layout: a standalone neighborhood with the river switched
## on. Nothing is built in the river, the main road gets a bridge, and the
## water widens and rises as the water table recovers.
##
##   Godot_console.exe --headless --fixed-fps 60 --path . res://tests/river_test.tscn


func _run() -> void:
	Game.reset()
	var hood := NeighborhoodBuilder.new()
	hood.has_river = true
	hood.river_z = 90.0
	hood.reserved_lots = []
	hood.river_owner = "PUREDRAIN"
	add_child(hood)
	await seconds(0.5)
	var river := hood.river()
	check(river != null and river.is_inside_tree(), "the neighborhood has a river")
	var wet := hood.footprints().filter(func(entry: Array) -> bool:
		var rect := entry[0] as Rect2
		return rect.end.y > hood.river_z - hood.river_width * 0.5 and rect.position.y < hood.river_z + hood.river_width * 0.5)
	check(wet.is_empty(), "nothing is built in the river (%d footprints)" % wet.size())
	check(hood.in_river(Vector3(40, 0, 90)) and not hood.in_river(Vector3(40, 0, 70)), "in_river() knows the banks")
	check(river.get_child_count() >= 2, "the water surface leaves a gap under the main road's bridge (%d segments)" % river.get_child_count())
	check(river.wetness() < 0.1, "at low water the bed is dry cracked clay")
	check(hood.has_node("Boathouse") and hood.has_node("FishingPier"), "a boathouse and a fishing pier on the river")
	var pier_signs := hood.get_node("FishingPier").find_children("*", "Label3D", true, false)
	check(pier_signs.any(func(l: Node) -> bool: return "PUREDRAIN" in (l as Label3D).text), "the pier sign says whose river it is now")
	var bottles := hood.get_node_or_null("RiverBottles") as MultiMeshInstance3D
	check(bottles != null and bottles.multimesh.instance_count >= 100, "plastic bottles litter the banks")
	var yard := 0
	for node in hood.get_children():
		for label in node.find_children("*", "Label3D", false, false):
			if (label as Label3D).text in NeighborhoodBuilder.YARD_SIGNS:
				yard += 1
	check(yard >= 4, "neighbors put protest signs on their lawns (%d)" % yard)
	var low := river.water_width()
	Game.district.water_table = 0.9
	await seconds(12.0)
	check(river.water_width() > low + 4.0, "the river rises as the water table recovers (%.1f -> %.1f m)" % [low, river.water_width()])
	check(river.wetness() > 0.6 and float(river.bed_material.get_shader_parameter(&"wet")) > 0.6, "the riverbed turns to wet mud")
	var houses := hood.door_positions().size()
	check(houses > 20, "the neighborhood still has its houses (%d doors)" % houses)
