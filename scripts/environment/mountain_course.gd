class_name PowderlineMountainCourse
extends Node3D

signal checkpoint_reached(checkpoint_id: StringName, respawn_transform: Transform3D)
signal finish_reached
signal risk_zone_changed(zone_id: StringName, entered: bool, multiplier: float, label: String)
signal jump_takeoff_reached(jump_id: StringName, strength: float, is_large_jump: bool)
signal course_event(event_name: StringName, payload: Dictionary)

const KENNEY_MODEL_ROOT: String = "res://assets/external/kenney_nature_kit/models/"
const COURSE_LENGTH: float = 1120.0

@export var build_decorations: bool = true
@export var build_obstacle_collisions: bool = true
@export var integrate_external_models: bool = true

@onready var terrain: ProceduralSkiTerrain = $Terrain
@onready var surface_grid: SnowSurfaceGrid = $Terrain/SnowSurfaceGrid
@onready var weather_manager: SkiWeatherManager = $WeatherManager
@onready var trail_renderer: SkiTrailRenderer = $SkiTrailRenderer
@onready var snow_spray: SnowSprayEmitter = $SnowSprayEmitter
@onready var spawn_point: Marker3D = $SpawnPoint
@onready var decoration_root: Node3D = $Decorations
@onready var geometry_root: Node3D = $CourseGeometry
@onready var trigger_root: Node3D = $Triggers

var _registered_player: Node3D
var _materials: Dictionary = {}
var _finish_gate: SkiFinishGate
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _active_risks: Dictionary = {}


func _ready() -> void:
	add_to_group(&"course_environment")
	_rng.seed = 0x504F57444552
	_create_materials()
	_position_spawn()
	_build_start_platform()
	_build_checkpoints_and_finish()
	_build_risk_zones()
	_build_jump_line()
	if build_decorations:
		_build_route_markers()
		_build_tree_fields()
		_build_rock_fields()
		_build_course_signs()
	weather_manager.accumulation_tick.connect(_on_weather_accumulation)
	weather_manager.weather_blend_updated.connect(_on_weather_blend_for_player)
	checkpoint_reached.connect(_on_course_checkpoint_for_player)
	finish_reached.connect(_on_course_finish_for_player)


func register_player(player: Node3D) -> void:
	if _registered_player != null and is_instance_valid(_registered_player):
		_disconnect_player_feedback(_registered_player)
	_registered_player = player
	trail_renderer.set_target(player, terrain)
	weather_manager.set_follow_target(player)
	if player.has_signal(&"snow_spray_requested"):
		var spray_callable: Callable = Callable(self, "_on_player_snow_spray")
		if not player.is_connected(&"snow_spray_requested", spray_callable):
			player.connect(&"snow_spray_requested", spray_callable)
	if player.has_method("set_course_environment"):
		player.call("set_course_environment", self)
	_on_weather_blend_for_player(weather_manager.get_gameplay_modifiers())


func unregister_player(player: Node3D) -> void:
	if _registered_player != player:
		return
	_disconnect_player_feedback(player)
	_registered_player = null
	trail_renderer.set_target(null, terrain)
	weather_manager.set_follow_target(null)


func get_spawn_transform() -> Transform3D:
	return spawn_point.global_transform


func get_surface_sample(global_position: Vector3) -> Dictionary:
	return terrain.get_snow_surface_sample(global_position)


func get_snow_surface_sample(global_position: Vector3) -> Dictionary:
	return terrain.get_snow_surface_sample(global_position)


func mark_surface_tracked(global_position: Vector3, strength: float = 1.0) -> void:
	terrain.mark_surface_tracked(global_position, strength)


func emit_snow_spray(
	global_position: Vector3,
	ground_normal: Vector3,
	motion_direction: Vector3,
	intensity: float = 1.0,
	kind: StringName = &"carve"
) -> void:
	var surface: Dictionary = get_surface_sample(global_position)
	var adjusted_intensity: float = intensity * float(surface.get("spray_multiplier", 1.0))
	snow_spray.emit_spray(
		global_position,
		ground_normal,
		motion_direction,
		adjusted_intensity,
		kind
	)


func get_weather_manager() -> SkiWeatherManager:
	return weather_manager


func get_weather_modifiers() -> Dictionary:
	return weather_manager.get_gameplay_modifiers()


func cycle_weather() -> void:
	weather_manager.cycle_weather()


