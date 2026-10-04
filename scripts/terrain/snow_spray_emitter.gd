class_name SnowSprayEmitter
extends Node3D

@export_range(2, 16, 1) var pool_size: int = 8
@export_range(12, 128, 1) var particles_per_burst: int = 52

var _pool: Array[GPUParticles3D] = []
var _cursor: int = 0


func _ready() -> void:
	for index: int in range(pool_size):
		_pool.append(_create_emitter(index))


func emit_spray(
	world_position: Vector3,
	ground_normal: Vector3,
	motion_direction: Vector3,
	intensity: float = 1.0,
	kind: StringName = &"carve"
) -> void:
	if _pool.is_empty():
		return
	var emitter: GPUParticles3D = _pool[_cursor]
	_cursor = (_cursor + 1) % _pool.size()
	var scaled_intensity: float = clampf(intensity, 0.1, 2.5)
	if kind == &"landing":
		scaled_intensity *= 1.45
	elif kind == &"takeoff":
		scaled_intensity *= 1.2
	elif kind == &"brake":
		scaled_intensity *= 1.15
	var normal: Vector3 = ground_normal.normalized()
	var forward: Vector3 = motion_direction.slide(normal).normalized()
	if forward.length_squared() < 0.1:
		forward = Vector3.FORWARD
	var right: Vector3 = normal.cross(forward).normalized()
	if right.length_squared() < 0.1:
		right = Vector3.RIGHT
	forward = right.cross(normal).normalized()
	emitter.global_transform = Transform3D(Basis(right, normal, forward), world_position)
	emitter.amount_ratio = clampf(scaled_intensity / 2.0, 0.15, 1.0)
	var process_material: ParticleProcessMaterial = emitter.process_material as ParticleProcessMaterial
	if process_material != null:
		process_material.initial_velocity_min = 3.5 + scaled_intensity * 2.2
		process_material.initial_velocity_max = 6.0 + scaled_intensity * 4.2
		process_material.scale_min = 0.025 + scaled_intensity * 0.012
		process_material.scale_max = 0.075 + scaled_intensity * 0.038
	emitter.restart()
	emitter.emitting = true


func emit_carve_spray(
	world_position: Vector3,
	ground_normal: Vector3,
	motion_direction: Vector3,
	carve_strength: float,
	surface_spray_multiplier: float = 1.0
) -> void:
	emit_spray(
		world_position,
		ground_normal,
		-motion_direction,
		carve_strength * surface_spray_multiplier,
		&"carve"
	)


func emit_landing_burst(
	world_position: Vector3,
	ground_normal: Vector3,
	motion_direction: Vector3,
	impact_strength: float
) -> void:
	emit_spray(world_position, ground_normal, -motion_direction, impact_strength, &"landing")


func get_active_particle_count() -> int:
	var count: int = 0
	for emitter: GPUParticles3D in _pool:
		if emitter.emitting:
			count += roundi(float(emitter.amount) * emitter.amount_ratio)
	return count


func _create_emitter(index: int) -> GPUParticles3D:
	var emitter: GPUParticles3D = GPUParticles3D.new()
	emitter.name = "SprayBurst%02d" % index
	emitter.amount = particles_per_burst
	emitter.lifetime = 0.72
	emitter.one_shot = true
	emitter.explosiveness = 0.86
	emitter.randomness = 0.35
	emitter.emitting = false
	emitter.visibility_aabb = AABB(Vector3(-8.0, -3.0, -8.0), Vector3(16.0, 12.0, 16.0))
	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.24
	process_material.direction = Vector3(0.0, 0.75, 0.65)
	process_material.spread = 34.0
	process_material.initial_velocity_min = 4.0
	process_material.initial_velocity_max = 8.0
	process_material.gravity = Vector3(0.0, -13.0, 0.0)
	process_material.damping_min = 1.2
	process_material.damping_max = 2.6
	process_material.scale_min = 0.04
	process_material.scale_max = 0.12
	process_material.color = Color(0.92, 0.97, 1.0, 0.82)
	emitter.process_material = process_material
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.13, 0.13)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.94, 0.98, 1.0, 0.82)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particle_mesh.material = material
	emitter.draw_pass_1 = particle_mesh
	add_child(emitter)
	return emitter
