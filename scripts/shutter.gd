class_name Shutter
extends Node3D

signal finished

@export var open_height := 3.0
@export var duration := 1.4

var is_open := false
var _closed_y := 0.0
var _tween: Tween

func _ready() -> void:
	_closed_y = position.y

func open() -> void:
	_move(_closed_y + open_height, true)

func close() -> void:
	_move(_closed_y, false)

func _move(target_y: float, opening: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position:y", target_y, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	is_open = opening
	finished.emit()
