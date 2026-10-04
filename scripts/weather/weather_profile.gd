class_name SkiWeatherProfile
extends Resource

@export var state_name: StringName = &"Clear"
@export_multiline var description: String = "Bright, calm mountain weather."
@export var sky_color: Color = Color(0.37, 0.62, 0.82, 1.0)
@export var horizon_color: Color = Color(0.73, 0.84, 0.91, 1.0)
@export var ambient_color: Color = Color(0.65, 0.76, 0.86, 1.0)
@export var sunlight_color: Color = Color(1.0, 0.93, 0.8, 1.0)
@export_range(0.0, 3.0, 0.01) var sunlight_energy: float = 1.25
@export_range(0.0, 0.15, 0.0005) var fog_density: float = 0.004
@export_range(20.0, 2000.0, 1.0) var visibility_distance: float = 900.0
@export_range(0.0, 1.0, 0.01) var snowfall_intensity: float = 0.0
@export_range(0.0, 2.0, 0.01) var accumulation_rate: float = 0.0
@export var wind_direction: Vector3 = Vector3(0.2, 0.0, -1.0)
@export_range(0.0, 30.0, 0.1) var wind_speed: float = 1.5
@export_range(0.8, 1.5, 0.01) var drag_multiplier: float = 1.0
@export_range(1.0, 2.0, 0.01) var score_multiplier: float = 1.0


func to_values() -> Dictionary:
	return {
		"state_name": state_name,
		"description": description,
		"sky_color": sky_color,
		"horizon_color": horizon_color,
		"ambient_color": ambient_color,
		"sunlight_color": sunlight_color,
		"sunlight_energy": sunlight_energy,
		"fog_density": fog_density,
		"visibility_distance": visibility_distance,
		"snowfall_intensity": snowfall_intensity,
		"accumulation_rate": accumulation_rate,
		"wind_direction": wind_direction.normalized(),
		"wind_speed": wind_speed,
		"drag_multiplier": drag_multiplier,
		"score_multiplier": score_multiplier,
	}
