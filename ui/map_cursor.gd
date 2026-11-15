class_name MapCursor
extends RefCounted

## Directional planet-to-planet navigation for the gamepad/keyboard map cursor. Pure and
## deterministic: give it a dictionary of id -> 2D map position and a direction, and it
## returns the next world. No Node, no screen projection, no camera.
##
## Positions are **world-plane** positions (x/y of each planet's layout position), not
## screen pixels. That keeps navigation stable at every zoom level: a high zoom can move
## the camera without changing which world is "to the right" of the current one.

const CONE_DOT := 0.25       ## prefer a candidate at most ~75 degrees off the stick
const HALF_PLANE_DOT := 0.0  ## fallback: anything in front of the stick
const ANGLE_TIE := 0.05      ## radians (~3 degrees): within this, the nearer world wins

var current_id: StringName = &""


func set_current(id: StringName) -> void:
	current_id = id


func step(positions: Dictionary, direction: Vector2) -> StringName:
	var next := next_id(positions, current_id, direction)
	if next != &"":
		current_id = next
	return current_id


## Pure form used by tests and by `step`. Returns `current_id` when there is nowhere
## better to go.
static func next_id(positions: Dictionary, current_id: StringName, direction: Vector2) -> StringName:
	if positions.is_empty():
		return current_id
	var dir := direction.normalized()
	if dir.is_zero_approx():
		return current_id
	if not positions.has(current_id):
		return _nearest_to_origin(positions)

	var origin: Vector2 = positions[current_id]
	var found := _best_in_cone(positions, current_id, origin, dir, CONE_DOT)
	if found != &"":
		return found
	found = _best_in_cone(positions, current_id, origin, dir, HALF_PLANE_DOT)
	return found if found != &"" else current_id


static func _best_in_cone(positions: Dictionary, current_id: StringName, origin: Vector2,
		dir: Vector2, minimum_dot: float) -> StringName:
	var best: StringName = &""
	var best_angle := INF
	var best_dist := INF
	for key in positions:
		if key == current_id:
			continue
		var delta: Vector2 = (positions[key] as Vector2) - origin
		if delta.length_squared() < 0.0001:
			continue
		var dist := delta.length()
		var dot := delta.normalized().dot(dir)
		if dot < minimum_dot:
			continue
		# Direction decides: the candidate closest to the exact angle of the stick wins, so
		# pushing straight at a world selects it even when a nearer one sits 45 degrees off.
		# Distance only breaks a (near-)tie between candidates in the same direction.
		var angle := acos(clampf(dot, -1.0, 1.0))
		var better := false
		if angle < best_angle - ANGLE_TIE:
			better = true
		elif angle <= best_angle + ANGLE_TIE:
			if dist < best_dist - 0.0001:
				better = true
			elif is_equal_approx(dist, best_dist) and String(key) < String(best):
				better = true
		if better:
			best_angle = angle
			best_dist = dist
			best = key
	return best


static func _nearest_to_origin(positions: Dictionary) -> StringName:
	var best: StringName = &""
	var best_d := INF
	for key in positions:
		var d := (positions[key] as Vector2).length_squared()
		if d < best_d - 0.0001:
			best_d = d
			best = key
		elif is_equal_approx(d, best_d) and String(key) < String(best):
			best = key
	return best
