class_name SkierController
extends CharacterBody3D

## Momentum-first CharacterBody3D skier. SkiGroundProbe is the sole contact
## authority; this controller owns all visible state transitions.

enum SkiState {
	GROUNDED,
	AIRBORNE,
	LANDING,
	CRASHED,
	RECOVERING,
	FINISHED,
}

signal state_changed(previous_state: int, current_state: int)
signal speed_changed(speed_mps: float)
signal surface_changed(surface_key: StringName)
signal takeoff(initial_velocity: Vector3)
signal landed(success: bool, landing_data: Dictionary)
signal crashed(reason: StringName, impact_speed: float)
signal recovery_started(checkpoint_transform: Transform3D)
signal recovered()
signal checkpoint_updated(checkpoint_transform: Transform3D)
signal trail_state_changed(active: bool, width: float, intensity: float)
signal snow_spray_requested(
	kind: StringName,
	intensity: float,
	world_position: Vector3,
	normal: Vector3
)
signal landing_impact(strength: float)
signal finished(final_score: int, elapsed_seconds: float)

@export var tuning: SkiTuning
@export_category("Input actions")
@export var forward_action: StringName = &"move_forward"
@export var back_action: StringName = &"move_back"
@export var steer_left_action: StringName = &"steer_left"
@export var steer_right_action: StringName = &"steer_right"
@export var jump_action: StringName = &"jump"
@export var tuck_grab_action: StringName = &"tuck_grab"
@export var restart_action: StringName = &"restart"
@export_category("Startup")
@export var begin_scoring_on_ready: bool = true
@export var initial_weather_score_multiplier: float = 1.0

@onready var ground_probe: SkiGroundProbe = $GroundProbes as SkiGroundProbe
@onready var trick_controller: TrickController = $TrickController as TrickController
@onready var crash_controller: CrashController = $CrashController as CrashController
@onready var landing_evaluator: LandingEvaluator = $LandingEvaluator as LandingEvaluator
@onready var score_manager: ScoreManager = $ScoreManager as ScoreManager
@onready var trick_visual: Node3D = $VisualRoot as Node3D
@onready var lean_visual: Node3D = $VisualRoot/LeanRoot as Node3D
@onready var spray_origin: Node3D = $SnowSprayOrigin as Node3D

var state: int = SkiState.GROUNDED
var speed_mps: float = 0.0
var steering_input: float = 0.0
var forward_input: float = 0.0
var brake_input: float = 0.0
var tuck_input: float = 0.0
var carve_amount: float = 0.0

var latest_checkpoint: Transform3D
var has_checkpoint: bool = false

var _state_elapsed: float = 0.0
var _airborne_time: float = 0.0
var _missing_ground_time: float = 0.0
var _recovery_transform: Transform3D
var _weather_air_force: Vector3 = Vector3.ZERO
var _weather_drag_multiplier: float = 1.0
var _external_risk_multiplier: float = 1.0
var _spray_cooldown: float = 0.0
var _last_surface_key: StringName = &"packed"


func _ready() -> void:
	if tuning == null:
		tuning = load("res://resources/tuning/default_ski_tuning.tres") as SkiTuning
	floor_snap_length = tuning.floor_snap_length
	floor_stop_on_slope = false
	floor_max_angle = deg_to_rad(72.0)
	up_direction = Vector3.UP
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED

	trick_controller.tuning = tuning
	trick_controller.trick_visual = trick_visual
	trick_controller.style_visual = lean_visual
	crash_controller.tuning = tuning
	crash_controller.crash_requested.connect(_on_crash_requested)
	ground_probe.surface_changed.connect(_on_surface_changed)
	trick_controller.trick_updated.connect(_on_trick_updated)
	latest_checkpoint = global_transform
	has_checkpoint = true
	if begin_scoring_on_ready:
		score_manager.begin_run(initial_weather_score_multiplier)


func _physics_process(delta: float) -> void:
	_state_elapsed += delta
	_spray_cooldown = maxf(0.0, _spray_cooldown - delta)
	crash_controller.tick(delta)

	if Input.is_action_just_pressed(restart_action):
		restart_from_checkpoint(true)
		return

	ground_probe.physics_sample(delta)
	_collect_input()

	if state == SkiState.CRASHED:
		_physics_crashed(delta)
		return
	if state == SkiState.RECOVERING:
		_physics_recovering(delta)
		return
	if state == SkiState.FINISHED:
		_physics_finished(delta)
		return

	_update_contact_state_before_motion()
	if state == SkiState.GROUNDED or state == SkiState.LANDING:
		if Input.is_action_just_pressed(jump_action) and ground_probe.is_grounded:
			_jump()
		else:
			_apply_ground_movement(delta)
	else:
		_apply_air_movement(delta)

	trick_controller.physics_tick(delta, state == SkiState.AIRBORNE, true)
	var pre_move_velocity := velocity
	move_and_slide()
	ground_probe.physics_sample(0.0)

	if state != SkiState.CRASHED and crash_controller.assess_motion_collisions(self, pre_move_velocity):
		return
	_update_contact_state_after_motion(delta, pre_move_velocity)
	_update_feedback(delta)


