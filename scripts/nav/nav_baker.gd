class_name NavBaker
extends NavigationRegion3D
## Bakes the navmesh at runtime from static colliders (world + destructibles)
## under nodes in the "nav_source" group, then rebakes (debounced) whenever
## something is destroyed or built. Call via:
##   get_tree().call_group(&"nav_baker", &"request_rebake")

## Emitted after every finished bake, including the first.
signal navmesh_ready

@export var bake_bounds := AABB(Vector3(-92.0, -2.0, -72.0), Vector3(184.0, 20.0, 236.0))
@export var rebake_delay := 0.4

var bake_count := 0

var _baking := false
var _pending := false
var _delay_left := -1.0


func _ready() -> void:
	add_to_group("nav_baker")
	if navigation_mesh == null:
		navigation_mesh = NavigationMesh.new()
	var mesh := navigation_mesh
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1 | 16  # world + destructibles
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = &"nav_source"
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0  # multiples of cell_height (0.25)
	mesh.agent_max_climb = 0.25
	mesh.filter_baking_aabb = bake_bounds
	bake_finished.connect(_on_bake_finished)
	# Deferred: procedural builders (fences, datacenter) create colliders in their own _ready.
	_start_bake.call_deferred()


func request_rebake() -> void:
	_delay_left = rebake_delay


func _process(delta: float) -> void:
	if _delay_left < 0.0:
		return
	_delay_left -= delta
	if _delay_left < 0.0:
		_start_bake()


func _start_bake() -> void:
	if _baking:
		_pending = true
		return
	_baking = true
	bake_navigation_mesh(true)


func _on_bake_finished() -> void:
	_baking = false
	bake_count += 1
	navmesh_ready.emit()
	if _pending:
		_pending = false
		_start_bake()