func set_weather(state_name: StringName, immediate: bool = false) -> bool:
	return weather_manager.set_weather_by_name(state_name, immediate)


func get_course_progress(global_position: Vector3) -> float:
	var local_position: Vector3 = to_local(global_position)
	return clampf(-local_position.z / COURSE_LENGTH, 0.0, 1.0)


func get_course_layout() -> Dictionary:
	return {
		"length_m": COURSE_LENGTH,
		"expected_run_seconds": Vector2(90.0, 180.0),
		"sections": [
			{"name": &"Beginner Bowl", "range": Vector2(0.0, 0.14)},
			{"name": &"Pine Slalom", "range": Vector2(0.14, 0.30)},
			{"name": &"Granite Chute", "range": Vector2(0.30, 0.47)},
			{"name": &"Powder Meadows", "range": Vector2(0.47, 0.70)},
			{"name": &"Wind Ridge", "range": Vector2(0.70, 0.84)},
			{"name": &"Final Drop", "range": Vector2(0.84, 1.0)},
		],
		"jump_count": 4,
		"checkpoint_count": 4,
	}


func reset_course_state(clear_tracks: bool = true) -> void:
	_active_risks.clear()
	for child: Node in trigger_root.get_children():
		if child is SkiCheckpoint:
			(child as SkiCheckpoint).reset_checkpoint()
	if _finish_gate != null:
		_finish_gate.reset_gate()
	if clear_tracks:
		trail_renderer.clear_trails()
		surface_grid.reset_to_fresh()


func _position_spawn() -> void:
	var spawn_position: Vector3 = Vector3(0.0, 0.0, -8.0)
	spawn_position.y = terrain.height_at_local(spawn_position.x, spawn_position.z) + 1.35
	spawn_point.position = spawn_position
	spawn_point.rotation = Vector3.ZERO


func _create_materials() -> void:
	_materials[&"wood"] = _standard_material(Color(0.19, 0.10, 0.055), 0.9)
	_materials[&"pine"] = _standard_material(Color(0.055, 0.24, 0.17), 0.92)
	_materials[&"pine_light"] = _standard_material(Color(0.09, 0.34, 0.22), 0.9)
	_materials[&"rock"] = _standard_material(Color(0.22, 0.27, 0.29), 0.96)
	_materials[&"ice"] = _standard_material(Color(0.2, 0.68, 0.9, 0.84), 0.15, true)
	_materials[&"safe"] = _standard_material(Color(0.07, 0.56, 0.82), 0.6)
	_materials[&"risk"] = _standard_material(Color(1.0, 0.31, 0.08), 0.48)
	_materials[&"checkpoint"] = _standard_material(Color(0.14, 0.86, 0.58), 0.55)
	_materials[&"finish"] = _standard_material(Color(0.92, 0.1, 0.14), 0.55)
	_materials[&"ramp"] = _standard_material(Color(0.66, 0.86, 0.94), 0.7)
	_materials[&"platform"] = _standard_material(Color(0.48, 0.68, 0.78), 0.78)


func _standard_material(
	color: Color,
	roughness: float,
	transparent: bool = false
) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _build_start_platform() -> void:
	var platform: StaticBody3D = StaticBody3D.new()
	platform.name = "StartPlatform"
	platform.collision_layer = 1
	platform.collision_mask = 0
	var size: Vector3 = Vector3(18.0, 0.5, 12.0)
	var position_3d: Vector3 = Vector3(0.0, terrain.height_at_local(0.0, -2.0) + 0.18, -2.0)
	platform.position = position_3d
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = _materials[&"platform"]
	mesh_instance.mesh = box_mesh
	platform.add_child(mesh_instance)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	platform.add_child(collision)
	geometry_root.add_child(platform)
	_create_gate_visual(Vector3(0.0, position_3d.y + 0.25, -8.0), 9.0, _materials[&"checkpoint"], "START")


