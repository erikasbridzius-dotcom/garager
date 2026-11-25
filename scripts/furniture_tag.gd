class_name FurnitureTag
extends Node
@export var display_name := ""  # leave empty to use the node's name
@export var footprint := Vector2i(2, 1)  # tiles, as the item sits in the scene (unrotated)
@export var movable := true              # false = blocks tiles but can't be dragged (counter)
@export var color := Color(0.6, 0.7, 0.8)
@export var inventory_big_cells := Vector2i(0, 0)  # (0, 0) = no inventory. Shelf: (2, 3)
@export var inventory_sub := 4                      # small cells per big cell, per side
@export var add_test_items := false                 # tick once to see sample items

var stored: Array[Dictionary] = []
var trader: CustomerData = null          # set on a customer's inventory, so drops become trades
var machine: MachineTag = null           # set on a machine's sections
var slot := ""                           # which section of the machine this is
var layout_row := 0   # for machine sections: which row of the machine window it sits in
var header_provider: Callable = Callable()  # optional: returns up to 3 text lines shown under the title

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

# Can the player click this to open something?
func is_openable() -> bool:
	return inventory_big_cells.x > 0 and inventory_big_cells.y > 0

func has_header() -> bool:
	return trader != null or header_provider.is_valid()

func header_lines() -> Array:
	if trader != null:
		return trader.header_lines()
	if header_provider.is_valid():
		return header_provider.call()
	return []

# Put an item in the first free spot. Returns false if there is no room.
func try_place(item: Dictionary) -> bool:
	var cells := inventory_cells()
	var s: Vector2i = item["size"]
	for y in cells.y:
		for x in cells.x:
			if x + s.x > cells.x or y + s.y > cells.y:
				continue
			var r := Rect2i(Vector2i(x, y), s)
			var clash := false
			for other in stored:
				var ot: Vector2i = other["tile"]
				var os: Vector2i = other["size"]
				if Rect2i(ot, os).intersects(r):
					clash = true
					break
			if not clash:
				item["tile"] = Vector2i(x, y)
				stored.append(item)
				return true
	return false

func _add_test_items() -> void:
	var placements := [["sword", Vector2i(0, 0)], ["filament", Vector2i(2, 0)], ["battery", Vector2i(4, 0)]]
	for p in placements:
		var item := ItemDB.make_item(str(p[0]))
		item["tile"] = p[1]
		stored.append(item)
