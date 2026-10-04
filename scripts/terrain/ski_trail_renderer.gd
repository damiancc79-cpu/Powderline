class_name SkiTrailRenderer
extends Node3D

@export_range(32, 600, 1) var max_points_per_ski: int = 240
@export_range(2.0, 60.0, 0.5) var trail_lifetime: float = 24.0
@export_range(0.04, 0.3, 0.01) var base_width: float = 0.105
@export_range(0.05, 1.0, 0.01) var minimum_point_spacing: float = 0.24
@export_range(1.0, 10.0, 0.1) var maximum_segment_length: float = 3.2
@export_range(5.0, 60.0, 1.0) var samples_per_second: float = 24.0
@export var trail_shader: Shader = preload("res://shaders/ski_trail.gdshader")

var _target: Node3D
var _terrain: Node
var _mesh_instance: MeshInstance3D
var _trail_material: ShaderMaterial
var _left_points: Array[Vector3] = []
var _right_points: Array[Vector3] = []
var _left_times: Array[float] = []
var _right_times: Array[float] = []
var _left_widths: Array[float] = []
var _right_widths: Array[float] = []
var _left_strengths: Array[float] = []
var _right_strengths: Array[float] = []
var _sample_clock: float = 0.0
var _render_clock: float = 0.0
var _last_forward: Vector3 = Vector3.FORWARD


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "BoundedTrailMesh"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	_trail_material = ShaderMaterial.new()
	_trail_material.shader = trail_shader


func _process(delta: float) -> void:
	_sample_clock += delta
	_render_clock += delta
	if _target != null and is_instance_valid(_target) \
		and _sample_clock >= 1.0 / samples_per_second:
		_sample_clock = 0.0
		_auto_sample_target()
	if _render_clock >= 0.08:
		_render_clock = 0.0
		_expire_old_points()
		_rebuild_mesh()


func set_target(target: Node3D, terrain_provider: Node = null) -> void:
	_target = target
	if terrain_provider != null:
		_terrain = terrain_provider


func set_terrain_provider(terrain_provider: Node) -> void:
	_terrain = terrain_provider


func record_skis(
	left_world_position: Vector3,
	right_world_position: Vector3,
	ground_normal: Vector3 = Vector3.UP,
	carve_amount: float = 0.0,
	strength: float = 1.0
) -> void:
	var now: float = Time.get_ticks_msec() * 0.001
	var width: float = base_width * lerpf(1.0, 1.48, clampf(absf(carve_amount), 0.0, 1.0))
	_append_point(
		left_world_position + ground_normal.normalized() * 0.025,
		now,
		width,
		strength,
		_left_points,
		_left_times,
		_left_widths,
		_left_strengths
	)
	_append_point(
		right_world_position + ground_normal.normalized() * 0.025,
		now,
		width,
		strength,
		_right_points,
		_right_times,
		_right_widths,
		_right_strengths
	)
	if _terrain != null and _terrain.has_method("mark_surface_tracked"):
		_terrain.call("mark_surface_tracked", (left_world_position + right_world_position) * 0.5, strength)


func clear_trails() -> void:
	_left_points.clear()
	_right_points.clear()
	_left_times.clear()
	_right_times.clear()
	_left_widths.clear()
	_right_widths.clear()
	_left_strengths.clear()
	_right_strengths.clear()
	if _mesh_instance != null:
		_mesh_instance.mesh = null


func get_active_segment_count() -> int:
	return maxi(0, _left_points.size() - 1) + maxi(0, _right_points.size() - 1)


func _auto_sample_target() -> void:
	var center: Vector3 = _target.global_position
	var terrain_height: float = center.y - 1.0
	var normal: Vector3 = Vector3.UP
	if _terrain != null:
		if _terrain.has_method("height_at_world"):
			terrain_height = float(_terrain.call("height_at_world", center))
		if _terrain.has_method("normal_at_world"):
			normal = _terrain.call("normal_at_world", center)
	if center.y - terrain_height > 2.15 or center.y < terrain_height - 0.35:
		return
	var forward: Vector3 = -_target.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = _last_forward
	else:
		forward = forward.normalized()
	_last_forward = forward
	var right: Vector3 = _target.global_basis.x.normalized()
	var left_position: Vector3 = center - right * 0.31 + forward * 0.12
	var right_position: Vector3 = center + right * 0.31 + forward * 0.12
	left_position.y = terrain_height
	right_position.y = terrain_height
	var velocity: Vector3 = _read_target_velocity()
	var planar_velocity: Vector3 = velocity.slide(normal)
	var carve_amount: float = 0.0
	if planar_velocity.length() > 1.0:
		carve_amount = clampf(absf(planar_velocity.normalized().dot(right)), 0.0, 1.0)
	var strength: float = clampf(planar_velocity.length() / 18.0, 0.25, 1.0)
	record_skis(left_position, right_position, normal, carve_amount, strength)


