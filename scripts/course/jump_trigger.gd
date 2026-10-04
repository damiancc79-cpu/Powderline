class_name SkiJumpTrigger
extends Area3D

signal takeoff_reached(jump_id: StringName, launch_strength: float, is_large_jump: bool)

@export var jump_id: StringName = &"jump"
@export_range(0.1, 3.0, 0.05) var launch_strength: float = 1.0
@export var is_large_jump: bool = false

var _cooldown_bodies: Dictionary = {}


func _ready() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	for body_id: int in _cooldown_bodies.keys():
		var remaining: float = float(_cooldown_bodies[body_id]) - delta
		if remaining <= 0.0:
			_cooldown_bodies.erase(body_id)
		else:
			_cooldown_bodies[body_id] = remaining


func _on_body_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D or body.is_in_group(&"skier") or body.is_in_group(&"player")):
		return
	var body_id: int = body.get_instance_id()
	if _cooldown_bodies.has(body_id):
		return
	_cooldown_bodies[body_id] = 1.0
	takeoff_reached.emit(jump_id, launch_strength, is_large_jump)
