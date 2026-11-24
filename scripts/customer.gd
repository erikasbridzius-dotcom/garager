class_name Customer
extends Node3D

signal clicked(customer: Customer)
signal leaving(customer: Customer)
signal finished

var data: CustomerData
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

	if data != null:
		data.finished_business.connect(_on_business_done)
		data.dismissed.connect(_on_dismissed)

func walk_in() -> void:
	global_position = entrance_pos
	var t := create_tween()
	t.tween_property(self, "global_position", spot_pos, 2.0)
	await t.finished
	_tag.enabled = true
	await get_tree().create_timer(patience).timeout
	_leave()

func _on_interacted() -> void:
	clicked.emit(self)

func _on_business_done() -> void:
	await get_tree().create_timer(1.2).timeout  # a moment to read the final note
	_leave()

func _on_dismissed() -> void:
	_leave()

func _leave() -> void:
	if _done:
		return
	_done = true
	_tag.enabled = false
	leaving.emit(self)
	var t := create_tween()
	t.tween_property(self, "global_position", entrance_pos, 2.0)
	await t.finished
	finished.emit()
	if data != null:
		data.release()
	queue_free()
