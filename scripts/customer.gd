class_name Customer
extends Node3D

signal clicked(customer: Customer)
signal leaving
signal finished

var data: CustomerData
var traded := false
var entrance_pos := Vector3.ZERO
var spot_pos := Vector3.ZERO
var patience := 90.0  # seconds they wait at the counter before giving up

var _tag: InteractTag
var _done := false

func _ready() -> void:
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(randf(), 0.5, 0.85)
	cap.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = cap
	mesh.position.y = 0.85
	add_child(mesh)

	_tag = InteractTag.new()
	_tag.prompt = "Talk to %s" % (data.display_name if data != null else "customer")
	_tag.enabled = false
	_tag.ignore_walls = true
	_tag.interacted.connect(_on_interacted)
	add_child(_tag)

func walk_in() -> void:
	global_position = entrance_pos
	var t := create_tween()
	t.tween_property(self, "global_position", spot_pos, 2.0)
	await t.finished
	_tag.enabled = true
	await get_tree().create_timer(patience).timeout
	if not _done:
		_leave(false)

func _on_interacted() -> void:
	clicked.emit(self)

# Called by the menu when the deal is over
func dismiss(_happy: bool) -> void:
	_leave(_happy)

func _leave(_happy: bool) -> void:
	if _done:
		return
	_done = true
	_tag.enabled = false
	leaving.emit()
	var t := create_tween()
	t.tween_property(self, "global_position", entrance_pos, 2.0)
	await t.finished
	finished.emit()
	queue_free()