func _build_checkpoints_and_finish() -> void:
	var checkpoint_specs: Array[Dictionary] = [
		{"id": &"pine_exit", "z": -235.0, "x": 4.0, "label": "PINE EXIT"},
		{"id": &"chute_exit", "z": -485.0, "x": 24.0, "label": "CHUTE EXIT"},
		{"id": &"meadow_exit", "z": -748.0, "x": 8.0, "label": "MEADOW EXIT"},
		{"id": &"final_drop", "z": -962.0, "x": 0.0, "label": "FINAL DROP"},
	]
	for spec: Dictionary in checkpoint_specs:
		_create_checkpoint(spec)

	var finish_z: float = -1084.0
	var finish_y: float = terrain.height_at_local(0.0, finish_z)
	_finish_gate = SkiFinishGate.new()
	_finish_gate.name = "FinishGate"
	_finish_gate.position = Vector3(0.0, finish_y + 5.0, finish_z)
	var finish_collision: CollisionShape3D = CollisionShape3D.new()
	var finish_shape: BoxShape3D = BoxShape3D.new()
	finish_shape.size = Vector3(92.0, 12.0, 6.0)
	finish_collision.shape = finish_shape
	_finish_gate.add_child(finish_collision)
	_finish_gate.crossed.connect(_on_finish_crossed)
	trigger_root.add_child(_finish_gate)
	_create_gate_visual(Vector3(0.0, finish_y, finish_z), 18.0, _materials[&"finish"], "FINISH")


func _create_checkpoint(spec: Dictionary) -> void:
	var checkpoint_x: float = float(spec["x"])
	var checkpoint_z: float = float(spec["z"])
	var terrain_height: float = terrain.height_at_local(checkpoint_x, checkpoint_z)
	var checkpoint: SkiCheckpoint = SkiCheckpoint.new()
	checkpoint.name = String(spec["id"]).to_pascal_case()
	checkpoint.checkpoint_id = spec["id"]
	checkpoint.position = Vector3(0.0, terrain_height + 5.0, checkpoint_z)
	checkpoint.respawn_transform = Transform3D(
		Basis.IDENTITY,
		to_global(Vector3(checkpoint_x, terrain_height + 1.4, checkpoint_z - 7.0))
	)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(208.0, 14.0, 7.0)
	collision.shape = shape
	checkpoint.add_child(collision)
	checkpoint.activated.connect(_on_checkpoint_activated)
	trigger_root.add_child(checkpoint)
	_create_gate_visual(
		Vector3(checkpoint_x, terrain_height, checkpoint_z),
		11.0,
		_materials[&"checkpoint"],
		String(spec["label"])
	)


func _build_risk_zones() -> void:
	_create_risk_zone(
		&"blue_ice_shortcut", "BLUE ICE SHORTCUT", 1.35,
		Vector3(-28.0, terrain.height_at_local(-28.0, -430.0), -430.0),
		Vector3(19.0, 58.0, 178.0)
	)
	_create_risk_zone(
		&"granite_chute", "GRANITE NEEDLE", 1.25,
		Vector3(3.0, terrain.height_at_local(3.0, -404.0), -404.0),
		Vector3(25.0, 54.0, 116.0)
	)
	_create_risk_zone(
		&"wind_ridge", "WIND RIDGE", 1.5,
		Vector3(-42.0, terrain.height_at_local(-42.0, -850.0), -850.0),
		Vector3(14.0, 66.0, 142.0)
	)
	_create_risk_zone(
		&"big_air", "SUMMIT KICKER", 1.45,
		Vector3(0.0, terrain.height_at_local(0.0, -938.0), -938.0),
		Vector3(32.0, 50.0, 68.0)
	)


func _create_risk_zone(
	zone_id: StringName,
	label: String,
	multiplier: float,
	center: Vector3,
	size: Vector3
) -> void:
	var zone: SkiRiskZone = SkiRiskZone.new()
	zone.name = String(zone_id).to_pascal_case()
	zone.zone_id = zone_id
	zone.display_label = label
	zone.score_multiplier = multiplier
	zone.position = center + Vector3.UP * (size.y * 0.15)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	zone.add_child(collision)
	zone.skier_entered.connect(_on_risk_zone_entered)
	zone.skier_exited.connect(_on_risk_zone_exited)
	trigger_root.add_child(zone)


func _build_jump_line() -> void:
	_create_jump(&"meadow_one", Vector3(-28.0, 0.0, -565.0), 10.0, 11.0, 11.0, 0.9, false)
	_create_jump(&"meadow_two", Vector3(2.0, 0.0, -650.0), 12.0, 12.0, 13.5, 1.05, false)
	_create_jump(&"ridge_pop", Vector3(31.0, 0.0, -744.0), 11.0, 11.0, 15.0, 1.15, false)
	_create_jump(&"summit_kicker", Vector3(0.0, 0.0, -925.0), 25.0, 25.0, 18.5, 1.75, true)


