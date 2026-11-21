class_name CustomerData
extends RefCounted

const NAMES := ["Ada", "Bruno", "Cato", "Dara", "Eli", "Fenna", "Gus", "Hana", "Ivo", "Juno", "Kira", "Lars"]

var display_name := "Customer"
var wants: Array = []                    # tags an item must ALL have to be wanted
var budget := 0                          # most they will spend
var pay_factor := 1.0                    # how generous they are compared to market value
var inventory: Array[Dictionary] = []    # items they carry, each with "for_sale" and "ask"

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
		inventory.append(it)
