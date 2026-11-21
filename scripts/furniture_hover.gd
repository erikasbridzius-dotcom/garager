extends Control

@export var player: Node3D
@export var layout_editor: LayoutEditor
@export var inventory_panel: InventoryPanel
@export var interact_distance := 10.0

var hovered: Node = null  # a FurnitureTag or an InteractTag
var _locked := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var root := get_tree().current_scene
	if player == null:
		player = root.find_child("Player", true, false) as Node3D
	if layout_editor == null:
		layout_editor = root.find_child("ShopEditor", true, false) as LayoutEditor
	if inventory_panel == null:
		inventory_panel = root.find_child("InventoryPanel", true, false) as InventoryPanel
	if player == null or layout_editor == null or inventory_panel == null:
		push_error("FurnitureHover: could not find Player, ShopEditor and InventoryPanel nodes.")
		set_process(false)
		set_process_unhandled_input(false)
		return
	inventory_panel.all_closed.connect(_on_all_closed)

func _process(_delta: float) -> void:
	if _locked and not inventory_panel.has_windows():
		_locked = false
		player.busy = false
	if hovered != null and not is_instance_valid(hovered):
		hovered = null
		queue_redraw()
	var old := hovered
	var blocked: bool = layout_editor.editing or (player.busy and not _locked)
	var over_window := _over_ui()
	if blocked or over_window:
		hovered = null
	else:
		hovered = _pick()
	if hovered != old:
		Input.set_default_cursor_shape(
			Input.CURSOR_POINTING_HAND if hovered != null else Input.CURSOR_ARROW)
	if hovered != old or hovered != null:
		queue_redraw()

func _over_ui() -> bool:
	if inventory_panel.blocks_point(inventory_panel.get_local_mouse_position()):
		return true
	var mp := get_viewport().get_mouse_position()
	for n in get_tree().get_nodes_in_group("ui_blocker"):
		if n.blocks_point(mp):
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if hovered == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var target := hovered
		hovered = null
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		queue_redraw()
		if target is FurnitureTag:
			_locked = true
			player.busy = true
			inventory_panel.open(target as FurnitureTag)
		elif target is InteractTag:
			(target as InteractTag).interact()
		get_viewport().set_input_as_handled()

func _on_all_closed() -> void:
	if _locked:
		_locked = false
		player.busy = false
	hovered = null
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	queue_redraw()

func _ray_dist(body: Node3D, from: Vector3, dir: Vector3) -> float:
	var box := _world_aabb(body)
	if box.size == Vector3.ZERO:
		return -1.0
	var hit = box.intersects_ray(from, dir)
	if hit == null:
		return -1.0
	return from.distance_to(hit)

func _pick() -> Node:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)

	var best: Node = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("furniture_tag"):
		var tag := node as FurnitureTag
		if tag.inventory_big_cells.x <= 0 or tag.inventory_big_cells.y <= 0:
			continue
		var d := _ray_dist(tag.get_parent() as Node3D, from, dir)
		if d >= 0.0 and d < best_d and d <= interact_distance:
			best = tag
			best_d = d
	for node in get_tree().get_nodes_in_group("interact_tag"):
		var it := node as InteractTag
		if not it.enabled:
			continue
		var d := _ray_dist(it.get_parent() as Node3D, from, dir)
		if d >= 0.0 and d < best_d and d <= interact_distance:
			best = it
			best_d = d
	if best == null:
		return null
	if best is InteractTag and (best as InteractTag).ignore_walls:
		return best

	# Something solid (a wall) between the camera and the target blocks it
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
	if hovered is InteractTag:
		_draw_prompt((hovered as InteractTag).prompt)

func _draw_prompt(text: String) -> void:
	var font := ThemeDB.fallback_font
	var fs := 16
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pad := Vector2(8, 4)
	var box := ts + pad * 2.0
	var pos := get_local_mouse_position() + Vector2(16, 20)
	pos.x = clampf(pos.x, 0.0, size.x - box.x)
	pos.y = clampf(pos.y, 0.0, size.y - box.y)
	draw_rect(Rect2(pos, box), Color(0, 0, 0, 0.85))
	draw_string(font, pos + pad + Vector2(0, font.get_ascent(fs)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