func _create_jump(
	jump_id: StringName,
	center: Vector3,
	width: float,
	length: float,
	angle_degrees: float,
	launch_strength: float,
	is_large: bool
) -> void:
	var thickness: float = 0.65 if not is_large else 1.05
	var angle: float = deg_to_rad(angle_degrees)
	var back_z: float = center.z + length * 0.5
	var back_height: float = terrain.height_at_local(center.x, back_z)
	var back_local_y: float = cos(angle) * thickness * 0.5 - sin(angle) * length * 0.5
	center.y = back_height + 0.08 - back_local_y
	var ramp: StaticBody3D = StaticBody3D.new()
	ramp.name = String(jump_id).to_pascal_case() + "Ramp"
	ramp.collision_layer = 1
	ramp.collision_mask = 0
	ramp.position = center
	ramp.rotation.x = angle
	var size: Vector3 = Vector3(width, thickness, length)
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var ramp_mesh: BoxMesh = BoxMesh.new()
	ramp_mesh.size = size
	ramp_mesh.material = _materials[&"ramp"]
	mesh_instance.mesh = ramp_mesh
	ramp.add_child(mesh_instance)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	ramp.add_child(collision)
	geometry_root.add_child(ramp)

	var lip_position: Vector3 = center + Vector3(
		0.0,
		cos(angle) * thickness * 0.5 + sin(angle) * length * 0.5,
		-length * 0.5
	)
	var trigger: SkiJumpTrigger = SkiJumpTrigger.new()
	trigger.name = String(jump_id).to_pascal_case() + "Takeoff"
	trigger.jump_id = jump_id
	trigger.launch_strength = launch_strength
	trigger.is_large_jump = is_large
	trigger.position = lip_position + Vector3(0.0, 1.2, -0.8)
	var trigger_collision: CollisionShape3D = CollisionShape3D.new()
	var trigger_shape: BoxShape3D = BoxShape3D.new()
	trigger_shape.size = Vector3(width * 0.94, 3.2, 2.4)
	trigger_collision.shape = trigger_shape
	trigger.add_child(trigger_collision)
	trigger.takeoff_reached.connect(_on_jump_takeoff)
	trigger_root.add_child(trigger)
	_create_gate_visual(
		Vector3(center.x, back_height, back_z + 5.0),
		width * 0.72,
		_materials[&"risk"] if is_large else _materials[&"safe"],
		"BIG AIR" if is_large else "JUMP"
	)


func _build_route_markers() -> void:
	# Safe blue flags curve right around the rock chute.
	for index: int in range(12):
		var t: float = float(index) / 11.0
		var z_position: float = lerpf(-324.0, -492.0, t)
		var x_position: float = 32.0 + sin(t * PI) * 12.0
		_create_flag(Vector3(x_position, 0.0, z_position), _materials[&"safe"], "SafeMarker%02d" % index)
	# Orange markers trace the narrow, low-grip ice line.
	for index: int in range(13):
		var t: float = float(index) / 12.0
		var z_position: float = lerpf(-338.0, -512.0, t)
		var x_position: float = lerpf(-38.0, -18.0, t)
		_create_flag(Vector3(x_position, 0.0, z_position), _materials[&"risk"], "IceMarker%02d" % index)
	# Late ridge split: blue stays in the bowl, orange commits left.
	for index: int in range(10):
		var t: float = float(index) / 9.0
		var z_position: float = lerpf(-790.0, -914.0, t)
		_create_flag(Vector3(27.0 + sin(t * 4.0) * 7.0, 0.0, z_position), _materials[&"safe"], "Bowl%02d" % index)
		_create_flag(Vector3(-42.0 + sin(t * 5.0) * 2.5, 0.0, z_position), _materials[&"risk"], "Ridge%02d" % index)


