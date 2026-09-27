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
	var low := river.water_width()
	Game.district.water_table = 0.9
	await seconds(12.0)
	check(river.water_width() > low + 4.0, "the river rises as the water table recovers (%.1f -> %.1f m)" % [low, river.water_width()])
	var houses := hood.door_positions().size()
	check(houses > 20, "the neighborhood still has its houses (%d doors)" % houses)