func set_checkpoint(checkpoint_transform: Transform3D) -> void:
	latest_checkpoint = checkpoint_transform
	has_checkpoint = true
	checkpoint_updated.emit(latest_checkpoint)


func restart_from_checkpoint(penalize_score: bool = true) -> void:
	if penalize_score and score_manager.run_active:
		score_manager.register_crash(&"manual_restart")
	var target := latest_checkpoint if has_checkpoint else global_transform
	_begin_recovery(target, true)


func apply_weather_force(airborne_force: Vector3, drag_multiplier: float = 1.0) -> void:
	_weather_air_force = airborne_force
	_weather_drag_multiplier = clampf(drag_multiplier, 0.5, 3.0)


func set_weather_score_multiplier(multiplier: float) -> void:
	score_manager.set_weather_multiplier(multiplier)


func set_external_risk_multiplier(multiplier: float, powder_bonus: float = 1.0) -> void:
	_external_risk_multiplier = clampf(multiplier, 1.0, 4.0)
	score_manager.set_risk_context(_external_risk_multiplier, powder_bonus)


func set_surface_response(
		surface_key: StringName,
		friction_multiplier: float = 1.0,
		edge_grip_multiplier: float = 1.0,
		spray_multiplier: float = 1.0,
		powder_factor: float = 0.0
	) -> void:
	ground_probe.override_surface(
		surface_key,
		friction_multiplier,
		edge_grip_multiplier,
		spray_multiplier,
		powder_factor
	)


func register_near_miss(
		distance_metres: float,
		hazard_key: StringName = &"hazard"
	) -> int:
	return score_manager.register_near_miss(distance_metres, speed_mps, hazard_key)


func register_shortcut(shortcut_name: String, points: int = 250, route_multiplier: float = 1.35) -> int:
	return score_manager.register_shortcut(shortcut_name, points, route_multiplier)


func register_missed_gate(gate_name: String = "gate") -> void:
	score_manager.register_gate_missed(gate_name)


func finish_run() -> void:
	if state == SkiState.FINISHED:
		return
	_change_state(SkiState.FINISHED)
	var final_score := score_manager.finish_run()
	trail_state_changed.emit(false, tuning.trail_base_width, 0.0)
	finished.emit(final_score, score_manager.elapsed_seconds)


func reset_run(start_transform: Transform3D = Transform3D.IDENTITY) -> void:
	if start_transform != Transform3D.IDENTITY:
		global_transform = start_transform
	latest_checkpoint = global_transform
	has_checkpoint = true
	velocity = Vector3.ZERO
	ground_probe.clear_contact()
	crash_controller.reset()
	trick_controller.cancel_airborne()
	score_manager.begin_run(initial_weather_score_multiplier)
	_change_state(SkiState.GROUNDED)


func get_state_name() -> StringName:
	return StringName(SkiState.keys()[state])


func get_debug_snapshot() -> Dictionary:
	return {
		"state": get_state_name(),
		"speed_mps": speed_mps,
		"velocity": velocity,
		"grounded": ground_probe.is_grounded,
		"ground_normal": ground_probe.ground_normal,
		"surface": ground_probe.surface_key,
		"carve": carve_amount,
		"score": score_manager.score,
		"combo": score_manager.combo_manager.multiplier if score_manager.combo_manager != null else 1.0,
	}


func _collect_input() -> void:
	steering_input = Input.get_axis(steer_left_action, steer_right_action)
	forward_input = Input.get_action_strength(forward_action)
	brake_input = Input.get_action_strength(back_action)
	tuck_input = maxf(forward_input, Input.get_action_strength(tuck_grab_action))