func _create_flag(position_3d: Vector3, material: Material, node_name: String) -> void:
	position_3d.y = terrain.height_at_local(position_3d.x, position_3d.z)
	var flag_root: Node3D = Node3D.new()
	flag_root.name = node_name
	flag_root.position = position_3d
	decoration_root.add_child(flag_root)
	var pole: CylinderMesh = CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.045
	pole.height = 2.1
	pole.radial_segments = 6
	pole.material = _materials[&"wood"]
	var pole_instance: MeshInstance3D = MeshInstance3D.new()
	pole_instance.mesh = pole
	pole_instance.position.y = 1.05
	flag_root.add_child(pole_instance)
	var cloth: BoxMesh = BoxMesh.new()
	cloth.size = Vector3(0.65, 0.42, 0.035)
	cloth.material = material
	var cloth_instance: MeshInstance3D = MeshInstance3D.new()
	cloth_instance.mesh = cloth
	cloth_instance.position = Vector3(0.32, 1.7, 0.0)
	flag_root.add_child(cloth_instance)


func _build_tree_fields() -> void:
	var tree_positions: Array[Vector3] = []
	# Forest walls provide strong peripheral speed cues while keeping a broad runout.
	for z_position: float in range(-80, -1060, -18):
		for side: float in [-1.0, 1.0]:
			var x_position: float = side * _rng.randf_range(72.0, 110.0)
			tree_positions.append(Vector3(x_position, 0.0, z_position + _rng.randf_range(-6.0, 6.0)))
	# Alternating tree islands make the dedicated slalom readable at speed.
	var slalom_index: int = 0
	for z_position: float in range(-160, -340, -15):
		var path_center: float = sin(float(slalom_index) * 0.82) * 19.0
		for side: float in [-1.0, 1.0]:
			var clearance: float = _rng.randf_range(11.0, 20.0)
			var position_3d: Vector3 = Vector3(
				path_center + side * clearance,
				0.0,
				z_position + _rng.randf_range(-2.4, 2.4)
			)
			tree_positions.append(position_3d)
			if build_obstacle_collisions and slalom_index % 2 == 0:
				_add_tree_collision(position_3d, "SlalomTree%02d_%d" % [slalom_index, int(side)])
		slalom_index += 1
	# Sparse powder trees enable deliberate near-misses without hiding the jumps.
	for index: int in range(34):
		var z_position: float = _rng.randf_range(-760.0, -525.0)
		var x_position: float = _rng.randf_range(-68.0, 68.0)
		if absf(x_position) < 16.0 or Vector2(x_position + 28.0, z_position + 565.0).length() < 15.0:
			continue
		tree_positions.append(Vector3(x_position, 0.0, z_position))
	_build_tree_multimeshes(tree_positions)
	if integrate_external_models:
		_place_kenney_hero_trees()


func _build_tree_multimeshes(tree_positions: Array[Vector3]) -> void:
	var trunk_mesh: CylinderMesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.13
	trunk_mesh.bottom_radius = 0.19
	trunk_mesh.height = 2.8
	trunk_mesh.radial_segments = 7
	trunk_mesh.material = _materials[&"wood"]
	var crown_mesh: CylinderMesh = CylinderMesh.new()
	crown_mesh.top_radius = 0.08
	crown_mesh.bottom_radius = 1.25
	crown_mesh.height = 5.4
	crown_mesh.radial_segments = 8
	crown_mesh.material = _materials[&"pine"]
	var upper_mesh: CylinderMesh = CylinderMesh.new()
	upper_mesh.top_radius = 0.05
	upper_mesh.bottom_radius = 0.82
	upper_mesh.height = 3.8
	upper_mesh.radial_segments = 8
	upper_mesh.material = _materials[&"pine_light"]
	var trunk_multimesh: MultiMesh = _new_multimesh(trunk_mesh, tree_positions.size())
	var crown_multimesh: MultiMesh = _new_multimesh(crown_mesh, tree_positions.size())
	var upper_multimesh: MultiMesh = _new_multimesh(upper_mesh, tree_positions.size())
	for index: int in range(tree_positions.size()):
		var position_3d: Vector3 = tree_positions[index]
		position_3d.y = terrain.height_at_local(position_3d.x, position_3d.z)
		var scale_factor: float = _rng.randf_range(0.78, 1.28)
		var yaw: float = _rng.randf_range(-PI, PI)
		var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(scale_factor, scale_factor, scale_factor))
		trunk_multimesh.set_instance_transform(
			index, Transform3D(basis, position_3d + Vector3.UP * 1.35 * scale_factor)
		)
		crown_multimesh.set_instance_transform(
			index, Transform3D(basis, position_3d + Vector3.UP * 4.05 * scale_factor)
		)
		upper_multimesh.set_instance_transform(
			index, Transform3D(basis, position_3d + Vector3.UP * 6.05 * scale_factor)
		)
	_add_multimesh_instance("TreeTrunks", trunk_multimesh)
	_add_multimesh_instance("TreeCrowns", crown_multimesh)
	_add_multimesh_instance("TreeTops", upper_multimesh)


