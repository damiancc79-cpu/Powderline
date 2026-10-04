class_name SkiWeatherManager
extends Node3D

signal weather_changed(state_name: StringName, state_index: int)
signal weather_blend_updated(gameplay_values: Dictionary)
signal accumulation_tick(accumulation_rate: float, elapsed: float)

const PROFILE_PATHS: Array[String] = [
	"res://resources/weather/clear.tres",
	"res://resources/weather/light_snow.tres",
	"res://resources/weather/heavy_snow.tres",
	"res://resources/weather/whiteout.tres",
]

@export_range(1.0, 30.0, 0.1) var transition_duration: float = 8.0
@export_range(0.1, 2.0, 0.05) var accumulation_interval: float = 0.75
@export var start_weather_index: int = 0
@export var debug_cycle_enabled: bool = true

var current_index: int = 0
var target_index: int = 0
var _profiles: Array[SkiWeatherProfile] = []
var _source_values: Dictionary = {}
var _current_values: Dictionary = {}
var _target_values: Dictionary = {}
var _transition_progress: float = 1.0
var _accumulation_clock: float = 0.0
var _broadcast_clock: float = 0.0
var _follow_target: Node3D

var _world_environment: WorldEnvironment
var _environment: Environment
var _sun: DirectionalLight3D
var _snow_particles: GPUParticles3D
var _gust_particles: GPUParticles3D


func _ready() -> void:
	_load_profiles()
	_build_environment_nodes()
	if _profiles.is_empty():
		push_warning("Weather manager has no weather profile resources.")
		return
	current_index = clampi(start_weather_index, 0, _profiles.size() - 1)
	target_index = current_index
	_current_values = _profiles[current_index].to_values()
	_source_values = _current_values.duplicate(true)
	_target_values = _current_values.duplicate(true)
	_apply_visuals(_current_values)
	weather_changed.emit(_profiles[current_index].state_name, current_index)


func _process(delta: float) -> void:
	if _profiles.is_empty():
		return
	if _transition_progress < 1.0:
		_transition_progress = minf(1.0, _transition_progress + delta / transition_duration)
		var eased: float = smoothstep(0.0, 1.0, _transition_progress)
		_current_values = _blend_values(_source_values, _target_values, eased)
		if is_equal_approx(_transition_progress, 1.0):
			current_index = target_index
	_apply_visuals(_current_values)
	_update_particle_follow()

	_accumulation_clock += delta
	if _accumulation_clock >= accumulation_interval:
		var elapsed: float = _accumulation_clock
		_accumulation_clock = 0.0
		accumulation_tick.emit(float(_current_values.get("accumulation_rate", 0.0)), elapsed)

	_broadcast_clock += delta
	if _broadcast_clock >= 0.2:
		_broadcast_clock = 0.0
		weather_blend_updated.emit(get_gameplay_modifiers())


func _unhandled_input(event: InputEvent) -> void:
	if debug_cycle_enabled and event.is_action_pressed(&"cycle_weather"):
		cycle_weather()
		get_viewport().set_input_as_handled()


func cycle_weather() -> void:
	if _profiles.is_empty():
		return
	set_weather_index((target_index + 1) % _profiles.size())


func set_weather_index(index: int, immediate: bool = false) -> void:
	if _profiles.is_empty():
		return
	var next_index: int = posmod(index, _profiles.size())
	if next_index == target_index and not immediate:
		return
	target_index = next_index
	_source_values = _current_values.duplicate(true)
	_target_values = _profiles[target_index].to_values()
	_transition_progress = 1.0 if immediate else 0.0
	if immediate:
		_current_values = _target_values.duplicate(true)
		current_index = target_index
		_apply_visuals(_current_values)
	weather_changed.emit(_profiles[target_index].state_name, target_index)


func set_weather_by_name(state_name: StringName, immediate: bool = false) -> bool:
	for index: int in range(_profiles.size()):
		if _profiles[index].state_name == state_name:
			set_weather_index(index, immediate)
			return true
	return false


func set_follow_target(target: Node3D) -> void:
	_follow_target = target


