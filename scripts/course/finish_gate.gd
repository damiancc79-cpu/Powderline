class_name SkiFinishGate
extends Area3D

signal crossed

@export var finish_id: StringName = &"finish"
var _crossed: bool = false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)


func reset_gate() -> void:
	_crossed = false


func _on_body_entered(body: Node3D) -> void:
	if _crossed:
		return
	if body is CharacterBody3D or body.is_in_group(&"skier") or body.is_in_group(&"player"):
		_crossed = true
		crossed.emit()
