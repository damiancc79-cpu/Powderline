class_name SnowSurfaceProfile
extends Resource

@export var surface_id: int = 0
@export var display_name: StringName = &"Packed Snow"
@export_range(0.05, 3.0, 0.01) var friction_multiplier: float = 1.0
@export_range(0.05, 3.0, 0.01) var edge_grip_multiplier: float = 1.0
@export_range(0.0, 3.0, 0.01) var spray_multiplier: float = 1.0
@export_range(0.2, 2.0, 0.01) var speed_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.01) var powder_amount: float = 0.25
@export var can_be_tracked: bool = true
@export var debug_color: Color = Color(0.82, 0.9, 0.96, 1.0)


func as_gameplay_data(freshness: float = 1.0) -> Dictionary:
	return {
		"id": surface_id,
		"name": display_name,
		"friction_multiplier": friction_multiplier,
		"edge_grip_multiplier": edge_grip_multiplier,
		"spray_multiplier": spray_multiplier * lerpf(0.65, 1.0, freshness),
		"speed_multiplier": speed_multiplier,
		"powder_amount": powder_amount * freshness,
		"freshness": freshness,
		"untouched_powder": display_name == &"Fresh Powder" and freshness > 0.82,
	}
