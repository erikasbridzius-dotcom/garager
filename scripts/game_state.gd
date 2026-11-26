extends Node

signal money_changed(amount: int)
signal day_changed(day: int)

# A day's events change prices of items with a tag. mult above 1 = more expensive.
# To add an event: add a line here.
const EVENTS := [
	{ "id": "weapon_rumour", "title": "Rumour: raiders nearby", "text": "Weapons sell for more today.", "tag": "weapon", "mult": 1.5 },
	{ "id": "food_surplus", "title": "Food surplus", "text": "Food is cheap today.", "tag": "food", "mult": 0.7 },
	{ "id": "food_deficit", "title": "Food shortage", "text": "Food is scarce and expensive today.", "tag": "food", "mult": 1.5 },
	{ "id": "water_surplus", "title": "Water surplus", "text": "Water is cheap today.", "tag": "drink", "mult": 0.7 },
	{ "id": "water_deficit", "title": "Water shortage", "text": "Water is scarce and expensive today.", "tag": "drink", "mult": 1.5 },
	{ "id": "material_surplus", "title": "Material surplus", "text": "Materials are cheap today.", "tag": "material", "mult": 0.7 },
	{ "id": "material_deficit", "title": "Material shortage", "text": "Materials are scarce and expensive today.", "tag": "material", "mult": 1.5 },
	{ "id": "medical_surplus", "title": "Medical surplus", "text": "Melical items are cheap today.", "tag": "medical", "mult": 0.7 },
	{ "id": "medical_deficit", "title": "Medical shortage", "text": "Medical items are scarce and expensive today.", "tag": "medical", "mult": 1.5 },
]

const NO_EVENT_CHANCE := 0.3
const TWO_EVENT_CHANCE := 0.2

var money := 100:
	set(value):
		money = value
		money_changed.emit(money)

var day := 1:
	set(value):
		day = value
		day_changed.emit(day)

var today_events: Array = []

# Jobs customers have given the player: they come back to collect them
# Each: {customer, want_id, want_name, want_uid (optional), reward, due, expires}
var orders: Array = []

func add_money(amount: int) -> void:
	money += amount

func can_afford(cost: int) -> bool:
	return money >= cost

func spend(cost: int) -> bool:
	if money < cost:
		return false
	money -= cost
	return true

func add_order(o: Dictionary) -> void:
	orders.append(o)

func remove_order(o: Dictionary) -> void:
	orders.erase(o)

# Orders whose customer should come back today
func orders_due() -> Array:
	var list: Array = []
	for o in orders:
		if day >= int(o["due"]) and day <= int(o["expires"]):
			list.append(o)
	return list

# How much today's events change the price of an item with these tags
func event_multiplier(tags: Array) -> float:
	var m := 1.0
	for e in today_events:
		if tags.has(e["tag"]):
			m *= float(e["mult"])
	return m

func roll_events() -> void:
	today_events = []
	if randf() < NO_EVENT_CHANCE:
		return
	var pool := EVENTS.duplicate()
	pool.shuffle()
	var count := 2 if randf() < TWO_EVENT_CHANCE else 1
	var used_tags: Array = []
	for e in pool:
		if used_tags.has(e["tag"]):
			continue
		today_events.append(e)
		used_tags.append(e["tag"])
		if today_events.size() >= count:
			break

func next_day() -> void:
	roll_events()
	day += 1
	var alive: Array = []
	for o in orders:
		if int(o["expires"]) >= day:
			alive.append(o)
	orders = alive
