class_name CustomerData
extends RefCounted

signal finished_business   # nothing left to buy or sell
signal dismissed           # the customer should leave now

const NAMES := ["Ada", "Bruno", "Cato", "Dara", "Eli", "Fenna", "Gus", "Hana", "Ivo", "Juno", "Kira", "Lars"]
const GREETINGS := ["Hey, got a minute?", "Anything good in stock?", "Hello there.", "Quiet day, huh?"]
const GRID_BIG := Vector2i(4, 3)  # the customer's inventory size, in big cells
const GRID_SUB := 4               # small cells per big cell, per side
const PRINT_DAYS := 3             # days until a print customer comes back
const RESTORE_DAYS := 2
const GRACE_DAYS := 2             # days after the due day that an order stays open

# "trader" = buys/sells, "print_offer" / "restore_offer" = asks for a job, "pickup" = returning for a job
var kind := "trader"
var greeting := ""                       # the bubble line when they arrive
var offer: Dictionary = {}               # the job they propose (offer kinds)
var order: Dictionary = {}               # the job they come to collect (pickup)
var resolved_text := ""                  # set once the job is accepted, delivered or cancelled: they only say goodbye

var display_name := "Customer"
var wants: Array = []                    # tags an item must ALL have to be wanted
var budget := 0                          # most they will spend
var pay_factor := 1.0                    # how generous they are compared to market value
var inventory: Array[Dictionary] = []    # items they carry, each with "for_sale" and "ask"
var traded := false
var note := ""                           # the status line shown under the budget

var _container: FurnitureTag = null

# A customer coming back to collect a job
static func for_order(o: Dictionary) -> CustomerData:
	var d := CustomerData.new()
	d.kind = "pickup"
	d.display_name = str(o["customer"])
	d.order = o
	d.greeting = "Hi, it's me again. Is it ready?"
	return d

# ---------- dialogue text ----------

func dialogue_text() -> String:
	var parts: Array[String] = []
	if not wants.is_empty():
		parts.append("I'm looking for something: %s." % ", ".join(PackedStringArray(wants)))
	for e in inventory:
		if e.get("for_sale", false):
			parts.append("I've got a few things to sell.")
			break
	if parts.is_empty():
		parts.append("Just browsing.")
	return " ".join(PackedStringArray(parts))

func offer_text() -> String:
	var days: int = offer["days"]
	var reward: int = offer["reward"]
	if offer["kind"] == "print":
		return "I need a %s 3D printed. I'll leave you the filament. Come back in %d days and I'll pay you § %d." % [offer["want_name"], days, reward]
	return "Could you restore this %s? I'll be back in %d days, and pay § %d when it's done." % [offer["give"]["name"], days, reward]

func accepted_text() -> String:
	return "Great, see you in %d days." % int(offer["days"])

func pickup_text() -> String:
	return "Is my %s ready? I'll pay § %d." % [order["want_name"], int(order["reward"])]

# The job that gets recorded when the player accepts the offer
func make_order() -> Dictionary:
	var days: int = offer["days"]
	var o := {
		"customer": display_name,
		"want_id": offer["want_id"],
		"want_name": offer["want_name"],
		"reward": offer["reward"],
		"due": GameState.day + days,
		"expires": GameState.day + days + GRACE_DAYS,
	}
	if offer.has("want_uid"):
		o["want_uid"] = offer["want_uid"]
	return o

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
	var offer_price := offer_for(entry)
	if offer_price > budget:
		return "Budget too low (§%d)" % offer_price
	return ""

# The player sold `entry` to this customer. Returns the money to pay.
func receive_sale(entry: Dictionary) -> int:
	var price := offer_for(entry)
	budget -= price
	wants = []
	entry["for_sale"] = false
	entry.erase("ask")
	entry.erase("bought")
	traded = true
	note = "Sold %s for §%d" % [entry["name"], price]
	check_done()
	return price

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
	var r := randf()
	if r < 0.2:
		if _roll_print_offer():
			return
	elif r < 0.4:
		if _roll_restore_offer():
			return
	_roll_trader()

func _roll_print_offer() -> bool:
	if not (ItemDB.defs.has("filament") and ItemDB.defs.has("plastic_toy")):
		return false
	var toy := ItemDB.make_item("plastic_toy")
	kind = "print_offer"
	greeting = "Hey! Can you 3D print something for me?"
	offer = {
		"kind": "print",
		"give": ItemDB.make_item("filament"),
		"want_id": "plastic_toy",
		"want_name": toy["name"],
		"reward": roundi(ItemDB.value_of(toy) * randf_range(2.0, 3.0)),
		"days": PRINT_DAYS,
	}
	return true

func _roll_restore_offer() -> bool:
	var picks: Array[String] = []
	for key in ItemDB.defs:
		var def: Dictionary = ItemDB.defs[key]
		if def.has("restores_to") and ItemDB.defs.has(str(def["restores_to"])):
			picks.append(str(key))
	if picks.is_empty():
		return false
	var pick := picks[randi() % picks.size()]
	var give := ItemDB.make_item(pick)
	var uid := randi()
	give["order_uid"] = uid
	var target := ItemDB.make_item(str(ItemDB.defs[pick]["restores_to"]))
	kind = "restore_offer"
	greeting = "Can you fix something for me?"
	offer = {
		"kind": "restore",
		"give": give,
		"want_id": target["id"],
		"want_name": target["name"],
		"want_uid": uid,
		"reward": roundi(ItemDB.value_of(target) * randf_range(0.6, 0.9)),
		"days": RESTORE_DAYS,
	}
	return true

func _roll_trader() -> void:
	kind = "trader"
	greeting = GREETINGS[randi() % GREETINGS.size()]
	var ids: Array = ItemDB.defs.keys()
	if ids.is_empty():
		return
	var mode := randi() % 3  # 0 = buys, 1 = sells, 2 = both
	if mode != 1:
		_roll_wants(ids)
	if mode != 0:
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
	for i in 1 + randi() % 5 + 2:
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