func _read_target_velocity() -> Vector3:
	if _target is CharacterBody3D:
		return (_target as CharacterBody3D).velocity
	if _target is RigidBody3D:
		return (_target as RigidBody3D).linear_velocity
	return Vector3.ZERO


func _append_point(
	point: Vector3,
	timestamp: float,
	width: float,
	strength: float,
	points: Array[Vector3],
	times: Array[float],
	widths: Array[float],
	strengths: Array[float]
) -> void:
	if not points.is_empty() and points[points.size() - 1].distance_to(point) < minimum_point_spacing:
		return
	points.append(point)
	times.append(timestamp)
	widths.append(width)
	strengths.append(clampf(strength, 0.15, 1.0))
	while points.size() > max_points_per_ski:
		points.pop_front()
		times.pop_front()
		widths.pop_front()
		strengths.pop_front()


func _expire_old_points() -> void:
	var now: float = Time.get_ticks_msec() * 0.001
	_expire_side(now, _left_points, _left_times, _left_widths, _left_strengths)
	_expire_side(now, _right_points, _right_times, _right_widths, _right_strengths)


func _expire_side(
	now: float,
	points: Array[Vector3],
	times: Array[float],
	widths: Array[float],
	strengths: Array[float]
) -> void:
	while not times.is_empty() and now - times[0] > trail_lifetime:
		points.pop_front()
		times.pop_front()
		widths.pop_front()
		strengths.pop_front()


func _rebuild_mesh() -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var now: float = Time.get_ticks_msec() * 0.001
	_add_side_geometry(
		_left_points, _left_times, _left_widths, _left_strengths,
		now, vertices, normals, colors, uvs, indices
	)
	_add_side_geometry(
		_right_points, _right_times, _right_widths, _right_strengths,
		now, vertices, normals, colors, uvs, indices
	)
	if vertices.is_empty():
		_mesh_instance.mesh = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var trail_mesh: ArrayMesh = ArrayMesh.new()
	trail_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	trail_mesh.surface_set_material(0, _trail_material)
	_mesh_instance.mesh = trail_mesh


func _add_side_geometry(
	points: Array[Vector3],
	times: Array[float],
	widths: Array[float],
	strengths: Array[float],
	now: float,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	indices: PackedInt32Array
) -> void:
	for index: int in range(points.size() - 1):
		var start: Vector3 = points[index]
		var finish: Vector3 = points[index + 1]
		var distance: float = start.distance_to(finish)
		if distance > maximum_segment_length or distance < 0.01:
			continue
		var normal: Vector3 = Vector3.UP
		if _terrain != null and _terrain.has_method("normal_at_world"):
			normal = _terrain.call("normal_at_world", (start + finish) * 0.5)
		var tangent: Vector3 = (finish - start).normalized()
		var side: Vector3 = normal.cross(tangent).normalized()
		if side.length_squared() < 0.1:
			side = Vector3.RIGHT
		var start_width: float = widths[index] * 0.5
		var finish_width: float = widths[index + 1] * 0.5
		var base_index: int = vertices.size()
		vertices.append(to_local(start - side * start_width))
		vertices.append(to_local(start + side * start_width))
		vertices.append(to_local(finish - side * finish_width))
		vertices.append(to_local(finish + side * finish_width))
		for unused: int in range(4):
			normals.append(normal)
		var start_alpha: float = clampf(1.0 - (now - times[index]) / trail_lifetime, 0.0, 1.0)
		var finish_alpha: float = clampf(1.0 - (now - times[index + 1]) / trail_lifetime, 0.0, 1.0)
		var start_color: Color = Color(0.22, 0.43, 0.58, start_alpha * strengths[index])
		var finish_color: Color = Color(0.22, 0.43, 0.58, finish_alpha * strengths[index + 1])
		colors.append_array(PackedColorArray([start_color, start_color, finish_color, finish_color]))
		uvs.append_array(PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(1.0, 0.0),
			Vector2(0.0, distance), Vector2(1.0, distance),
		]))
		indices.append_array(PackedInt32Array([
			base_index, base_index + 2, base_index + 1,
			base_index + 1, base_index + 2, base_index + 3,
		]))
