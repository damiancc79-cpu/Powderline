class_name ProceduralSkiTerrain
extends StaticBody3D

signal terrain_rebuilt(vertex_count: int)

@export_range(100.0, 500.0, 1.0) var course_width: float = 240.0
@export_range(500.0, 2000.0, 1.0) var course_length: float = 1120.0
@export_range(16, 128, 1) var width_segments: int = 48
@export_range(64, 400, 1) var length_segments: int = 224
@export var terrain_shader: Shader = preload("res://shaders/snow_terrain.gdshader")
@export_node_path("SnowSurfaceGrid") var surface_grid_path: NodePath = ^"SnowSurfaceGrid"

var _mesh_instance: MeshInstance3D
var _collision_shape: CollisionShape3D
var _surface_grid: SnowSurfaceGrid
var _terrain_mesh: ArrayMesh


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_surface_grid = get_node_or_null(surface_grid_path) as SnowSurfaceGrid
	_build_terrain()
	if _surface_grid != null:
		_surface_grid.configure(
			to_global(Vector3(-course_width * 0.5, 0.0, 0.0)),
			Vector2(course_width, course_length),
			Vector2i(width_segments, length_segments)
		)


func rebuild() -> void:
	_build_terrain()


func height_at_world(global_position: Vector3) -> float:
	var local_position: Vector3 = to_local(global_position)
	var local_height: float = height_at_local(local_position.x, local_position.z)
	return to_global(Vector3(local_position.x, local_height, local_position.z)).y


func normal_at_world(global_position: Vector3) -> Vector3:
	var local_position: Vector3 = to_local(global_position)
	return (global_basis * normal_at_local(local_position.x, local_position.z)).normalized()


func height_at_local(x_position: float, z_position: float) -> float:
	var progress: float = clampf(-z_position / course_length, 0.0, 1.0)
	var height: float = _profile_height(progress)
	var normalized_x: float = x_position / (course_width * 0.5)

	# Raised shoulders frame the playable valley without invisible walls.
	height += normalized_x * normalized_x * 11.0
	height += sin(x_position * 0.052 + progress * 18.0) * 0.38
	height += sin(x_position * 0.115 - progress * 31.0) * 0.18

	# Rock chute: a readable central trough with a smoother ice ribbon on the left.
	var chute_weight: float = _band(progress, 0.27, 0.48, 0.035)
	height -= exp(-x_position * x_position / 700.0) * 2.1 * chute_weight
	var ice_t: float = clampf(inverse_lerp(0.30, 0.47, progress), 0.0, 1.0)
	var ice_center: float = lerpf(-38.0, -18.0, ice_t)
	var ice_weight: float = exp(-pow(x_position - ice_center, 2.0) / 120.0) * chute_weight
	height -= ice_weight * 0.7

	# Powder field is softly rolling so suspension reads without random launches.
	var powder_weight: float = _band(progress, 0.47, 0.70, 0.04)
	height += (
		sin(x_position * 0.16 + progress * 49.0) * 0.34
		+ sin(x_position * 0.07 - progress * 71.0) * 0.23
	) * powder_weight

	# The exposed late shortcut sits on a narrow shoulder.
	var ridge_weight: float = _band(progress, 0.69, 0.83, 0.025)
	height += exp(-pow(x_position + 42.0, 2.0) / 160.0) * 2.4 * ridge_weight
	return height


func normal_at_local(x_position: float, z_position: float) -> Vector3:
	const SAMPLE_DISTANCE: float = 0.65
	var tangent_x: Vector3 = Vector3(
		SAMPLE_DISTANCE * 2.0,
		height_at_local(x_position + SAMPLE_DISTANCE, z_position)
			- height_at_local(x_position - SAMPLE_DISTANCE, z_position),
		0.0
	)
	var tangent_z: Vector3 = Vector3(
		0.0,
		height_at_local(x_position, z_position + SAMPLE_DISTANCE)
			- height_at_local(x_position, z_position - SAMPLE_DISTANCE),
		SAMPLE_DISTANCE * 2.0
	)
	return tangent_z.cross(tangent_x).normalized()


func sample_surface(global_position: Vector3) -> Dictionary:
	var data: Dictionary = (
		_surface_grid.sample(global_position)
		if _surface_grid != null
		else {
			"id": SnowSurfaceGrid.SurfaceType.PACKED_SNOW,
			"name": &"Packed Snow",
			"friction_multiplier": 1.0,
			"edge_grip_multiplier": 1.0,
			"spray_multiplier": 1.0,
			"speed_multiplier": 1.0,
			"powder_amount": 0.25,
		}
	)
	data["height"] = height_at_world(global_position)
	data["normal"] = normal_at_world(global_position)
	return data


