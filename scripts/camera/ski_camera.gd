class_name SkiCamera
extends Node3D

## A world-space chase rig. It follows the controller root, never the aerial
## trick visual, so spins and flips remain readable.

@export var target: Node3D
@export var spring_arm: SpringArm3D
@export var camera: Camera3D

@export_category("Follow")
@export_range(0.1, 30.0, 0.1) var follow_response: float = 7.0
@export_range(0.1, 30.0, 0.1) var rotation_response: float = 8.5
@export_range(0.0, 10.0, 0.1) var focus_height: float = 1.45
@export_range(0.0, 20.0, 0.1) var look_ahead_distance: float = 5.0
@export_range(1.0, 20.0, 0.1) var minimum_follow_distance: float = 5.2
@export_range(1.0, 30.0, 0.1) var maximum_follow_distance: float = 8.8
@export_range(1.0, 80.0, 0.5) var full_speed_at: float = 34.0

@export_category("Lens and carve")
@export_range(30.0, 120.0, 1.0) var base_fov: float = 68.0
@export_range(30.0, 130.0, 1.0) var high_speed_fov: float = 82.0
@export_range(0.0, 20.0, 0.1) var fov_response: float = 6.0
@export_range(0.0, 20.0, 0.25) var maximum_carve_roll_degrees: float = 5.0

@export_category("Impact feedback")
@export_range(0.0, 2.0, 0.05) var shake_scale: float = 1.0
@export_range(0.0, 2.0, 0.05) var reduced_shake_scale: float = 0.35
@export var reduced_shake: bool = false
@export_range(0.0, 10.0, 0.1) var trauma_decay: float = 2.4
@export_range(0.0, 1.0, 0.01) var maximum_shake_offset: float = 0.22
@export_range(0.0, 20.0, 0.1) var maximum_shake_roll_degrees: float = 4.0

var _trauma: float = 0.0
var _landing_pitch: float = 0.0
var _shake_clock: float = 0.0
var _last_forward: Vector3 = Vector3.FORWARD
var _initialized: bool = false


func _ready() -> void:
	if target == null:
		target = get_parent() as Node3D
	if spring_arm == null:
		spring_arm = get_node_or_null("SpringArm3D") as SpringArm3D
	if camera == null and spring_arm != null:
		camera = spring_arm.get_node_or_null("Camera3D") as Camera3D
	top_level = true
	_bind_target_signals()
	if target != null:
		_snap_to_target()


func _process(delta: float) -> void:
	if target == null or spring_arm == null or camera == null:
		return
	var skier := target as SkierController
	var speed := skier.speed_mps if skier != null else 0.0
	var steer := skier.steering_input if skier != null else 0.0
	var speed_ratio := clampf(speed / full_speed_at, 0.0, 1.0)
	var forward := (target.global_basis * Vector3.FORWARD).slide(Vector3.UP)
	if forward.length_squared() > 0.01:
		_last_forward = forward.normalized()

	var look_ahead := _last_forward * look_ahead_distance * speed_ratio
	var desired_origin := target.global_position + Vector3.UP * focus_height + look_ahead
	var follow_weight := 1.0 - exp(-follow_response * delta)
	if not _initialized:
		global_position = desired_origin
		_initialized = true
	else:
		global_position = global_position.lerp(desired_origin, follow_weight)

	var aim_point := target.global_position + Vector3.UP * 0.7 + look_ahead
	var look_direction := (aim_point - global_position).normalized()
	if look_direction.length_squared() < 0.01:
		look_direction = _last_forward
	var desired_basis := Basis.looking_at(look_direction, Vector3.UP)
	var rotation_weight := 1.0 - exp(-rotation_response * delta)
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(
		desired_basis.get_rotation_quaternion(), rotation_weight
	)).orthonormalized()

	_trauma = maxf(0.0, _trauma - trauma_decay * delta)
	_landing_pitch = lerpf(_landing_pitch, 0.0, 1.0 - exp(-8.0 * delta))
	_shake_clock += delta * 37.0
	var accessibility_scale := reduced_shake_scale if reduced_shake else shake_scale
	var shake_strength := _trauma * _trauma * accessibility_scale
	var offset := Vector3(
		sin(_shake_clock * 1.31),
		sin(_shake_clock * 1.73 + 1.7),
		0.0
	) * maximum_shake_offset * shake_strength
	spring_arm.position = offset
	var carve_roll := deg_to_rad(maximum_carve_roll_degrees) * -steer * speed_ratio
	var shake_roll := deg_to_rad(maximum_shake_roll_degrees) \
		* sin(_shake_clock * 1.11) * shake_strength
	spring_arm.rotation.z = lerp_angle(
		spring_arm.rotation.z,
		carve_roll + shake_roll,
		1.0 - exp(-8.0 * delta)
	)
	spring_arm.rotation.x = _landing_pitch
	spring_arm.spring_length = lerpf(minimum_follow_distance, maximum_follow_distance, speed_ratio)
	camera.fov = lerpf(camera.fov, lerpf(base_fov, high_speed_fov, speed_ratio), 1.0 - exp(-fov_response * delta))


func set_target(new_target: Node3D) -> void:
	_unbind_target_signals()
	target = new_target
	_initialized = false
	_bind_target_signals()
	if is_inside_tree() and target != null:
		_snap_to_target()


func add_crash_shake(impact_speed: float) -> void:
	_trauma = clampf(_trauma + impact_speed / 24.0, 0.0, 1.0)


func add_landing_impact(strength: float) -> void:
	var clamped_strength := clampf(strength, 0.0, 1.5)
	_trauma = clampf(_trauma + clamped_strength * 0.35, 0.0, 1.0)
	_landing_pitch = deg_to_rad(3.5) * clamped_strength


func set_reduced_shake(enabled: bool) -> void:
	reduced_shake = enabled


func _snap_to_target() -> void:
	if target == null:
		return
	var forward := (target.global_basis * Vector3.FORWARD).slide(Vector3.UP)
	if forward.length_squared() > 0.01:
		_last_forward = forward.normalized()
	global_position = target.global_position + Vector3.UP * focus_height
	global_basis = Basis.looking_at(_last_forward, Vector3.UP)
	_initialized = true


func _bind_target_signals() -> void:
	if target == null:
		return
	var crash_callable := Callable(self, "_on_target_crashed")
	var landing_callable := Callable(self, "_on_target_landing_impact")
	if target.has_signal("crashed") and not target.is_connected("crashed", crash_callable):
		target.connect("crashed", crash_callable)
	if target.has_signal("landing_impact") and not target.is_connected("landing_impact", landing_callable):
		target.connect("landing_impact", landing_callable)


func _unbind_target_signals() -> void:
	if target == null:
		return
	var crash_callable := Callable(self, "_on_target_crashed")
	var landing_callable := Callable(self, "_on_target_landing_impact")
	if target.has_signal("crashed") and target.is_connected("crashed", crash_callable):
		target.disconnect("crashed", crash_callable)
	if target.has_signal("landing_impact") and target.is_connected("landing_impact", landing_callable):
		target.disconnect("landing_impact", landing_callable)


func _on_target_crashed(_reason: StringName, impact_speed: float) -> void:
	add_crash_shake(impact_speed)


func _on_target_landing_impact(strength: float) -> void:
	add_landing_impact(strength)