func get_weather_name() -> StringName:
	if _profiles.is_empty():
		return &"Unknown"
	return _profiles[target_index].state_name


func get_gameplay_modifiers() -> Dictionary:
	var direction: Vector3 = _current_values.get("wind_direction", Vector3.ZERO)
	var wind_speed: float = float(_current_values.get("wind_speed", 0.0))
	var snowfall: float = float(_current_values.get("snowfall_intensity", 0.0))
	return {
		"state_name": get_weather_name(),
		"drag_multiplier": float(_current_values.get("drag_multiplier", 1.0)),
		"score_multiplier": float(_current_values.get("score_multiplier", 1.0)),
		"visibility_distance": float(_current_values.get("visibility_distance", 900.0)),
		"snowfall_intensity": snowfall,
		"accumulation_rate": float(_current_values.get("accumulation_rate", 0.0)),
		"wind_vector": direction.normalized() * wind_speed,
		# Kept subtle: the player controller decides whether this is applied airborne.
		"airborne_force": direction.normalized() * wind_speed * 0.38,
		"transition_progress": _transition_progress,
	}


func get_profile_count() -> int:
	return _profiles.size()


func _load_profiles() -> void:
	_profiles.clear()
	for path: String in PROFILE_PATHS:
		if not ResourceLoader.exists(path):
			push_warning("Missing weather profile: %s" % path)
			continue
		var profile: SkiWeatherProfile = load(path) as SkiWeatherProfile
		if profile != null:
			_profiles.append(profile)


func _build_environment_nodes() -> void:
	_world_environment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _world_environment == null:
		_world_environment = WorldEnvironment.new()
		_world_environment.name = "WorldEnvironment"
		add_child(_world_environment)
	_environment = _world_environment.environment
	if _environment == null:
		_environment = Environment.new()
		_world_environment.environment = _environment
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.fog_enabled = true

	_sun = get_node_or_null("Sun") as DirectionalLight3D
	if _sun == null:
		_sun = DirectionalLight3D.new()
		_sun.name = "Sun"
		_sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
		_sun.shadow_enabled = true
		_sun.directional_shadow_max_distance = 220.0
		add_child(_sun)

	_snow_particles = _create_weather_particles("Snowfall", 900, false)
	_gust_particles = _create_weather_particles("GroundGusts", 180, true)


func _create_weather_particles(
	node_name: String,
	particle_count: int,
	is_gust: bool
) -> GPUParticles3D:
	var particles: GPUParticles3D = get_node_or_null(node_name) as GPUParticles3D
	if particles != null:
		return particles
	particles = GPUParticles3D.new()
	particles.name = node_name
	particles.amount = particle_count
	particles.lifetime = 3.4 if not is_gust else 1.8
	particles.preprocess = particles.lifetime
	particles.visibility_aabb = AABB(Vector3(-48.0, -32.0, -48.0), Vector3(96.0, 70.0, 96.0))
	particles.emitting = true
	particles.amount_ratio = 0.0
	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(38.0, 1.0 if not is_gust else 0.25, 42.0)
	process_material.direction = Vector3(0.15, -1.0 if not is_gust else 0.08, -0.2)
	process_material.spread = 18.0 if not is_gust else 8.0
	process_material.initial_velocity_min = 4.0 if not is_gust else 8.0
	process_material.initial_velocity_max = 8.0 if not is_gust else 14.0
	process_material.gravity = Vector3(0.0, -2.5 if not is_gust else -0.2, 0.0)
	process_material.scale_min = 0.035 if not is_gust else 0.08
	process_material.scale_max = 0.10 if not is_gust else 0.18
	particles.process_material = process_material
	var flake: QuadMesh = QuadMesh.new()
	flake.size = Vector2(0.12, 0.12) if not is_gust else Vector2(0.38, 0.06)
	flake.orientation = PlaneMesh.FACE_Z
	var flake_material: StandardMaterial3D = StandardMaterial3D.new()
	flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake_material.albedo_color = Color(0.94, 0.98, 1.0, 0.78 if not is_gust else 0.4)
	flake_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.material = flake_material
	particles.draw_pass_1 = flake
	add_child(particles)
	return particles


