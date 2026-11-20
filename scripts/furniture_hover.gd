extends Control

@export var player: Node3D
@export var layout_editor: LayoutEditor
@export var inventory_panel: InventoryPanel
@export var interact_distance := 4

var hovered: FurnitureTag = null
var _opened_here := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	inventory_panel.closed.connect(_on_panel_closed)

func _process(_delta: float) -> void:
	var old := hovered
	if layout_editor.editing or player.busy or inventory_panel.visible:
		hovered = null
	else:
		hovered = _pick()
	if hovered != old:
		Input.set_default_cursor_shape(
			Input.CURSOR_POINTING_HAND if hovered != null else Input.CURSOR_ARROW)
	if hovered != old or hovered != null:
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if hovered == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_opened_here = true
		player.busy = true
		inventory_panel.open(hovered)
		hovered = null
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		get_viewport().set_input_as_handled()

func _on_panel_closed() -> void:
	if _opened_here:
		_opened_here = false
		player.busy = false

func _pick() -> FurnitureTag:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)

	var best: FurnitureTag = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("furniture_tag"):
		var tag := node as FurnitureTag
		if tag.inventory_big_cells.x <= 0 or tag.inventory_big_cells.y <= 0:
			continue
		var box := _world_aabb(tag.get_parent() as Node3D)
		if box.size == Vector3.ZERO:
			continue
		var hit = box.intersects_ray(from, dir)
		if hit == null:
			continue
		var d := from.distance_to(hit)
		if d < best_d and d <= interact_distance:
			best = tag
			best_d = d
	if best == null:
		return null

	# Something solid (a wall) between the camera and the furniture blocks it
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * (best_d - 0.05))
	if not cam.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return null
	return best

func _world_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is VisualInstance3D and not n is Light3D:
			var v := n as VisualInstance3D
			var b: AABB = v.global_transform * v.get_aabb()
			if first:
				result = b
				first = false
			else:
				result = result.merge(b)
	return result

func _draw() -> void:
	if hovered == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var box := _world_aabb(hovered.get_parent() as Node3D)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var corner := box.get_endpoint(i)
		if cam.is_position_behind(corner):
			return
		var sp := cam.unproject_position(corner)
		lo = Vector2(minf(lo.x, sp.x), minf(lo.y, sp.y))
		hi = Vector2(maxf(hi.x, sp.x), maxf(hi.y, sp.y))
	draw_rect(Rect2(lo, hi - lo).grow(3.0), Color(1, 0.9, 0.2, 0.9), false, 2.0)
