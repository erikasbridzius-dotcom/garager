class_name MachineTag
extends FurnitureTag

# Base for all machines. A machine is a FurnitureTag (so it can be moved in the layout editor)
# that owns several inventory sections and does something once per day.
# To make a new machine: extend this, override _build_sections(), accepts() and process_day().

var sections: Array[FurnitureTag] = []
var status := ""

func _ready() -> void:
	super()
	_build_sections()
	GameState.day_changed.connect(_on_day_changed)

func _exit_tree() -> void:
	for s in sections:
		if is_instance_valid(s):
			s.free()
	sections.clear()

func is_openable() -> bool:
	return true

func _on_day_changed(_day: int) -> void:
	process_day()

# ----- override these -----
func _build_sections() -> void:
	pass

# "" = the item may go into that section, otherwise the reason it can't
func accepts(_slot: String, _item: Dictionary) -> String:
	return ""

func process_day() -> void:
	pass

# ----- helpers -----
func _add_section(slot_name: String, title: String, big: Vector2i, sub: int) -> FurnitureTag:
	var s := FurnitureTag.new()
	s.display_name = title
	s.inventory_big_cells = big
	s.inventory_sub = sub
	s.movable = false
	s.machine = self
	s.slot = slot_name
	sections.append(s)
	return s

func section(slot_name: String) -> FurnitureTag:
	for s in sections:
		if s.slot == slot_name:
			return s
	return null