func _apply_ground_movement(delta: float) -> void:
	var normal := ground_probe.ground_normal.normalized()
	var tangent_velocity := velocity.slide(normal)
	var speed := tangent_velocity.length()
	var forward := _motion_forward(normal)
	var speed_ratio := clampf(speed / tuning.full_speed_steering_at, 0.0, 1.0)
	var turn_rate := deg_to_rad(lerpf(
		tuning.low_speed_turn_rate_degrees,
		tuning.high_speed_turn_rate_degrees,
		speed_ratio
	))
	var desired_forward := forward.rotated(normal, -steering_input * turn_rate * delta).normalized()

	if speed > 0.1:
		var travel_direction := tangent_velocity.normalized()
		var steer_response := tuning.steering_response * lerpf(1.0, 0.38, speed_ratio)
		var steering_weight := 1.0 - exp(-steer_response * absf(steering_input) * delta)
		var steered_direction := travel_direction.slerp(desired_forward, steering_weight).normalized()
		tangent_velocity = steered_direction * speed
	else:
		tangent_velocity += desired_forward * forward_input * tuning.low_speed_push * delta

	var lateral_velocity := tangent_velocity - desired_forward * tangent_velocity.dot(desired_forward)
	var grip := tuning.edge_grip * ground_probe.edge_grip_multiplier
	var carve_response := tuning.carve_strength * grip * lerpf(1.15, 0.58, speed_ratio)
	var lateral_reduction := 1.0 - exp(-carve_response * delta)
	lateral_reduction *= lerpf(tuning.lateral_damping, 1.0, absf(steering_input))
	tangent_velocity -= lateral_velocity * clampf(lateral_reduction, 0.0, 0.94)

	# The component of gravity tangent to the slope naturally accelerates the run.
	var slope_gravity := (Vector3.DOWN * tuning.gravity).slide(normal) * tuning.slope_gravity_scale
	tangent_velocity += slope_gravity * delta
	if forward_input > 0.0 and tangent_velocity.length() < 10.0:
		tangent_velocity += desired_forward * forward_input * tuning.low_speed_push * delta
	if brake_input > 0.0 and tangent_velocity.length() < 1.25:
		tangent_velocity -= desired_forward * brake_input * tuning.low_speed_push * 0.55 * delta

	var friction := _surface_friction() * ground_probe.friction_multiplier
	var tangent_speed := tangent_velocity.length()
	if tangent_speed > 0.001:
		var friction_speed := move_toward(tangent_speed, 0.0, friction * delta)
		tangent_velocity *= friction_speed / tangent_speed
	var aerodynamic_coefficient := lerpf(tuning.aerodynamic_drag, tuning.tuck_drag, tuck_input)
	aerodynamic_coefficient *= _weather_drag_multiplier
	tangent_velocity *= maxf(0.0, 1.0 - aerodynamic_coefficient * tangent_velocity.length() * delta)
	if brake_input > 0.0:
		var brake_speed := move_toward(tangent_velocity.length(), 0.0, tuning.brake_drag * brake_input * delta)
		tangent_velocity = tangent_velocity.normalized() * brake_speed if brake_speed > 0.001 else Vector3.ZERO
	var surface_speed_limit := tuning.practical_max_speed * ground_probe.speed_multiplier
	if tangent_velocity.length() > surface_speed_limit:
		var overspeed := tangent_velocity.length() - surface_speed_limit
		var reduced_speed := move_toward(
			tangent_velocity.length(), surface_speed_limit,
			overspeed * tuning.overspeed_drag * delta
		)
		tangent_velocity = tangent_velocity.normalized() * reduced_speed

	# Floor snap maintains contact. Injecting velocity along -normal would leave
	# an uphill horizontal component after CharacterBody3D resolves a slope.
	velocity = tangent_velocity
	carve_amount = clampf(absf(steering_input) * speed_ratio * grip, 0.0, 1.0)
	_align_body(desired_forward, normal, delta)
	_update_grounded_visual(delta, speed_ratio)


func _apply_air_movement(delta: float) -> void:
	velocity += Vector3.DOWN * tuning.gravity * delta
	velocity += _weather_air_force * tuning.wind_response * delta
	var air_drag := tuning.airborne_drag * _weather_drag_multiplier
	velocity *= maxf(0.0, 1.0 - air_drag * delta)
	if absf(steering_input) > 0.01:
		var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
		if horizontal_velocity.length_squared() > 0.01:
			var desired_direction := horizontal_velocity.normalized().rotated(
				Vector3.UP, -steering_input * tuning.air_control * delta
			)
			var controlled_horizontal := horizontal_velocity.normalized().slerp(
				desired_direction, clampf(tuning.air_control * delta, 0.0, 1.0)
			) * horizontal_velocity.length()
			velocity.x = controlled_horizontal.x
			velocity.z = controlled_horizontal.z
	carve_amount = 0.0


