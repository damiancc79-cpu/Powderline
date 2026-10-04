class_name SkiCheckpoint
extends Area3D

signal activated(checkpoint_id: StringName, respawn_transform: Transform3D)

@export var checkpoint_id: StringName = &"checkpoint"
@export var respawn_transform: Transform3D = Transform3D.IDENTITY
@export var one_shot: bool = true

var _has_activated: bool = false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)


func reset_checkpoint() -> void:
	_has_activated = false


func _on_body_entered(body: Node3D) -> void:
	if one_shot and _has_activated:
		return
	if not _is_skier(body):
		return
	_has_activated = true
	activated.emit(checkpoint_id, respawn_transform)


func _is_skier(body: Node3D) -> bool:
	return body is CharacterBody3D or body.is_in_group(&"skier") or body.is_in_group(&"player")
