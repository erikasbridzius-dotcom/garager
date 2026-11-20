extends Node3D

const CELL_SIZE := 8
const MOVE_TIME := 0.5
const TURN_TIME := 0.5

var busy := false

func _process(_delta: float) -> void:
	if busy:
		return

	if Input.is_action_pressed("move_forward"):
		try_move(-global_transform.basis.z)
	elif Input.is_action_pressed("move_back"):
		try_move(global_transform.basis.z)
	elif Input.is_action_pressed("turn_left"):
		turn(90.0)
	elif Input.is_action_pressed("turn_right"):
		turn(-90.0)

func try_move(dir: Vector3) -> void:
	dir = dir.snapped(Vector3.ONE * 0.01).normalized()
	if is_blocked(dir):
		return
	busy = true
	var target := position + dir * CELL_SIZE
	var tween := create_tween()
	tween.tween_property(self, "position", target, MOVE_TIME)
	tween.finished.connect(func():
		position = position.snapped(Vector3(CELL_SIZE, 0.0, CELL_SIZE))
		busy = false)

func turn(degrees: float) -> void:
	busy = true
	var target := rotation_degrees.y + degrees
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees:y", target, TURN_TIME)
	tween.finished.connect(func():
		rotation_degrees.y = snappedf(rotation_degrees.y, 90.0)
		busy = false)

func is_blocked(dir: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.0, 0)
	var to := from + dir * (CELL_SIZE * 0.75)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return not space.intersect_ray(query).is_empty()
