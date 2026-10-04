class_name CrashController
extends Node

## Converts landing classifications and obstacle impacts into a single crash
## request. It intentionally never performs a grounded check.

signal crash_requested(reason: StringName, impact_speed: float)

@export var tuning: SkiTuning
@export_range(0.0, 1.0, 0.01) var wall_normal_maximum_up_dot: float = 0.55
@export_range(0.0, 1.0, 0.01) var duplicate_impact_cooldown: float = 0.25

var _cooldown_remaining: float = 0.0


func _ready() -> void:
	if tuning == null:
		tuning = load("res://resources/tuning/default_ski_tuning.tres") as SkiTuning


func tick(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)


func assess_landing(landing_data: Dictionary) -> bool:
	if bool(landing_data.get("success", false)):
		return false
	request_crash(
		StringName(landing_data.get("reason", &"failed_landing")),
		float(landing_data.get("impact_speed", 0.0))
	)
	return true


func assess_motion_collisions(body: CharacterBody3D, pre_move_velocity: Vector3) -> bool:
	if _cooldown_remaining > 0.0:
		return false
	var strongest_impact := 0.0
	for index: int in range(body.get_slide_collision_count()):
		var collision := body.get_slide_collision(index)
		var normal := collision.get_normal().normalized()
		if normal.dot(Vector3.UP) > wall_normal_maximum_up_dot:
			continue
		strongest_impact = maxf(strongest_impact, absf(pre_move_velocity.dot(normal)))
	if strongest_impact >= tuning.obstacle_crash_speed:
		request_crash(&"obstacle_impact", strongest_impact)
		return true
	return false


func request_crash(reason: StringName, impact_speed: float) -> void:
	if _cooldown_remaining > 0.0:
		return
	_cooldown_remaining = duplicate_impact_cooldown
	crash_requested.emit(reason, impact_speed)


func reset() -> void:
	_cooldown_remaining = 0.0
