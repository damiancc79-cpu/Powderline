class_name LandingEvaluator
extends Node

## Pure landing classification. The caller supplies the authoritative contact
## normal and pre-impact motion so this node never performs a second ground test.


func evaluate(
		impact_speed: float,
		skier_up: Vector3,
		skier_forward: Vector3,
		travel_velocity: Vector3,
		ground_normal: Vector3,
		tuning: SkiTuning
	) -> Dictionary:
	var safe_normal := ground_normal.normalized()
	var safe_up := skier_up.normalized()
	var upright_angle := rad_to_deg(acos(clampf(safe_up.dot(safe_normal), -1.0, 1.0)))

	var travel_tangent := travel_velocity.slide(safe_normal)
	var forward_tangent := skier_forward.slide(safe_normal)
	var sideways_angle := 0.0
	if travel_tangent.length_squared() > 0.01 and forward_tangent.length_squared() > 0.01:
		var raw_direction_angle := rad_to_deg(acos(clampf(
			forward_tangent.normalized().dot(travel_tangent.normalized()), -1.0, 1.0
		)))
		# Landing switch is valid; only the distance to forward/backward alignment
		# matters for a sideways impact.
		sideways_angle = minf(raw_direction_angle, absf(180.0 - raw_direction_angle))

	var angle_ok := upright_angle <= tuning.maximum_stable_landing_angle
	var direction_ok := sideways_angle <= tuning.maximum_sideways_angle
	var impact_ok := impact_speed <= tuning.crash_impact_speed
	var success := angle_ok and direction_ok and impact_ok
	var perfect := success \
		and upright_angle <= tuning.perfect_landing_angle \
		and sideways_angle <= tuning.perfect_landing_angle \
		and impact_speed <= tuning.hard_landing_speed * 0.72

	var angle_quality := 1.0 - clampf(upright_angle / tuning.maximum_stable_landing_angle, 0.0, 1.0)
	var direction_quality := 1.0 - clampf(sideways_angle / tuning.maximum_sideways_angle, 0.0, 1.0)
	var impact_quality := 1.0 - clampf(impact_speed / tuning.crash_impact_speed, 0.0, 1.0)
	var quality := clampf(angle_quality * 0.45 + direction_quality * 0.35 + impact_quality * 0.20, 0.0, 1.0)
	var multiplier := lerpf(0.75, 1.35, quality)
	if perfect:
		multiplier = 1.5

	var reason: StringName = &"clean"
	if not impact_ok:
		reason = &"hard_impact"
	elif not angle_ok:
		reason = &"bad_landing_angle"
	elif not direction_ok:
		reason = &"sideways_landing"
	elif perfect:
		reason = &"perfect"
	elif impact_speed > tuning.hard_landing_speed:
		reason = &"heavy"

	return {
		"success": success,
		"perfect": perfect,
		"reason": reason,
		"quality": quality,
		"multiplier": multiplier,
		"impact_speed": impact_speed,
		"upright_angle": upright_angle,
		"sideways_angle": sideways_angle,
	}
