class_name SnowSurfaceGrid
extends Node

signal surface_changed(cell: Vector2i, old_surface: int, new_surface: int)

enum SurfaceType {
	FRESH_POWDER,
	PACKED_SNOW,
	EXISTING_TRACKS,
	ICE,
}

const PROFILE_PATHS: Dictionary = {
	SurfaceType.FRESH_POWDER: "res://resources/surfaces/fresh_powder.tres",
	SurfaceType.PACKED_SNOW: "res://resources/surfaces/packed_snow.tres",
	SurfaceType.EXISTING_TRACKS: "res://resources/surfaces/existing_tracks.tres",
	SurfaceType.ICE: "res://resources/surfaces/ice.tres",
}

@export var grid_dimensions: Vector2i = Vector2i(48, 224)
@export var world_size: Vector2 = Vector2(240.0, 1120.0)
@export var world_origin: Vector3 = Vector3(-120.0, 0.0, 0.0)
@export_range(0.5, 10.0, 0.1) var tracking_radius: float = 2.2

var _states: PackedByteArray = PackedByteArray()
var _base_states: PackedByteArray = PackedByteArray()
var _freshness: PackedFloat32Array = PackedFloat32Array()
var _profiles: Dictionary = {}
var _initialized: bool = false


func _ready() -> void:
	_load_profiles()
	if not _initialized:
		configure(world_origin, world_size, grid_dimensions)


func configure(origin: Vector3, size: Vector2, dimensions: Vector2i) -> void:
	world_origin = origin
	world_size = Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	grid_dimensions = Vector2i(maxi(dimensions.x, 2), maxi(dimensions.y, 2))
	var cell_count: int = grid_dimensions.x * grid_dimensions.y
	_states.resize(cell_count)
	_base_states.resize(cell_count)
	_freshness.resize(cell_count)
	for z_index: int in range(grid_dimensions.y):
		for x_index: int in range(grid_dimensions.x):
			var cell: Vector2i = Vector2i(x_index, z_index)
			var state: int = _initial_state_for_cell(cell)
			var index: int = _index(cell)
			_states[index] = state
			_base_states[index] = state
			_freshness[index] = 1.0 if state == SurfaceType.FRESH_POWDER else 0.65
	_initialized = true


func sample(global_position: Vector3) -> Dictionary:
	if not _initialized:
		configure(world_origin, world_size, grid_dimensions)
	var cell: Vector2i = world_to_cell(global_position)
	var is_inside: bool = _is_cell_valid(cell)
	if not is_inside:
		return _profile_data(SurfaceType.PACKED_SNOW, 0.45, cell, false)
	var index: int = _index(cell)
	return _profile_data(int(_states[index]), _freshness[index], cell, true)


func mark_tracked(global_position: Vector3, strength: float = 1.0, radius: float = -1.0) -> void:
	if not _initialized:
		return
	var use_radius: float = tracking_radius if radius <= 0.0 else radius
	var center: Vector2i = world_to_cell(global_position)
	var cell_world_size: Vector2 = Vector2(
		world_size.x / float(grid_dimensions.x),
		world_size.y / float(grid_dimensions.y)
	)
	var extent_x: int = maxi(1, ceili(use_radius / cell_world_size.x))
	var extent_z: int = maxi(1, ceili(use_radius / cell_world_size.y))
	for z_offset: int in range(-extent_z, extent_z + 1):
		for x_offset: int in range(-extent_x, extent_x + 1):
			var cell: Vector2i = center + Vector2i(x_offset, z_offset)
			if not _is_cell_valid(cell):
				continue
			var cell_position: Vector3 = cell_to_world(cell)
			var planar_distance: float = Vector2(
				cell_position.x - global_position.x,
				cell_position.z - global_position.z
			).length()
			if planar_distance > use_radius:
				continue
			var index: int = _index(cell)
			var old_state: int = int(_states[index])
			if old_state == SurfaceType.ICE:
				continue
			_states[index] = SurfaceType.EXISTING_TRACKS
			_freshness[index] = maxf(0.0, _freshness[index] - strength * 0.32)
			if old_state != SurfaceType.EXISTING_TRACKS:
				surface_changed.emit(cell, old_state, SurfaceType.EXISTING_TRACKS)


