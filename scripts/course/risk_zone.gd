class_name SkiRiskZone
extends Area3D

signal skier_entered(zone_id: StringName, multiplier: float, label: String)
signal skier_exited(zone_id: StringName, multiplier: float, label: String)

@export var zone_id: StringName = &"risk_zone"
@export var display_label: String = "Risk Line"
@export_range(1.0, 3.0, 0.05) var score_multiplier: float = 1.25
@export var entry_bonus: int = 0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if _is_skier(body):
		skier_entered.emit(zone_id, score_multiplier, display_label)


func _on_body_exited(body: Node3D) -> void:
	if _is_skier(body):
		skier_exited.emit(zone_id, score_multiplier, display_label)


func _is_skier(body: Node3D) -> bool:
	return body is CharacterBody3D or body.is_in_group(&"skier") or body.is_in_group(&"player")
