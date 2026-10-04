class_name TrickController
extends Node

## Reads only InputMap actions and turns simultaneous two-button combinations
## into a provisional airborne trick description. Scoring is deferred until the
## skier controller confirms the landing.

signal trick_started(display_name: String)
signal trick_updated(snapshot: Dictionary)
signal trick_milestone(label: String, degrees: int)
signal trick_resolved(snapshot: Dictionary, landed_successfully: bool)

@export var tuning: SkiTuning
@export var trick_visual: Node3D
@export var style_visual: Node3D

@export_category("Input actions")
@export var steer_left_action: StringName = &"steer_left"
@export var steer_right_action: StringName = &"steer_right"
@export var forward_action: StringName = &"move_forward"
@export var back_action: StringName = &"move_back"
@export var trick_one_action: StringName = &"trick_one"
@export var trick_two_action: StringName = &"trick_two"
@export var tuck_grab_action: StringName = &"tuck_grab"

var is_airborne: bool = false
var airtime: float = 0.0
var spin_degrees_signed: float = 0.0
var flip_degrees_signed: float = 0.0
var grab_time: float = 0.0
var did_grab: bool = false
var tweak_count: int = 0

var _buffer_remaining: float = 0.0
var _buffered_combinations: Dictionary = {}
var _last_snapshot: Dictionary = {}
var _last_display_name: String = ""
var _spin_milestone: int = 0
var _flip_milestone: int = 0
var _tweak_side: int = 0
var _ground_reset_active: bool = false


func _ready() -> void:
	if tuning == null:
		tuning = load("res://resources/tuning/default_ski_tuning.tres") as SkiTuning


func physics_tick(delta: float, airborne: bool, allow_input: bool = true) -> void:
	if not airborne:
		_capture_pre_takeoff_buffer(delta)
		_smooth_visual_reset(delta)
		return
	if not is_airborne:
		begin_airborne()
	airtime += delta
	_buffer_remaining = maxf(0.0, _buffer_remaining - delta)
	if allow_input:
		_apply_trick_inputs(delta)
	_update_snapshot()


func begin_airborne() -> void:
	is_airborne = true
	airtime = 0.0
	spin_degrees_signed = 0.0
	flip_degrees_signed = 0.0
	grab_time = 0.0
	did_grab = false
	tweak_count = 0
	_tweak_side = 0
	_last_snapshot.clear()
	_last_display_name = ""
	_spin_milestone = 0
	_flip_milestone = 0
	_ground_reset_active = false
	_buffer_remaining = tuning.trick_input_buffer
	_apply_buffered_combinations()
	_buffered_combinations.clear()


func resolve_airborne(landed_successfully: bool) -> Dictionary:
	if not is_airborne:
		return {}
	_update_snapshot()
	var result := _last_snapshot.duplicate(true)
	is_airborne = false
	_ground_reset_active = true
	_buffer_remaining = 0.0
	trick_resolved.emit(result, landed_successfully)
	return result


func cancel_airborne() -> Dictionary:
	return resolve_airborne(false)


func current_snapshot() -> Dictionary:
	if is_airborne:
		_update_snapshot()
	return _last_snapshot.duplicate(true)


func _capture_pre_takeoff_buffer(delta: float) -> void:
	if _any_combo_just_pressed():
		_buffer_remaining = tuning.trick_input_buffer
		_buffered_combinations = _read_combinations()
	elif _buffer_remaining > 0.0:
		_buffer_remaining = maxf(0.0, _buffer_remaining - delta)
		if _buffer_remaining <= 0.0:
			_buffered_combinations.clear()


func _apply_buffered_combinations() -> void:
	if _buffer_remaining <= 0.0 or _buffered_combinations.is_empty():
		return
	if bool(_buffered_combinations.get("grab", false)):
		did_grab = true
		grab_time = maxf(grab_time, tuning.grab_minimum_time)
	if bool(_buffered_combinations.get("tweak_left", false)):
		tweak_count += 1
		_tweak_side = -1
	elif bool(_buffered_combinations.get("tweak_right", false)):
		tweak_count += 1
		_tweak_side = 1


func _apply_trick_inputs(delta: float) -> void:
	var combinations := _read_combinations()
	var spin_direction := int(bool(combinations.get("spin_right", false))) \
		- int(bool(combinations.get("spin_left", false)))
	var flip_direction := int(bool(combinations.get("front_flip", false))) \
		- int(bool(combinations.get("back_flip", false)))
	var maximum_rate := deg_to_rad(tuning.maximum_trick_speed_degrees)
	var spin_rate := minf(deg_to_rad(tuning.spin_speed_degrees), maximum_rate)
	var flip_rate := minf(deg_to_rad(tuning.flip_speed_degrees), maximum_rate)

	if spin_direction != 0:
		var spin_step := spin_rate * float(spin_direction) * delta
		spin_degrees_signed += rad_to_deg(spin_step)
		if trick_visual != null:
			trick_visual.rotate_object_local(Vector3.UP, spin_step)
	if flip_direction != 0:
		# Positive X rotation reads as a front flip for the primitive skier.
		var flip_step := flip_rate * float(flip_direction) * delta
		flip_degrees_signed += rad_to_deg(flip_step)
		if trick_visual != null:
			trick_visual.rotate_object_local(Vector3.RIGHT, flip_step)

	if bool(combinations.get("grab", false)):
		grab_time += delta
		if grab_time >= tuning.grab_minimum_time:
			did_grab = true

	var requested_tweak := 0
	if bool(combinations.get("tweak_left", false)):
		requested_tweak = -1
	elif bool(combinations.get("tweak_right", false)):
		requested_tweak = 1
	if requested_tweak != 0 and requested_tweak != _tweak_side:
		tweak_count += 1
	_tweak_side = requested_tweak
	if style_visual != null:
		var tweak_target := deg_to_rad(tuning.tweak_angle_degrees) * float(_tweak_side)
		style_visual.rotation.z = lerp_angle(style_visual.rotation.z, tweak_target, 1.0 - exp(-12.0 * delta))


