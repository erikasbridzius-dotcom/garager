class_name PrinterTag
extends MachineTag

const BATTERY_USE := 6        # % of battery used for each day of printing
const PROGRESS_PER_DAY := 25  # progress the printer makes each day
# To print something else: add a recipe. "work" above 25 makes the print take several days.
const RECIPES := [
	{ "output": "plastic_toy", "needs": "filament", "work": 25 },
]

var job: Dictionary = {}          # {"recipe": index, "progress": n}; empty = idle
var _waiting: Dictionary = {}     # a finished print waiting for room in the output

func _build_sections() -> void:
	_add_section("input", "Input", Vector2i(3, 2), 4)
	_add_section("output", "Output", Vector2i(3, 2), 4)
	_add_section("upgrades", "Upgrades", Vector2i(2, 2), 4)
	var bat := _add_section("battery", "Battery", Vector2i(1, 1), 2)
	bat.cell_scale = 2.0

func accepts(slot_name: String, item: Dictionary) -> String:
	match slot_name:
		"battery":
			if str(item.get("id", "")) != "battery":
				return "Needs a battery"
			if not section("battery").stored.is_empty():
				return "Already has a battery"
		"input":
			var ok := false
			for r in RECIPES:
				if str(r["needs"]) == str(item.get("id", "")):
					ok = true
			if not ok:
				return "The printer can't use that"
		"output":
			return "Output only"
		"upgrades":
			if not (item.get("tags", []) as Array).has("upgrade"):
				return "Not an upgrade module"
	return ""

func process_day() -> void:
	if not _waiting.is_empty():
		if section("output").try_place(_waiting):
			_waiting = {}
		else:
			status = "Output is full"
			return
	var bat := _battery()
	if bat.is_empty():
		status = "No battery"
		return
	if int(bat.get("charge", 100)) < BATTERY_USE:
		status = "Battery too low"
		return
	if job.is_empty() and not _start_job():
		status = "Needs filament"
		return
	var recipe: Dictionary = RECIPES[int(job["recipe"])]
	job["progress"] = int(job["progress"]) + PROGRESS_PER_DAY
	bat["charge"] = maxi(0, int(bat.get("charge", 100)) - BATTERY_USE)
	if int(job["progress"]) >= int(recipe["work"]):
		var item := ItemDB.make_item(str(recipe["output"]))
		job = {}
		if section("output").try_place(item):
			status = "Printed %s" % item["name"]
		else:
			_waiting = item
			status = "Output is full"
	else:
		status = "Printing... (%d/%d)" % [int(job["progress"]), int(recipe["work"])]

func _battery() -> Dictionary:
	var s := section("battery")
	if s.stored.is_empty():
		return {}
	return s.stored[0]

# Uses up one filament spool and starts a job. False if there is nothing to print.
func _start_job() -> bool:
	var inp := section("input")
	for i in RECIPES.size():
		for idx in inp.stored.size():
			if str(inp.stored[idx].get("id", "")) == str(RECIPES[i]["needs"]):
				inp.stored.remove_at(idx)
				job = {"recipe": i, "progress": 0}
				return true
	return false

func status_lines() -> Array:
	var l1 := "Idle"
	if not job.is_empty():
		var r: Dictionary = RECIPES[int(job["recipe"])]
		l1 = "Printing: %s  %d/%d" % [ItemDB.make_item(str(r["output"]))["name"], int(job["progress"]), int(r["work"])]
	var bat := _battery()
	var l2 := "Battery: none"
	if not bat.is_empty():
		l2 = "Battery: %d%%" % int(bat.get("charge", 100))
	return [l1, l2, status]
