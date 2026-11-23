extends Node3D

const CELL_SIZE := 8.0
const MOVE_TIME := 0.25
const TURN_TIME := 0.2
const LEAN_TIME := 0.35

@export var lean_spot: Marker3D       # where the player ends up when leaning at the counter
@export var lean_range := 5.0         # how close the player must be to the spot to lean
@export var lean_fov := 60.0          # camera zoom while leaning (smaller = closer)
@export var lean_pitch := -6.0        # camera tilt while leaning (negative = look down)

var busy := false
var leaning := false

var _home_pos := Vector3.ZERO
var _cam: Camera3D
var _base_fov := 75.0
var _base_pitch := 0.0

func _ready() -> void:
	_add_action("move_forward", KEY_W)
	_add_action("move_back", KEY_S)
	_add_action("turn_left", KEY_A)
	_add_action("turn_right", KEY_D)
	_cam = get_node_or_null("Camera3D") as Camera3D
	if _cam != null:
		_base_fov = _cam.fov
		_base_pitch = _cam.rotation_degrees.x
	if lean_spot == null:
		lean_spot = get_tree().current_scene.find_child("LeanSpot", true, false) as Marker3D

func _add_action(action_name: String, key: Key) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action_name, event)

func _process(_delta: float) -> void:
	if busy:
		return

	if leaning:
		if Input.is_action_just_pressed("move_back"):
			_close_menu_and_unlean()
		return

	if Input.is_action_pressed("move_forward"):
		if _can_lean():
			lean_in()
		else:
			try_move(-global_transform.basis.z)
	elif Input.is_action_pressed("move_back"):
		try_move(global_transform.basis.z)
	elif Input.is_action_pressed("turn_left"):
		turn(90.0)
	elif Input.is_action_pressed("turn_right"):
		turn(-90.0)

func _close_menu_and_unlean() -> void:
	# Close the customer menu if one is open, then unlean
	var cm := get_tree().current_scene.find_child("CustomerMenu", true, false) as Node
	if cm != null and cm.has_method("close_menu"):
		cm.close_menu()
	unlean()

# ---------- leaning at the counter ----------

func _can_lean() -> bool:
	if lean_spot == null:
		return false
	var offset := lean_spot.global_position - global_position
	offset.y = 0.0
	var dist := offset.length()
	if dist < 0.5 or dist > lean_range:
		return false
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized().dot(offset / dist) > 0.9

func lean_in() -> void:
	busy = true
	_home_pos = global_position
	var target := Vector3(lean_spot.global_position.x, global_position.y, lean_spot.global_position.z)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "global_position", target, LEAN_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _cam != null:
		t.tween_property(_cam, "fov", lean_fov, LEAN_TIME)
		t.tween_property(_cam, "rotation_degrees:x", _base_pitch + lean_pitch, LEAN_TIME)
	await t.finished
	leaning = true
	busy = false

func unlean() -> void:
	busy = true
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "global_position", _home_pos, LEAN_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _cam != null:
		t.tween_property(_cam, "fov", _base_fov, LEAN_TIME)
		t.tween_property(_cam, "rotation_degrees:x", _base_pitch, LEAN_TIME)
	await t.finished
	global_position = _home_pos
	leaning = false
	busy = false

# ---------- normal grid movement ----------

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
