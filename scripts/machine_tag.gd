class_name MachineTag
extends FurnitureTag

# Base for all machines. A machine is a FurnitureTag (so it can be moved in the layout editor)
# that owns several inventory sections, shown together in ONE window, and does something once per day.
# Optional: an info panel with a button between sections (see WorkbenchTag).
# To make a new machine: extend this, override _build_sections(), accepts(), process_day(), status_lines().

var sections: Array[FurnitureTag] = []
var status := ""
var info_after := ""        # slot name: show an info panel right after this section ("" = none)
var info_title := "Info"

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

# Up to 3 lines shown under the window title (return [] for no header)
func status_lines() -> Array:
	return [status]

# Info panel: lines are [text, Color]. Keep it to about 5 lines.
func info_lines() -> Array:
	return []

func action_label() -> String:   # "" = no button
	return ""

func action_enabled() -> bool:
	return false

func on_action() -> void:
	pass

# ----- helpers -----
# row: sections with the same row number sit side by side; a higher row goes below
func _add_section(slot_name: String, title: String, big: Vector2i, sub: int, row := 0) -> FurnitureTag:
	var s := FurnitureTag.new()
	s.display_name = title
	s.inventory_big_cells = big
	s.inventory_sub = sub
	s.movable = false
	s.machine = self
	s.slot = slot_name
	s.layout_row = row
	sections.append(s)
	return s

func section(slot_name: String) -> FurnitureTag:
	for s in sections:
		if s.slot == slot_name:
			return s
	return null
