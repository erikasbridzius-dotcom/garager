extends Node3D

@export var inventory_panel: InventoryPanel
@export var layout_editor: LayoutEditor
@export var hand_spacing := 0.56  # distance between the hands. This node is the RIGHT hand.

var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	var root := get_tree().current_scene
	if inventory_panel == null:
		inventory_panel = root.find_child("InventoryPanel", true, false) as InventoryPanel
	if layout_editor == null:
		layout_editor = root.find_child("ShopEditor", true, false) as LayoutEditor
	if inventory_panel == null or layout_editor == null:
		push_error("HeldItemView: could not find InventoryPanel and ShopEditor nodes.")
		set_process(false)
		return
	for i in 2:
		var m := MeshInstance3D.new()
		if i == 0:
			m.position = Vector3(-hand_spacing, 0, 0)
			m.rotation_degrees = Vector3(15, 25, 0)
		else:
			m.rotation_degrees = Vector3(15, -25, 0)
		m.visible = false
		add_child(m)
		_meshes.append(m)
	inventory_panel.hand_changed.connect(_on_hand_changed)
	for i in 2:
		_on_hand_changed(i, inventory_panel.hands[i])

func _process(_delta: float) -> void:
	var in_editor: bool = layout_editor.editing
	for i in 2:
		var item: Dictionary = inventory_panel.hands[i]
		_meshes[i].visible = not item.is_empty() and not item.get("ghost", false) and not in_editor
	inventory_panel.show_hands = not in_editor

func _on_hand_changed(index: int, entry: Dictionary) -> void:
	if entry.is_empty() or entry.get("ghost", false):
		_meshes[0].position.x = -hand_spacing
		return
	var col: Color = entry["color"]
	var box := BoxMesh.new()
	if entry.get("is_box", false):
		box.size = Vector3(0.4, 0.3, 0.3)          # one big box held between both arms
		_meshes[0].position.x = -hand_spacing * 0.5
	else:
		var s: Vector2i = entry["size"]
		var unit := 0.06
		box.size = Vector3(maxf(s.x * unit, 0.05), maxf(s.y * unit, 0.05), 0.06)
		if index == 0:
			_meshes[0].position.x = -hand_spacing
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	box.material = mat
	_meshes[index].mesh = box
