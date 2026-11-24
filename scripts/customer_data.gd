class_name CustomerData
extends RefCounted

signal finished_business   # nothing left to buy or sell
signal dismissed           # the player pressed "Send away"

const NAMES := ["Ada", "Bruno", "Cato", "Dara", "Eli", "Fenna", "Gus", "Hana", "Ivo", "Juno", "Kira", "Lars"]
const GRID_BIG := Vector2i(4, 3)  # the customer's inventory size, in big cells (change to (2, 3) for shelf size)
const GRID_SUB := 4               # small cells per big cell, per side

var display_name := "Customer"
var wants: Array = []                    # tags an item must ALL have to be wanted
var budget := 0                          # most they will spend
var pay_factor := 1.0                    # how generous they are compared to market value
var inventory: Array[Dictionary] = []    # items they carry, each with "for_sale" and "ask"
var traded := false
var note := ""                           # the status line shown under the budget

var _container: FurnitureTag = null

# ---------- the customer's inventory as a shelf-style container ----------

func container() -> FurnitureTag:
	if _container == null:
		_container = FurnitureTag.new()
		_container.display_name = display_name
		_container.inventory_big_cells = GRID_BIG
		_container.inventory_sub = GRID_SUB
		_container.movable = false
		_container.stored = inventory
		_container.trader = self
	return _container

# Called when the customer is gone, to break the reference loop and free the container
func release() -> void:
	if _container != null and is_instance_valid(_container):
		_container.trader = null
		_container.free()
	_container = null

func header_lines() -> Array[String]:
	var lines: Array[String] = []
	if wants.is_empty():
		lines.append("Wants: nothing")
	else:
		lines.append("Wants: " + ", ".join(PackedStringArray(wants)))
	lines.append("Budget: § %d" % budget)
	lines.append(note)
	return lines

# ---------- trading ----------



func offer_for(entry: Dictionary) -> int:
	return roundi(ItemDB.value_of(entry) * pay_factor)

# "" if the customer will buy this item, otherwise the reason they won't
func sale_problem(entry: Dictionary) -> String:
	if wants.is_empty():
		return "Doesn't need anything"
	if not ItemDB.has_all_tags(entry, wants):
		return "Doesn't want that"
	var offer := offer_for(entry)
	if offer > budget:
		return "Budget too low (§%d)" % offer
	return ""

# The player sold `entry` to this customer. Returns the money to pay.
func receive_sale(entry: Dictionary) -> int:
	var offer := offer_for(entry)
	budget -= offer
	wants = []
	entry["for_sale"] = false
	entry.erase("ask")
	entry.erase("bought")
	traded = true
	note = "Sold %s for §%d" % [entry["name"], offer]
	check_done()
	return offer

# The player bought `entry` from this customer.
func complete_purchase(entry: Dictionary) -> void:
	note = "You bought %s for §%d" % [entry["name"], int(entry.get("ask", 0))]
	entry["bought"] = int(entry.get("ask", 0))
	entry.erase("ask")
	entry.erase("for_sale")
	traded = true
	check_done()

func check_done() -> void:
	if not traded:
		return
	for e in inventory:
		if e.get("for_sale", false):
			return
	if wants.is_empty():
		finished_business.emit()

# ---------- random profile ----------

func roll() -> void:
	display_name = NAMES[randi() % NAMES.size()]
	pay_factor = randf_range(0.9, 1.4)
	var ids: Array = ItemDB.defs.keys()
	if ids.is_empty():
		return
	var kind := randi() % 3  # 0 = buys, 1 = sells, 2 = both
	if kind != 1:
		_roll_wants(ids)
	if kind != 0:
		_roll_items(ids)

func _roll_wants(ids: Array) -> void:
	var ref := ItemDB.make_item(str(ids[randi() % ids.size()]))
	var tags: Array = ref["tags"]
	if tags.is_empty():
		return
	wants = [tags[0]]
	if tags.size() > 1 and randf() < 0.4:
		wants.append(tags[1 + randi() % (tags.size() - 1)])
	budget = roundi(ItemDB.value_of(ref) * pay_factor * randf_range(1.1, 2.0))

func _roll_items(ids: Array) -> void:
	for i in 1 + randi() % 3:
		var it := ItemDB.make_item(str(ids[randi() % ids.size()]))
		it["for_sale"] = (i == 0) or randf() < 0.6
		it["ask"] = roundi(ItemDB.value_of(it) * randf_range(0.7, 1.2))
		if _auto_place(it):
			inventory.append(it)

# Put the item in the first free spot of the grid
func _auto_place(it: Dictionary) -> bool:
	var cells := GRID_BIG * GRID_SUB
	var s: Vector2i = it["size"]
	for y in cells.y:
		for x in cells.x:
			if x + s.x > cells.x or y + s.y > cells.y:
				continue
			var r := Rect2i(Vector2i(x, y), s)
			var clash := false
			for other in inventory:
				var ot: Vector2i = other["tile"]
				var os: Vector2i = other["size"]
				if Rect2i(ot, os).intersects(r):
					clash = true
					break
			if not clash:
				it["tile"] = Vector2i(x, y)
				return true
	return false
