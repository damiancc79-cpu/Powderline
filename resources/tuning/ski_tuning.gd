class_name SkiTuning
extends Resource

## Central, shareable tuning for the momentum skier. Values use metres, seconds,
## radians, and metres/second unless a property explicitly says otherwise.

@export_category("Gravity and contact")
@export_range(1.0, 60.0, 0.5) var gravity: float = 24.0
@export_range(0.0, 20.0, 0.1) var slope_gravity_scale: float = 1.0
@export_range(0.0, 2.0, 0.01) var floor_snap_length: float = 0.55
@export_range(0.0, 1.0, 0.01) var ground_probe_grace: float = 0.10
@export_range(0.0, 1.0, 0.01) var landing_grace: float = 0.16
@export_range(0.0, 4.0, 0.05) var suspension_strength: float = 1.4

@export_category("Momentum")
@export_range(0.0, 20.0, 0.1) var low_speed_push: float = 5.0
@export_range(0.0, 10.0, 0.1) var ground_friction: float = 1.25
@export_range(0.0, 10.0, 0.1) var powder_friction: float = 2.0
@export_range(0.0, 10.0, 0.1) var ice_friction: float = 0.35
@export_range(0.0, 0.1, 0.0005) var aerodynamic_drag: float = 0.010
@export_range(0.0, 0.1, 0.0005) var tuck_drag: float = 0.0035
@export_range(0.0, 30.0, 0.25) var brake_drag: float = 12.0
@export_range(5.0, 80.0, 0.5) var practical_max_speed: float = 38.0
@export_range(0.0, 2.0, 0.01) var overspeed_drag: float = 0.16

@export_category("Steering and carving")
@export_range(0.0, 20.0, 0.1) var carve_strength: float = 7.5
@export_range(0.0, 4.0, 0.05) var edge_grip: float = 1.0
@export_range(0.1, 20.0, 0.1) var steering_response: float = 7.0
@export_range(10.0, 240.0, 1.0) var low_speed_turn_rate_degrees: float = 112.0
@export_range(5.0, 180.0, 1.0) var high_speed_turn_rate_degrees: float = 38.0
@export_range(1.0, 50.0, 0.5) var full_speed_steering_at: float = 30.0
@export_range(0.0, 1.0, 0.01) var lateral_damping: float = 0.25
@export_range(0.0, 70.0, 0.5) var maximum_lean_degrees: float = 32.0
@export_range(0.0, 20.0, 0.1) var visual_alignment_speed: float = 9.0

@export_category("Jump and air")
@export_range(0.0, 30.0, 0.1) var jump_impulse: float = 8.0
@export_range(0.0, 10.0, 0.1) var jump_forward_boost: float = 1.2
@export_range(0.0, 1.0, 0.01) var air_control: float = 0.22
@export_range(0.0, 10.0, 0.1) var airborne_drag: float = 0.08
@export_range(0.0, 10.0, 0.05) var wind_response: float = 0.8

@export_category("Tricks")
@export_range(0.0, 1.0, 0.01) var trick_input_buffer: float = 0.28
@export_range(90.0, 1080.0, 5.0) var spin_speed_degrees: float = 430.0
@export_range(90.0, 1080.0, 5.0) var flip_speed_degrees: float = 390.0
@export_range(90.0, 1080.0, 5.0) var maximum_trick_speed_degrees: float = 600.0
@export_range(0.0, 90.0, 1.0) var tweak_angle_degrees: float = 24.0
@export_range(0.0, 2.0, 0.01) var grab_minimum_time: float = 0.18

@export_category("Landing and crash")
@export_range(1.0, 50.0, 0.5) var hard_landing_speed: float = 14.0
@export_range(1.0, 80.0, 0.5) var crash_impact_speed: float = 19.0
@export_range(1.0, 80.0, 0.5) var obstacle_crash_speed: float = 13.0
@export_range(1.0, 89.0, 1.0) var maximum_stable_landing_angle: float = 38.0
@export_range(0.0, 45.0, 1.0) var perfect_landing_angle: float = 9.0
@export_range(1.0, 90.0, 1.0) var maximum_sideways_angle: float = 42.0
@export_range(0.1, 10.0, 0.1) var crash_control_lock_time: float = 1.15
@export_range(0.0, 5.0, 0.1) var recovery_settle_time: float = 0.35

@export_category("Feedback")
@export_range(0.01, 1.0, 0.01) var trail_base_width: float = 0.09
@export_range(0.0, 3.0, 0.05) var trail_carve_width_scale: float = 0.45
@export_range(0.0, 1.0, 0.01) var spray_carve_threshold: float = 0.42
@export_range(0.0, 1.0, 0.01) var spray_brake_threshold: float = 0.2
