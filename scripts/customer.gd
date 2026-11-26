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
var _bubble: Label3D
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

	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.pixel_size = 0.004
	_bubble.font_size = 40
	_bubble.outline_size = 10
	_bubble.width = 520.0
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.position = Vector3(0, 2.3, 0)
	_bubble.visible = false
	add_child(_bubble)

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
	speak()
	await get_tree().create_timer(patience).timeout
	_leave()

# They speak first: the greeting types out above their head
func speak() -> void:
	if data == null or data.greeting == "" or _done:
		return
	var full := data.greeting
	_bubble.text = ""
	_bubble.visible = true
	var t := create_tween()
	t.tween_method(func(v: float) -> void: _bubble.text = full.substr(0, int(v)),
		0.0, float(full.length()), full.length() * 0.03)

func hush() -> void:
	_bubble.visible = false

func _on_interacted() -> void:
	clicked.emit(self)

func _on_business_done() -> void:
	await get_tree().create_timer(2.5).timeout  # a moment to read the final line
	_leave()

func _on_dismissed() -> void:
	_leave()

func _leave() -> void:
	if _done:
		return
	_done = true
	_tag.enabled = false
	_bubble.visible = false
	leaving.emit(self)
	var t := create_tween()
	t.tween_property(self, "global_position", entrance_pos, 2.0)
	await t.finished
	finished.emit()
	if data != null:
		data.release()
	queue_free()