func _build_rock_fields() -> void:
	var rock_positions: Array[Vector3] = []
	# Granite chute pinches the center while leaving a clearly marked safe bypass.
	for index: int in range(38):
		var t: float = float(index) / 37.0
		var z_position: float = lerpf(-344.0, -492.0, t) + _rng.randf_range(-5.0, 5.0)
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var x_position: float = side * _rng.randf_range(9.5, 22.0)
		# Keep the left ice ribbon narrowly passable.
		if side < 0.0:
			x_position -= 15.0
		var position_3d: Vector3 = Vector3(x_position, 0.0, z_position)
		rock_positions.append(position_3d)
		if build_obstacle_collisions and index % 2 == 0:
			_add_rock_collision(position_3d, _rng.randf_range(1.1, 2.2), "ChuteRock%02d" % index)
	# Finish runout rocks sit wide enough to frame, never blindside.
	for index: int in range(20):
		var side: float = -1.0 if index % 2 == 0 else 1.0
		rock_positions.append(Vector3(
			side * _rng.randf_range(48.0, 78.0), 0.0,
			_rng.randf_range(-1065.0, -840.0)
		))
	var rock_mesh: SphereMesh = SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 1.7
	rock_mesh.radial_segments = 8
	rock_mesh.rings = 5
	rock_mesh.material = _materials[&"rock"]
	var rock_multimesh: MultiMesh = _new_multimesh(rock_mesh, rock_positions.size())
	for index: int in range(rock_positions.size()):
		var position_3d: Vector3 = rock_positions[index]
		position_3d.y = terrain.height_at_local(position_3d.x, position_3d.z) + 0.48
		var scale_3d: Vector3 = Vector3(
			_rng.randf_range(0.7, 2.1),
			_rng.randf_range(0.6, 1.7),
			_rng.randf_range(0.7, 2.0)
		)
		var basis: Basis = Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(scale_3d)
		rock_multimesh.set_instance_transform(index, Transform3D(basis, position_3d))
	_add_multimesh_instance("GraniteRocks", rock_multimesh)
	if integrate_external_models:
		_place_kenney_rocks()


func _new_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = false
	multimesh.mesh = mesh
	multimesh.instance_count = count
	return multimesh


func _add_multimesh_instance(node_name: String, multimesh: MultiMesh) -> void:
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.visibility_range_end = 430.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	decoration_root.add_child(instance)


func _add_tree_collision(position_3d: Vector3, node_name: String) -> void:
	position_3d.y = terrain.height_at_local(position_3d.x, position_3d.z)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = position_3d + Vector3.UP * 1.8
	body.collision_layer = 1
	body.collision_mask = 0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = 0.44
	shape.height = 3.6
	collision.shape = shape
	body.add_child(collision)
	geometry_root.add_child(body)


func _add_rock_collision(position_3d: Vector3, radius: float, node_name: String) -> void:
	position_3d.y = terrain.height_at_local(position_3d.x, position_3d.z)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = position_3d + Vector3.UP * radius * 0.55
	body.collision_layer = 1
	body.collision_mask = 0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(radius * 1.6, radius * 1.1, radius * 1.45)
	collision.shape = shape
	body.add_child(collision)
	geometry_root.add_child(body)


func _build_course_signs() -> void:
	_create_course_label(Vector3(0.0, 0.0, -24.0), "W/S TUCK + BRAKE   A/D CARVE   SPACE POP", Color(0.08, 0.2, 0.28))
	_create_course_label(Vector3(0.0, 0.0, -142.0), "PINE SLALOM", Color(0.06, 0.26, 0.18))
	_create_course_label(Vector3(0.0, 0.0, -320.0), "SAFE BOWL  >        <  ICE SHORTCUT", Color(0.7, 0.18, 0.05))
	_create_course_label(Vector3(0.0, 0.0, -520.0), "POWDER MEADOWS / JUMP LINE", Color(0.05, 0.34, 0.52))
	_create_course_label(Vector3(0.0, 0.0, -785.0), "SAFE BOWL  >        <  WIND RIDGE", Color(0.75, 0.19, 0.04))
	_create_course_label(Vector3(0.0, 0.0, -892.0), "SUMMIT KICKER", Color(0.78, 0.12, 0.05))
	if integrate_external_models:
		for position_3d: Vector3 in [
			Vector3(-8.0, 0.0, -27.0), Vector3(8.0, 0.0, -27.0),
			Vector3(-11.0, 0.0, -320.0), Vector3(11.0, 0.0, -320.0),
		]:
			_place_external_model("sign.glb", position_3d, Vector3.ONE * 1.35)


