class_name SkiGroundProbe
extends Node3D

## The sole authority for skier/terrain contact. Other player systems consume
## this component's sample instead of performing their own grounded checks.

signal contact_changed(is_grounded: bool)
signal sample_updated(normal: Vector3, point: Vector3, surface_key: StringName)
signal surface_changed(surface_key: StringName)

@export var probes: Array[RayCast3D] = []
@export_range(0.0, 1.0, 0.01) var minimum_floor_dot: float = 0.55
@export_range(0.0, 0.5, 0.01) var contact_memory_seconds: float = 0.08
@export var default_surface_key: StringName = &"packed"

var is_grounded: bool = false
var raw_contact: bool = false
var ground_normal: Vector3 = Vector3.UP
var contact_point: Vector3 = Vector3.ZERO
var surface_key: StringName = &"packed"
var friction_multiplier: float = 1.0
var edge_grip_multiplier: float = 1.0
var spray_multiplier: float = 1.0
var powder_factor: float = 0.0
var speed_multiplier: float = 1.0
var collider: Object = null

var _contact_memory: float = 0.0
var _suppression_time: float = 0.0
var _body: CollisionObject3D = null


func _ready() -> void:
	_body = get_parent() as CollisionObject3D
	if probes.is_empty():
		for child: Node in get_children():
			var ray := child as RayCast3D
			if ray != null:
				probes.append(ray)
	for ray: RayCast3D in probes:
		ray.enabled = true
		if _body != null:
			ray.add_exception(_body)
	surface_key = default_surface_key


func physics_sample(delta: float) -> void:
	_suppression_time = maxf(0.0, _suppression_time - delta)
	var normals: Array[Vector3] = []
	var points: Array[Vector3] = []
	var closest_distance := INF
	var closest_collider: Object = null
	var closest_point := global_position

	for ray: RayCast3D in probes:
		ray.force_raycast_update()
		if not ray.is_colliding():
			continue
		var hit_normal: Vector3 = ray.get_collision_normal().normalized()
		if hit_normal.dot(Vector3.UP) < minimum_floor_dot:
			continue
		var hit_point: Vector3 = ray.get_collision_point()
		normals.append(hit_normal)
		points.append(hit_point)
		var distance := ray.global_position.distance_to(hit_point)
		if distance < closest_distance:
			closest_distance = distance
			closest_collider = ray.get_collider()
			closest_point = hit_point

	raw_contact = not normals.is_empty() and _suppression_time <= 0.0
	if raw_contact:
		_contact_memory = contact_memory_seconds
		ground_normal = _average_vectors(normals, Vector3.UP).normalized()
		contact_point = _average_vectors(points, closest_point)
		collider = closest_collider
		_read_surface_sample(closest_collider, closest_point)
	else:
		_contact_memory = maxf(0.0, _contact_memory - delta)
		if _contact_memory <= 0.0:
			collider = null

	var next_grounded := raw_contact or (_contact_memory > 0.0 and _suppression_time <= 0.0)
	if next_grounded != is_grounded:
		is_grounded = next_grounded
		contact_changed.emit(is_grounded)
	if is_grounded:
		sample_updated.emit(ground_normal, contact_point, surface_key)


func suppress_contact(seconds: float) -> void:
	_suppression_time = maxf(_suppression_time, seconds)
	_contact_memory = 0.0
	raw_contact = false
	if is_grounded:
		is_grounded = false
		contact_changed.emit(false)


func clear_contact() -> void:
	_contact_memory = 0.0
	raw_contact = false
	collider = null
	if is_grounded:
		is_grounded = false
		contact_changed.emit(false)


func override_surface(
		new_key: StringName,
		new_friction_multiplier: float = 1.0,
		new_edge_grip_multiplier: float = 1.0,
		new_spray_multiplier: float = 1.0,
		new_powder_factor: float = 0.0
	) -> void:
	_apply_surface_dictionary({
		"surface_key": new_key,
		"friction_multiplier": new_friction_multiplier,
		"edge_grip_multiplier": new_edge_grip_multiplier,
		"spray_multiplier": new_spray_multiplier,
		"powder_factor": new_powder_factor,
	})


func _read_surface_sample(hit_collider: Object, world_point: Vector3) -> void:
	if hit_collider != null and hit_collider.has_method("get_snow_surface_sample"):
		var result: Variant = hit_collider.call("get_snow_surface_sample", world_point)
		if result is Dictionary:
			_apply_surface_dictionary(result as Dictionary)
			return
	var metadata_source := hit_collider as Node
	if metadata_source != null and metadata_source.has_meta("surface_key"):
		_apply_surface_dictionary({"surface_key": metadata_source.get_meta("surface_key")})
		return
	_apply_surface_dictionary({"surface_key": default_surface_key})


func _apply_surface_dictionary(sample: Dictionary) -> void:
	var previous_key := surface_key
	var raw_surface: Variant = sample.get("surface_key", sample.get("name", sample.get("type", default_surface_key)))
	surface_key = _canonical_surface_key(raw_surface)
	friction_multiplier = maxf(0.0, float(sample.get("friction_multiplier", 1.0)))
	edge_grip_multiplier = maxf(0.0, float(sample.get("edge_grip_multiplier", 1.0)))
	spray_multiplier = maxf(0.0, float(sample.get("spray_multiplier", 1.0)))
	powder_factor = clampf(float(sample.get("powder_factor", sample.get("powder_amount", 0.0))), 0.0, 1.0)
	speed_multiplier = clampf(float(sample.get("speed_multiplier", 1.0)), 0.25, 2.0)
	if surface_key != previous_key:
		surface_changed.emit(surface_key)


func _canonical_surface_key(raw_surface: Variant) -> StringName:
	if raw_surface is int:
		match int(raw_surface):
			0:
				return &"fresh_powder"
			1:
				return &"packed"
			2:
				return &"existing_tracks"
			3:
				return &"ice"
	var normalized := String(raw_surface).strip_edges().to_lower().replace(" ", "_")
	match normalized:
		"fresh_powder", "powder":
			return &"fresh_powder"
		"packed_snow", "packed":
			return &"packed"
		"existing_tracks", "tracks", "tracked":
			return &"existing_tracks"
		"blue_ice", "ice":
			return &"ice"
		_:
			return StringName(normalized)


func _average_vectors(values: Array[Vector3], fallback: Vector3) -> Vector3:
	if values.is_empty():
		return fallback
	var total := Vector3.ZERO
	for value: Vector3 in values:
		total += value
	return total / float(values.size())
