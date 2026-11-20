class_name LayoutEditor
extends CanvasLayer

const TILE := 1.0  # keep whatever value you're using

const RISE_HEIGHT := 1.5  # how far the camera lifts before the black screen
const RISE_TILT := 25.0   # how much it tilts downward while lifting (degrees)
@export var player: Node3D
@export var shop_origin := Vector3(4, 0, -12)
@export var flip_rows := true
@export var invert_rotation := false
@export var forbidden_zones: Array[Rect2i] = [Rect2i(3, 3, 18, 2), Rect2i(10, 0, 4, 4)]

@onready var fade: ColorRect = $Fade
@onready var grid: LayoutGrid = $LayoutGrid
@onready var inventory_panel: InventoryPanel = $InventoryPanel

var cam: Camera3D
var _cam_pos: Vector3
var _cam_rot: Vector3
var editing := false
var transitioning := false

func _ready() -> void:
	cam = player.get_node("Camera3D")
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.modulate.a = 0.0
	grid.visible = false
	grid.item_moved.connect(_on_item_moved)
	grid.item_rotated.connect(_on_item_rotated)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_M:
		if inventory_panel.visible:
			inventory_panel.close()
			return
		if transitioning:
			return
		if editing:
			_close()
		else:
			_open()
	elif event.keycode == KEY_R and editing and not transitioning and not inventory_panel.visible:
		grid.try_rotate(not event.shift_pressed)

func _open() -> void:
	if player.busy:
		return
	transitioning = true
	editing = true
	player.busy = true
	_cam_pos = cam.position
	_cam_rot = cam.rotation_degrees

	var t := create_tween().set_parallel(true)
	t.tween_property(cam, "position:y", _cam_pos.y + RISE_HEIGHT, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(cam, "rotation_degrees:x", _cam_rot.x - RISE_TILT, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(fade, "modulate:a", 1.0, 0.3).set_delay(0.25)
	await t.finished

	_load_furniture()
	grid.visible = true
	grid.queue_redraw()
	await _fade_to(0.0)
	transitioning = false

func _close() -> void:
	transitioning = true
	await _fade_to(1.0)
	grid.visible = false

	# Start from the slightly raised view, hidden behind the black screen
	cam.position = _cam_pos + Vector3(0, RISE_HEIGHT, 0)
	cam.rotation_degrees = _cam_rot + Vector3(-RISE_TILT, 0, 0)

	var t := create_tween().set_parallel(true)
	t.tween_property(fade, "modulate:a", 0.0, 0.3)
	t.tween_property(cam, "position", _cam_pos, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(cam, "rotation_degrees", _cam_rot, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished

	player.busy = false
	editing = false
	transitioning = false

func _fade_to(alpha: float) -> void:
	var t := create_tween()
	t.tween_property(fade, "modulate:a", alpha, 0.3)
	await t.finished

func _load_furniture() -> void:
	grid.forbidden = forbidden_zones
	grid.clear_items()
	for node in get_tree().get_nodes_in_group("furniture_tag"):
		var tag := node as FurnitureTag
		var body := tag.get_parent() as Node3D
		var fp := tag.size_for(tag.rot_steps)
		grid.add_item(tag, _world_to_tile(body, fp), fp)

func _world_to_tile(body: Node3D, fp: Vector2i) -> Vector2i:
	var p: Vector3 = body.global_position - shop_origin
	var gx: float = p.z / TILE
	var gy: float = (-p.x if flip_rows else p.x) / TILE
	return Vector2i(
		roundi(gx - fp.x / 2.0),
		roundi(gy - fp.y / 2.0))

func _on_item_moved(item: LayoutGrid.Item) -> void:
	var body := item.tag.get_parent() as Node3D
	var fp: Vector2i = item.size
	var gx: float = (item.tile.x + fp.x / 2.0) * TILE
	var gy: float = (item.tile.y + fp.y / 2.0) * TILE
	body.global_position = Vector3(
		shop_origin.x + (-gy if flip_rows else gy),
		body.global_position.y,
		shop_origin.z + gx)

func _on_item_rotated(item: LayoutGrid.Item, step: int) -> void:
	var tag := item.tag
	tag.rot_steps += step
	var body := tag.get_parent() as Node3D
	var dir := -1.0 if invert_rotation else 1.0
	var target := tag.start_rot_y + tag.rot_steps * 90.0 * dir
	create_tween().tween_property(body, "rotation_degrees:y", target, 0.15)