func _create_course_label(position_3d: Vector3, text: String, color: Color) -> void:
	position_3d.y = terrain.height_at_local(position_3d.x, position_3d.z) + 3.2
	var label: Label3D = Label3D.new()
	label.name = text.to_pascal_case().replace("/", "")
	label.text = text
	label.position = position_3d
	label.font_size = 38
	label.pixel_size = 0.009
	label.modulate = Color(0.95, 0.98, 1.0)
	label.outline_modulate = color
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	decoration_root.add_child(label)


func _create_gate_visual(
	base_position: Vector3,
	gate_width: float,
	material: Material,
	label_text: String
) -> void:
	var gate: Node3D = Node3D.new()
	gate.name = label_text.to_pascal_case() + "Visual"
	gate.position = base_position
	decoration_root.add_child(gate)
	for side: float in [-1.0, 1.0]:
		var pole_mesh: CylinderMesh = CylinderMesh.new()
		pole_mesh.top_radius = 0.10
		pole_mesh.bottom_radius = 0.13
		pole_mesh.height = 4.2
		pole_mesh.radial_segments = 8
		pole_mesh.material = material
		var pole: MeshInstance3D = MeshInstance3D.new()
		pole.mesh = pole_mesh
		var pole_x: float = side * gate_width * 0.5
		var pole_ground: float = terrain.height_at_local(base_position.x + pole_x, base_position.z) - base_position.y
		pole.position = Vector3(pole_x, pole_ground + 2.1, 0.0)
		gate.add_child(pole)
	var banner_mesh: BoxMesh = BoxMesh.new()
	banner_mesh.size = Vector3(gate_width, 0.55, 0.12)
	banner_mesh.material = material
	var banner: MeshInstance3D = MeshInstance3D.new()
	banner.mesh = banner_mesh
	banner.position = Vector3(0.0, 4.0, 0.0)
	gate.add_child(banner)
	var label: Label3D = Label3D.new()
	label.text = label_text
	label.font_size = 42
	label.pixel_size = 0.009
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.03, 0.08, 0.12)
	label.outline_size = 10
	label.position = Vector3(0.0, 4.05, 0.08)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gate.add_child(label)


func _place_kenney_hero_trees() -> void:
	var positions: Array[Vector3] = [
		Vector3(-14.0, 0.0, -104.0), Vector3(18.0, 0.0, -128.0),
		Vector3(-29.0, 0.0, -179.0), Vector3(31.0, 0.0, -211.0),
		Vector3(-54.0, 0.0, -548.0), Vector3(58.0, 0.0, -612.0),
		Vector3(-61.0, 0.0, -808.0), Vector3(65.0, 0.0, -884.0),
	]
	for index: int in range(positions.size()):
		var model_name: String = "tree_cone.glb" if index % 2 == 0 else "tree_default.glb"
		_place_external_model(model_name, positions[index], Vector3.ONE * _rng.randf_range(1.2, 1.7))


func _place_kenney_rocks() -> void:
	var positions: Array[Vector3] = [
		Vector3(-13.0, 0.0, -371.0), Vector3(18.0, 0.0, -397.0),
		Vector3(-49.0, 0.0, -450.0), Vector3(15.0, 0.0, -474.0),
		Vector3(-52.0, 0.0, -882.0), Vector3(56.0, 0.0, -1014.0),
	]
	for index: int in range(positions.size()):
		var model_name: String = "rock_largeA.glb" if index % 2 == 0 else "rock_largeB.glb"
		_place_external_model(model_name, positions[index], Vector3.ONE * _rng.randf_range(1.2, 2.0))