func _blend_values(from: Dictionary, to: Dictionary, weight: float) -> Dictionary:
	var from_wind: Vector3 = from.get("wind_direction", Vector3.ZERO)
	var to_wind: Vector3 = to.get("wind_direction", Vector3.ZERO)
	return {
		"state_name": to.get("state_name", &"Unknown"),
		"description": to.get("description", ""),
		"sky_color": (from.get("sky_color", Color.BLACK) as Color).lerp(
			to.get("sky_color", Color.BLACK), weight
		),
		"horizon_color": (from.get("horizon_color", Color.BLACK) as Color).lerp(
			to.get("horizon_color", Color.BLACK), weight
		),
		"ambient_color": (from.get("ambient_color", Color.WHITE) as Color).lerp(
			to.get("ambient_color", Color.WHITE), weight
		),
		"sunlight_color": (from.get("sunlight_color", Color.WHITE) as Color).lerp(
			to.get("sunlight_color", Color.WHITE), weight
		),
		"sunlight_energy": lerpf(from.get("sunlight_energy", 1.0), to.get("sunlight_energy", 1.0), weight),
		"fog_density": lerpf(from.get("fog_density", 0.0), to.get("fog_density", 0.0), weight),
		"visibility_distance": lerpf(from.get("visibility_distance", 900.0), to.get("visibility_distance", 900.0), weight),
		"snowfall_intensity": lerpf(from.get("snowfall_intensity", 0.0), to.get("snowfall_intensity", 0.0), weight),
		"accumulation_rate": lerpf(from.get("accumulation_rate", 0.0), to.get("accumulation_rate", 0.0), weight),
		"wind_direction": from_wind.slerp(to_wind, weight).normalized(),
		"wind_speed": lerpf(from.get("wind_speed", 0.0), to.get("wind_speed", 0.0), weight),
		"drag_multiplier": lerpf(from.get("drag_multiplier", 1.0), to.get("drag_multiplier", 1.0), weight),
		"score_multiplier": lerpf(from.get("score_multiplier", 1.0), to.get("score_multiplier", 1.0), weight),
	}


func _apply_visuals(values: Dictionary) -> void:
	if _environment == null:
		return
	var sky: Color = values.get("sky_color", Color(0.4, 0.6, 0.8))
	var horizon: Color = values.get("horizon_color", sky)
	_environment.background_color = sky.lerp(horizon, 0.38)
	_environment.ambient_light_color = values.get("ambient_color", Color.WHITE)
	_environment.ambient_light_energy = lerpf(0.72, 0.42, float(values.get("snowfall_intensity", 0.0)))
	_environment.fog_light_color = horizon
	_environment.fog_density = float(values.get("fog_density", 0.0))
	_environment.fog_sky_affect = 0.72
	_sun.light_color = values.get("sunlight_color", Color.WHITE)
	_sun.light_energy = float(values.get("sunlight_energy", 1.0))
	var snowfall: float = float(values.get("snowfall_intensity", 0.0))
	_snow_particles.amount_ratio = clampf(snowfall, 0.0, 1.0)
	_gust_particles.amount_ratio = clampf(
		snowfall * float(values.get("wind_speed", 0.0)) / 18.0,
		0.0,
		1.0
	)
	var wind: Vector3 = values.get("wind_direction", Vector3.ZERO)
	var snow_material: ParticleProcessMaterial = _snow_particles.process_material as ParticleProcessMaterial
	var gust_material: ParticleProcessMaterial = _gust_particles.process_material as ParticleProcessMaterial
	if snow_material != null:
		snow_material.direction = Vector3(wind.x * 0.75, -1.0, wind.z * 0.75).normalized()
	if gust_material != null:
		gust_material.direction = Vector3(wind.x, 0.08, wind.z).normalized()


func _update_particle_follow() -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		return
	var target_position: Vector3 = _follow_target.global_position
	_snow_particles.global_position = target_position + Vector3(0.0, 22.0, -7.0)
	_gust_particles.global_position = target_position + Vector3(0.0, -0.2, -10.0)
