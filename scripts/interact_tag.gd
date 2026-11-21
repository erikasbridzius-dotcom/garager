class_name InteractTag
extends Node

signal interacted

@export var prompt := "Interact"
@export var enabled := true
@export var ignore_walls := false  # true = clickable even if something solid is in the way

func _ready() -> void:
	add_to_group("interact_tag")

func interact() -> void:
	if enabled:
		interacted.emit()