func _physics_crashed(delta: float) -> void:
	trick_controller.physics_tick(delta, false, false)
	velocity += Vector3.DOWN * tuning.gravity * delta
	velocity *= maxf(0.0, 1.0 - 2.3 * delta)
	move_and_slide()
	ground_probe.physics_sample(0.0)
	trail_state_changed.emit(false, tuning.trail_base_width, 0.0)
	speed_mps = velocity.length()
	speed_changed.emit(speed_mps)
	if _state_elapsed >= tuning.crash_control_lock_time:
		_begin_recovery(latest_checkpoint if has_checkpoint else _recovery_transform, false)


func _physics_recovering(delta: float) -> void:
	velocity = Vector3.ZERO
	ground_probe.physics_sample(delta)
	trick_controller.physics_tick(delta, false, false)
	trail_state_changed.emit(false, tuning.trail_base_width, 0.0)
	if _state_elapsed >= tuning.recovery_settle_time:
		_change_state(SkiState.GROUNDED)
		recovered.emit()


func _physics_finished(delta: float) -> void:
	var normal := ground_probe.ground_normal if ground_probe.is_grounded else Vector3.UP
	velocity += Vector3.DOWN * tuning.gravity * delta
	velocity = velocity.slide(normal)
	velocity *= maxf(0.0, 1.0 - 2.0 * delta)
	move_and_slide()
	trail_state_changed.emit(false, tuning.trail_base_width, 0.0)
	speed_mps = velocity.length()
	speed_changed.emit(speed_mps)


func _update_contact_state_before_motion() -> void:
	if state == SkiState.AIRBORNE:
		return
	if (state == SkiState.GROUNDED or state == SkiState.LANDING) and not ground_probe.is_grounded:
		_missing_ground_time += get_physics_process_delta_time()
		if _missing_ground_time >= tuning.ground_probe_grace:
			_begin_airborne(false)
	else:
		_missing_ground_time = 0.0


func _update_contact_state_after_motion(delta: float, pre_move_velocity: Vector3) -> void:
	if state == SkiState.AIRBORNE:
		_airborne_time += delta
		if ground_probe.raw_contact and _airborne_time >= tuning.landing_grace:
			_resolve_landing(pre_move_velocity)
	elif state == SkiState.LANDING:
		if not ground_probe.is_grounded:
			_begin_airborne(false)
		elif _state_elapsed >= 0.12:
			_change_state(SkiState.GROUNDED)


func _jump() -> void:
	var normal := ground_probe.ground_normal.normalized()
	var forward := _motion_forward(normal)
	velocity = velocity.slide(normal)
	velocity += normal * tuning.jump_impulse
	velocity += forward * tuning.jump_forward_boost
	ground_probe.suppress_contact(maxf(tuning.landing_grace, 0.18))
	_begin_airborne(true)
	snow_spray_requested.emit(&"takeoff", 1.0, spray_origin.global_position, normal)


func _begin_airborne(from_jump: bool) -> void:
	if state == SkiState.AIRBORNE:
		return
	_missing_ground_time = 0.0
	_airborne_time = 0.0
	floor_snap_length = 0.0
	_change_state(SkiState.AIRBORNE)
	trick_controller.begin_airborne()
	takeoff.emit(velocity)
	if not from_jump:
		ground_probe.suppress_contact(0.04)


func _resolve_landing(pre_move_velocity: Vector3) -> void:
	var normal := ground_probe.ground_normal.normalized()
	var impact_speed := maxf(0.0, -pre_move_velocity.dot(normal))
	var visual_up := trick_visual.global_basis.y.normalized()
	var visual_forward := (trick_visual.global_basis * Vector3.FORWARD).normalized()
	var landing_data := landing_evaluator.evaluate(
		impact_speed,
		visual_up,
		visual_forward,
		pre_move_velocity,
		normal,
		tuning
	)
	var success := bool(landing_data.get("success", false))
	var trick_snapshot := trick_controller.resolve_airborne(success)
	score_manager.resolve_landing(trick_snapshot, landing_data)
	floor_snap_length = tuning.floor_snap_length
	landing_impact.emit(clampf(impact_speed / tuning.crash_impact_speed, 0.0, 1.5))
	snow_spray_requested.emit(
		&"landing",
		clampf(0.4 + impact_speed / tuning.hard_landing_speed, 0.4, 2.0),
		spray_origin.global_position,
		normal
	)
	landed.emit(success, landing_data)
	if success:
		velocity = velocity.slide(normal) * lerpf(0.78, 0.98, float(landing_data.get("quality", 0.5)))
		_change_state(SkiState.LANDING)
	else:
		crash_controller.assess_landing(landing_data)