func apply_snowfall(accumulation_rate: float, delta: float) -> void:
	if not _initialized or accumulation_rate <= 0.0:
		return
	var restore_amount: float = accumulation_rate * delta
	for index: int in range(_states.size()):
		var state: int = int(_states[index])
		if state == SurfaceType.ICE:
			continue
		_freshness[index] = minf(1.0, _freshness[index] + restore_amount)
		if state == SurfaceType.EXISTING_TRACKS and _freshness[index] >= 0.88:
			var cell: Vector2i = Vector2i(index % grid_dimensions.x, floori(float(index) / float(grid_dimensions.x)))
			_states[index] = SurfaceType.FRESH_POWDER
			surface_changed.emit(cell, SurfaceType.EXISTING_TRACKS, SurfaceType.FRESH_POWDER)


func reset_to_fresh() -> void:
	if not _initialized:
		return
	for index: int in range(_states.size()):
		_states[index] = _base_states[index]
		_freshness[index] = 1.0 if int(_states[index]) == SurfaceType.FRESH_POWDER else 0.65


func world_to_cell(global_position: Vector3) -> Vector2i:
	var normalized_x: float = (global_position.x - world_origin.x) / world_size.x
	var normalized_z: float = (world_origin.z - global_position.z) / world_size.y
	return Vector2i(
		floori(normalized_x * float(grid_dimensions.x)),
		floori(normalized_z * float(grid_dimensions.y))
	)


func cell_to_world(cell: Vector2i) -> Vector3:
	var x_fraction: float = (float(cell.x) + 0.5) / float(grid_dimensions.x)
	var z_fraction: float = (float(cell.y) + 0.5) / float(grid_dimensions.y)
	return Vector3(
		world_origin.x + x_fraction * world_size.x,
		world_origin.y,
		world_origin.z - z_fraction * world_size.y
	)


func get_surface_name(surface_type: int) -> StringName:
	var profile: SnowSurfaceProfile = _profiles.get(surface_type) as SnowSurfaceProfile
	return profile.display_name if profile != null else &"Packed Snow"


func _load_profiles() -> void:
	_profiles.clear()
	for surface_type: int in PROFILE_PATHS:
		var path: String = PROFILE_PATHS[surface_type]
		if ResourceLoader.exists(path):
			_profiles[surface_type] = load(path)


func _profile_data(
	surface_type: int,
	freshness: float,
	cell: Vector2i,
	is_inside: bool
) -> Dictionary:
	var profile: SnowSurfaceProfile = _profiles.get(surface_type) as SnowSurfaceProfile
	var data: Dictionary
	if profile != null:
		data = profile.as_gameplay_data(freshness)
	else:
		data = {
			"id": SurfaceType.PACKED_SNOW,
			"name": &"Packed Snow",
			"friction_multiplier": 1.0,
			"edge_grip_multiplier": 1.0,
			"spray_multiplier": 1.0,
			"speed_multiplier": 1.0,
			"powder_amount": 0.25,
			"freshness": freshness,
			"untouched_powder": false,
		}
	data["cell"] = cell
	data["inside_course"] = is_inside
	return data


func _initial_state_for_cell(cell: Vector2i) -> int:
	var course_progress: float = (float(cell.y) + 0.5) / float(grid_dimensions.y)
	var x_position: float = world_origin.x + (
		(float(cell.x) + 0.5) / float(grid_dimensions.x)
	) * world_size.x

	# The blue-ice chute is a narrow, fast shortcut on skier's left.
	if course_progress >= 0.30 and course_progress <= 0.47:
		var ice_t: float = inverse_lerp(0.30, 0.47, course_progress)
		var ice_center: float = lerpf(-38.0, -18.0, ice_t)
		if absf(x_position - ice_center) < 8.5:
			return SurfaceType.ICE

	# An exposed second shortcut crosses the late ridge.
	if course_progress >= 0.70 and course_progress <= 0.82:
		var ridge_center: float = -42.0 + sin(course_progress * 35.0) * 3.0
		if absf(x_position - ridge_center) < 6.0:
			return SurfaceType.ICE

	# Wide off-line sections retain untouched powder; the central line is packed.
	if course_progress >= 0.47 and course_progress <= 0.70:
		var packed_center: float = sin(course_progress * 24.0) * 15.0
		if absf(x_position - packed_center) > 13.0:
			return SurfaceType.FRESH_POWDER

	if absf(x_position) > 62.0:
		return SurfaceType.FRESH_POWDER
	return SurfaceType.PACKED_SNOW


func _index(cell: Vector2i) -> int:
	return cell.y * grid_dimensions.x + cell.x


func _is_cell_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 \
		and cell.x < grid_dimensions.x and cell.y < grid_dimensions.y
