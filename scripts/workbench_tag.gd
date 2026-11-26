class_name WorkbenchTag
extends MachineTag

# What each bad quality tag turns into, and what the fix costs (§).
# To add a fix: add a line here. "to" is the tag the item gets instead.
const FIXES := {
	"damaged":   { "to": "undamaged",    "cost": 6,  "verb": "Repair" },
	"rusty":     { "to": "undamaged",    "cost": 5,  "verb": "Restore" },
	"makeshift": { "to": "high_quality", "cost": 15, "verb": "Upgrade" },
}

const GREY := Color(0.7, 0.72, 0.8)
const GOLD := Color(1, 0.9, 0.3)
const RED := Color(1.0, 0.55, 0.45)

func _build_sections() -> void:
	var inp := _add_section("input", "Item", Vector2i(1, 1), 4)
	var out := _add_section("output", "Result", Vector2i(1, 1), 4)
	inp.cell_scale = 2.0
	out.cell_scale = 2.0
	info_after = "input"   # the details panel sits between the two grids
	info_title = "Workbench"

# The grids are 1x1 big when empty and shrink to the size of the item inside
func _process(_delta: float) -> void:
	for slot_name in ["input", "output"]:
		var s := section(slot_name)
		if s == null:
			continue
		if s.stored.is_empty():
			s.inventory_big_cells = Vector2i(1, 1)
			s.inventory_sub = 4
		else:
			var it: Dictionary = s.stored[0]
			it["tile"] = Vector2i.ZERO
			s.inventory_big_cells = it["size"]
			s.inventory_sub = 1

func accepts(slot_name: String, _item: Dictionary) -> String:
	match slot_name:
		"input":
			if not section("input").stored.is_empty():
				return "The bench already has an item"
		"output":
			return "Take items out of here"
	return ""

func status_lines() -> Array:
	return []   # no header, the info panel says it all

# ----- the fix -----

func _item() -> Dictionary:
	var s := section("input")
	if s.stored.is_empty():
		return {}
	return s.stored[0]

# The first fixable tag on the item, or {}
func _fix_for(item: Dictionary) -> Dictionary:
	for t in item.get("tags", []):
		if FIXES.has(str(t)):
			var f: Dictionary = (FIXES[str(t)] as Dictionary).duplicate()
			f["from"] = str(t)
			return f
	return {}

# What the item becomes (without changing the original)
func _result_of(item: Dictionary, fix: Dictionary) -> Dictionary:
	var def: Dictionary = ItemDB.defs.get(str(item["id"]), {})
	var res: Dictionary
	if def.has("restores_to") and str(fix["to"]) == "undamaged":
		res = ItemDB.make_item(str(def["restores_to"]))
		for k in ["bought", "order_uid"]:
			if item.has(k):
				res[k] = item[k]
	else:
		res = item.duplicate(true)
		var tags: Array = res["tags"]
		tags.erase(fix["from"])
		if not tags.has(fix["to"]):
			tags.append(fix["to"])
	return res

# "" if the fix can go ahead, otherwise why not
func _problem() -> String:
	var item := _item()
	if item.is_empty():
		return "Place an item first"
	var fix := _fix_for(item)
	if fix.is_empty():
		return "Nothing to fix"
	if not section("output").stored.is_empty():
		return "Take the result out first"
	if GameState.money < int(fix["cost"]):
		return "Need § %d" % int(fix["cost"])
	return ""

func info_lines() -> Array:
	var item := _item()
	if item.is_empty():
		return [["Drop a damaged, rusty", GREY], ["or makeshift item on", GREY], ["the left to fix it.", GREY]]
	var lines: Array = [[str(item["name"]), Color.WHITE]]
	var fix := _fix_for(item)
	if fix.is_empty():
		lines.append(["Nothing to repair", GREY])
		lines.append(["or upgrade.", GREY])
		return lines
	var res := _result_of(item, fix)
	lines.append(["%s -> %s" % [str(fix["from"]).capitalize(), str(fix["to"]).capitalize()], GREY])
	lines.append(["Cost: § %d" % int(fix["cost"]), GOLD])
	lines.append(["Value: § %d -> § %d" % [ItemDB.value_of(item), ItemDB.value_of(res)], GOLD])
	var why := _problem()
	if why != "":
		lines.append([why, RED])
	return lines

func action_label() -> String:
	var fix := _fix_for(_item())
	if _item().is_empty() or fix.is_empty():
		return ""
	return str(fix["verb"])

func action_enabled() -> bool:
	return _problem() == ""

func on_action() -> void:
	if _problem() != "":
		return
	var item := _item()
	var fix := _fix_for(item)
	var res := _result_of(item, fix)
	GameState.spend(int(fix["cost"]))
	section("input").stored.clear()
	section("output").try_place(res)