func _read_combinations() -> Dictionary:
	var q := Input.is_action_pressed(trick_one_action)
	var e := Input.is_action_pressed(trick_two_action)
	var shift := Input.is_action_pressed(tuck_grab_action)
	var left := Input.is_action_pressed(steer_left_action)
	var right := Input.is_action_pressed(steer_right_action)
	var forward := Input.is_action_pressed(forward_action)
	var back := Input.is_action_pressed(back_action)
	return {
		"spin_left": q and left,
		"spin_right": q and right,
		"front_flip": e and forward,
		"back_flip": e and back,
		"grab": q and e,
		"tweak_left": shift and left,
		"tweak_right": shift and right,
	}


func _any_combo_just_pressed() -> bool:
	var any_modifier := Input.is_action_pressed(trick_one_action) \
		or Input.is_action_pressed(trick_two_action) \
		or Input.is_action_pressed(tuck_grab_action)
	var any_direction := Input.is_action_pressed(steer_left_action) \
		or Input.is_action_pressed(steer_right_action) \
		or Input.is_action_pressed(forward_action) \
		or Input.is_action_pressed(back_action)
	return (any_modifier and any_direction) \
		or (Input.is_action_pressed(trick_one_action) and Input.is_action_pressed(trick_two_action))


func _update_snapshot() -> void:
	var absolute_spin := absf(spin_degrees_signed)
	var absolute_flip := absf(flip_degrees_signed)
	var spin_steps := clampi(int(floor((absolute_spin + 28.0) / 180.0)), 0, 8)
	var flip_count := clampi(int(floor((absolute_flip + 55.0) / 360.0)), 0, 4)
	var recognized_spin := spin_steps * 180
	var recognized_flip := flip_count * 360
	var has_trick := spin_steps > 0 or flip_count > 0 or did_grab or tweak_count > 0
	var components: Array[String] = []
	if spin_steps > 0:
		components.append("%d Spin %s" % [recognized_spin, "Right" if spin_degrees_signed > 0.0 else "Left"])
	if flip_count > 0:
		var direction_name := "Front Flip" if flip_degrees_signed > 0.0 else "Backflip"
		components.append(direction_name if flip_count == 1 else "%dx %s" % [flip_count, direction_name])
	if did_grab:
		components.append("Grab")
	if tweak_count > 0:
		components.append("Tweak")
	var display_name := " + ".join(components) if not components.is_empty() else "Air"
	var trick_key := StringName("spin_%d_%d|flip_%d_%d|grab_%d|tweak_%d" % [
		recognized_spin,
		signf(spin_degrees_signed),
		recognized_flip,
		signf(flip_degrees_signed),
		int(did_grab),
		mini(tweak_count, 1),
	])
	_last_snapshot = {
		"has_trick": has_trick,
		"display_name": display_name,
		"trick_key": trick_key,
		"spin_degrees": recognized_spin,
		"spin_raw_degrees": spin_degrees_signed,
		"flip_degrees": recognized_flip,
		"flip_raw_degrees": flip_degrees_signed,
		"did_grab": did_grab,
		"grab_time": grab_time,
		"tweak_count": tweak_count,
		"airtime": airtime,
	}
	if has_trick and _last_display_name.is_empty():
		trick_started.emit(display_name)
	_last_display_name = display_name if has_trick else ""
	_emit_milestones(spin_steps, flip_count)
	trick_updated.emit(_last_snapshot.duplicate(true))


func _emit_milestones(spin_steps: int, flip_count: int) -> void:
	if spin_steps > _spin_milestone:
		_spin_milestone = spin_steps
		trick_milestone.emit("%d spin" % (spin_steps * 180), spin_steps * 180)
	if flip_count > _flip_milestone:
		_flip_milestone = flip_count
		trick_milestone.emit("Flip", flip_count * 360)


func _smooth_visual_reset(delta: float) -> void:
	if not _ground_reset_active:
		return
	var weight := 1.0 - exp(-10.0 * delta)
	if trick_visual != null:
		var current_quaternion := trick_visual.quaternion
		trick_visual.quaternion = current_quaternion.slerp(Quaternion.IDENTITY, weight).normalized()
	if style_visual != null:
		style_visual.rotation.z = lerp_angle(style_visual.rotation.z, 0.0, weight)
	var trick_done := trick_visual == null or trick_visual.quaternion.angle_to(Quaternion.IDENTITY) < 0.01
	var style_done := style_visual == null or absf(style_visual.rotation.z) < 0.01
	if trick_done and style_done:
		if trick_visual != null:
			trick_visual.quaternion = Quaternion.IDENTITY
		if style_visual != null:
			style_visual.rotation.z = 0.0
		_ground_reset_active = false