func _place_external_model(model_name: String, position_3d: Vector3, scale_3d: Vector3) -> void:
	var path: String = KENNEY_MODEL_ROOT + model_name
	if not ResourceLoader.exists(path):
		return
	var packed_scene: PackedScene = load(path) as PackedScene
	if packed_scene == null:
		return
	var instance: Node = packed_scene.instantiate()
	if not instance is Node3D:
		instance.queue_free()
		return
	var model: Node3D = instance as Node3D
	position_3d.y = terrain.height_at_local(position_3d.x, position_3d.z)
	model.name = model_name.get_basename().to_pascal_case() + str(decoration_root.get_child_count())
	model.position = position_3d
	model.scale = scale_3d
	model.rotation.y = _rng.randf_range(-PI, PI)
	decoration_root.add_child(model)


func _on_checkpoint_activated(checkpoint_id: StringName, respawn: Transform3D) -> void:
	checkpoint_reached.emit(checkpoint_id, respawn)
	course_event.emit(&"checkpoint", {"id": checkpoint_id, "transform": respawn})


func _on_finish_crossed() -> void:
	finish_reached.emit()
	course_event.emit(&"finish", {})


func _on_risk_zone_entered(zone_id: StringName, multiplier: float, label: String) -> void:
	_active_risks[zone_id] = multiplier
	_apply_player_risk_context()
	risk_zone_changed.emit(zone_id, true, multiplier, label)
	course_event.emit(&"risk_entered", {"id": zone_id, "multiplier": multiplier, "label": label})


func _on_risk_zone_exited(zone_id: StringName, multiplier: float, label: String) -> void:
	_active_risks.erase(zone_id)
	_apply_player_risk_context()
	risk_zone_changed.emit(zone_id, false, multiplier, label)
	course_event.emit(&"risk_exited", {"id": zone_id, "multiplier": multiplier, "label": label})


func _on_jump_takeoff(jump_id: StringName, strength: float, is_large: bool) -> void:
	jump_takeoff_reached.emit(jump_id, strength, is_large)
	course_event.emit(&"jump_takeoff", {
		"id": jump_id,
		"strength": strength,
		"large": is_large,
	})


func _on_weather_accumulation(rate: float, elapsed: float) -> void:
	terrain.apply_snowfall(rate, elapsed)


func _on_weather_blend_for_player(values: Dictionary) -> void:
	if _registered_player == null or not is_instance_valid(_registered_player):
		return
	if _registered_player.has_method("apply_weather_force"):
		_registered_player.call(
			"apply_weather_force",
			values.get("airborne_force", Vector3.ZERO),
			float(values.get("drag_multiplier", 1.0))
		)
	if _registered_player.has_method("set_weather_score_multiplier"):
		_registered_player.call(
			"set_weather_score_multiplier",
			float(values.get("score_multiplier", 1.0))
		)


func _on_course_checkpoint_for_player(
	_unused_checkpoint_id: StringName,
	respawn: Transform3D
) -> void:
	if _registered_player != null and is_instance_valid(_registered_player) \
		and _registered_player.has_method("set_checkpoint"):
		_registered_player.call("set_checkpoint", respawn)


func _on_course_finish_for_player() -> void:
	if _registered_player != null and is_instance_valid(_registered_player) \
		and _registered_player.has_method("finish_run"):
		_registered_player.call("finish_run")


func _on_player_snow_spray(
	kind: StringName,
	intensity: float,
	world_position: Vector3,
	ground_normal: Vector3
) -> void:
	var motion_direction: Vector3 = Vector3.FORWARD
	if _registered_player is CharacterBody3D:
		motion_direction = (_registered_player as CharacterBody3D).velocity.normalized()
	emit_snow_spray(world_position, ground_normal, motion_direction, intensity, kind)


func _apply_player_risk_context() -> void:
	if _registered_player == null or not is_instance_valid(_registered_player) \
		or not _registered_player.has_method("set_external_risk_multiplier"):
		return
	var strongest_multiplier: float = 1.0
	for value: Variant in _active_risks.values():
		strongest_multiplier = maxf(strongest_multiplier, float(value))
	_registered_player.call("set_external_risk_multiplier", strongest_multiplier)


func _disconnect_player_feedback(player: Node3D) -> void:
	if player.has_signal(&"snow_spray_requested"):
		var spray_callable: Callable = Callable(self, "_on_player_snow_spray")
		if player.is_connected(&"snow_spray_requested", spray_callable):
			player.disconnect(&"snow_spray_requested", spray_callable)
