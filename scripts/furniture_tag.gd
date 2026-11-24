class_name FurnitureTag
extends Node
@export var display_name := ""  # leave empty to use the node's name
@export var footprint := Vector2i(2, 1)  # tiles, as the item sits in the scene (unrotated)
@export var movable := true              # false = blocks tiles but can't be dragged (counter)
@export var color := Color(0.6, 0.7, 0.8)
@export var inventory_big_cells := Vector2i(0, 0)  # (0, 0) = no inventory. Shelf: (2, 3)
@export var inventory_sub := 4                      # small cells per big cell, per side
@export var add_test_items := false                 # tick once to see sample items
var trader: CustomerData = null  # set on a customer's inventory, so drops become trades

var stored: Array[Dictionary] = []

var rot_steps := 0
var start_rot_y := 0.0

func _ready() -> void:
	add_to_group("furniture_tag")
	var body := get_parent() as Node3D
	start_rot_y = body.rotation_degrees.y
	if add_test_items:
		_add_test_items()

func size_for(steps: int) -> Vector2i:
	if posmod(steps, 2) == 1:
		return Vector2i(footprint.y, footprint.x)
	return footprint

func get_display_name() -> String:
	if display_name != "":
		return display_name
	return get_parent().name.capitalize()

func inventory_cells() -> Vector2i:
	return inventory_big_cells * inventory_sub

func _add_test_items() -> void:
	var placements := [["sword", Vector2i(0, 0)], ["canned_food", Vector2i(2, 0)], ["crate", Vector2i(4, 0)]]
	for p in placements:
		var item := ItemDB.make_item(str(p[0]))
		item["tile"] = p[1]
		stored.append(item)