func _on_crash_requested(reason: StringName, impact_speed: float) -> void:
	if state == SkiState.CRASHED or state == SkiState.RECOVERING or state == SkiState.FINISHED:
		return
	trick_controller.cancel_airborne()
	score_manager.register_crash(reason)
	_recovery_transform = global_transform
	velocity = velocity * 0.28 + ground_probe.ground_normal * minf(3.5, impact_speed * 0.12)
	_change_state(SkiState.CRASHED)
	trail_state_changed.emit(false, tuning.trail_base_width, 0.0)
	snow_spray_requested.emit(
		&"crash",
		clampf(impact_speed / tuning.obstacle_crash_speed, 0.75, 2.5),
		spray_origin.global_position,
		ground_probe.ground_normal
	)
	crashed.emit(reason, impact_speed)


func _begin_recovery(target: Transform3D, manual: bool) -> void:
	_recovery_transform = target
	_change_state(SkiState.RECOVERING)
	velocity = Vector3.ZERO
	global_transform = target
	ground_probe.clear_contact()
	crash_controller.reset()
	trick_controller.cancel_airborne()
	recovery_started.emit(target)
	if manual:
		snow_spray_requested.emit(&"recovery", 0.25, global_position, Vector3.UP)


func _update_feedback(delta: float) -> void:
	speed_mps = velocity.length()
	speed_changed.emit(speed_mps)
	var on_snow := state == SkiState.GROUNDED or state == SkiState.LANDING
	var trail_width := tuning.trail_base_width * (1.0 + carve_amount * tuning.trail_carve_width_scale)
	var trail_intensity := clampf(speed_mps / 18.0, 0.15, 1.0) \
		* lerpf(0.7, 1.35, ground_probe.powder_factor)
	trail_state_changed.emit(on_snow and speed_mps > 0.6, trail_width, trail_intensity)
	if on_snow and _spray_cooldown <= 0.0:
		var spray_kind: StringName = &""
		var intensity := 0.0
		if brake_input >= tuning.spray_brake_threshold and speed_mps > 3.0:
			spray_kind = &"brake"
			intensity = brake_input * clampf(speed_mps / 15.0, 0.25, 1.5)
		elif carve_amount >= tuning.spray_carve_threshold:
			spray_kind = &"carve"
			intensity = carve_amount * clampf(speed_mps / 18.0, 0.25, 1.4)
		if not spray_kind.is_empty():
			_spray_cooldown = 0.08
			snow_spray_requested.emit(
				spray_kind,
				intensity * ground_probe.spray_multiplier,
				spray_origin.global_position,
				ground_probe.ground_normal
			)
	score_manager.physics_tick(
		delta,
		speed_mps,
		carve_amount,
		brake_input,
		ground_probe.surface_key,
		ground_probe.powder_factor
	)


func _surface_friction() -> float:
	match ground_probe.surface_key:
		&"powder", &"fresh_powder":
			return tuning.powder_friction
		&"ice":
			return tuning.ice_friction
		_:
			return tuning.ground_friction


func _motion_forward(normal: Vector3) -> Vector3:
	var forward := (global_basis * Vector3.FORWARD).slide(normal)
	if forward.length_squared() < 0.001:
		forward = velocity.slide(normal)
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD.slide(normal)
	return forward.normalized()


func _align_body(forward: Vector3, normal: Vector3, delta: float) -> void:
	var safe_forward := forward.slide(normal).normalized()
	if safe_forward.length_squared() < 0.001:
		return
	var right := safe_forward.cross(normal).normalized()
	var target_basis := Basis(right, normal.normalized(), -safe_forward).orthonormalized()
	var weight := 1.0 - exp(-tuning.visual_alignment_speed * delta)
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(
		target_basis.get_rotation_quaternion(), weight
	)).orthonormalized()


func _update_grounded_visual(delta: float, speed_ratio: float) -> void:
	if trick_controller.is_airborne:
		return
	var lean_target := -steering_input * deg_to_rad(tuning.maximum_lean_degrees) * speed_ratio
	lean_visual.rotation.z = lerp_angle(
		lean_visual.rotation.z,
		lean_target,
		1.0 - exp(-9.0 * delta)
	)


func _change_state(next_state: int) -> void:
	if next_state == state:
		return
	var previous := state
	state = next_state
	_state_elapsed = 0.0
	state_changed.emit(previous, state)


func _on_surface_changed(new_surface: StringName) -> void:
	_last_surface_key = new_surface
	surface_changed.emit(new_surface)


func _on_trick_updated(snapshot: Dictionary) -> void:
	if state == SkiState.AIRBORNE:
		score_manager.preview_trick(snapshot)