func get_snow_surface_sample(global_position: Vector3) -> Dictionary:
	var data: Dictionary = sample_surface(global_position)
	data["surface_key"] = data.get("name", &"Packed Snow")
	data["type"] = data.get("id", SnowSurfaceGrid.SurfaceType.PACKED_SNOW)
	data["powder_factor"] = data.get("powder_amount", 0.25)
	return data


func mark_surface_tracked(global_position: Vector3, strength: float = 1.0) -> void:
	if _surface_grid != null:
		_surface_grid.mark_tracked(global_position, strength)


func apply_snowfall(accumulation_rate: float, delta: float) -> void:
	if _surface_grid != null:
		_surface_grid.apply_snowfall(accumulation_rate, delta)


func _build_terrain() -> void:
	_ensure_runtime_nodes()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var row_width: int = width_segments + 1

	for z_index: int in range(length_segments + 1):
		var progress: float = float(z_index) / float(length_segments)
		var z_position: float = -progress * course_length
		for x_index: int in range(width_segments + 1):
			var x_fraction: float = float(x_index) / float(width_segments)
			var x_position: float = lerpf(-course_width * 0.5, course_width * 0.5, x_fraction)
			vertices.append(Vector3(x_position, height_at_local(x_position, z_position), z_position))
			normals.append(normal_at_local(x_position, z_position))
			uvs.append(Vector2(x_fraction * 8.0, progress * 32.0))
			colors.append(_surface_weights(x_position, progress))

	for z_index: int in range(length_segments):
		for x_index: int in range(width_segments):
			var top_left: int = z_index * row_width + x_index
			var top_right: int = top_left + 1
			var bottom_left: int = top_left + row_width
			var bottom_right: int = bottom_left + 1
			indices.append_array(PackedInt32Array([
				top_left, top_right, bottom_left,
				top_right, bottom_right, bottom_left,
			]))

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	_terrain_mesh = ArrayMesh.new()
	_terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = terrain_shader
	_terrain_mesh.surface_set_material(0, material)
	_mesh_instance.mesh = _terrain_mesh
	_collision_shape.shape = _terrain_mesh.create_trimesh_shape()
	terrain_rebuilt.emit(vertices.size())


func _ensure_runtime_nodes() -> void:
	_mesh_instance = get_node_or_null("TerrainMesh") as MeshInstance3D
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "TerrainMesh"
		add_child(_mesh_instance)
		_mesh_instance.owner = owner
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_collision_shape = get_node_or_null("TerrainCollision") as CollisionShape3D
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "TerrainCollision"
		add_child(_collision_shape)
		_collision_shape.owner = owner


func _profile_height(progress: float) -> float:
	const POINTS: PackedVector2Array = PackedVector2Array([
		Vector2(0.00, 178.0),
		Vector2(0.12, 165.0),
		Vector2(0.30, 116.0),
		Vector2(0.46, 89.0),
		Vector2(0.63, 58.0),
		Vector2(0.82, 2.0),
		Vector2(1.00, -35.0),
	])
	for index: int in range(POINTS.size() - 1):
		if progress <= POINTS[index + 1].x:
			var section_t: float = inverse_lerp(POINTS[index].x, POINTS[index + 1].x, progress)
			return lerpf(POINTS[index].y, POINTS[index + 1].y, section_t)
	return POINTS[POINTS.size() - 1].y


func _surface_weights(x_position: float, progress: float) -> Color:
	var powder: float = 0.0
	var packed: float = 1.0
	var ice: float = 0.0
	if progress >= 0.47 and progress <= 0.70:
		var packed_center: float = sin(progress * 24.0) * 15.0
		powder = smoothstep(11.0, 25.0, absf(x_position - packed_center))
		packed = 1.0 - powder
	if absf(x_position) > 62.0:
		powder = maxf(powder, smoothstep(62.0, 85.0, absf(x_position)))
		packed = 1.0 - powder
	if progress >= 0.30 and progress <= 0.47:
		var ice_t: float = inverse_lerp(0.30, 0.47, progress)
		var ice_center: float = lerpf(-38.0, -18.0, ice_t)
		ice = 1.0 - smoothstep(5.5, 10.5, absf(x_position - ice_center))
	if progress >= 0.70 and progress <= 0.82:
		ice = maxf(ice, 1.0 - smoothstep(4.0, 8.5, absf(x_position + 42.0)))
	packed *= 1.0 - ice
	powder *= 1.0 - ice
	return Color(powder, packed, ice, 1.0)


func _band(value: float, start: float, finish: float, feather: float) -> float:
	return smoothstep(start - feather, start + feather, value) \
		* (1.0 - smoothstep(finish - feather, finish + feather, value))
