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
]

const NO_EVENT_CHANCE := 0.3
const TWO_EVENT_CHANCE := 0.2

const RENT_START := 60        # the first rent payment
const RENT_INTERVAL := 7      # rent is due every this many days
const RENT_GROWTH := 0.06     # the rent goes up by this much after every payment

var money := 100:
	set(value):
		money = value
		money_changed.emit(money)

var day := 1:
	set(value):
		day = value
		day_changed.emit(day)

var today_events: Array = []
var event_log: Dictionary = {}    # day -> the events of that day

# Today's money movements (reset every morning)
var earned_today := 0
var spent_today := 0
var rent_paid_today := 0

var rent := RENT_START            # the next rent payment
var next_rent_day := RENT_INTERVAL
var rent_history: Dictionary = {} # day -> rent paid that day

# Jobs customers have given the player: they come back to collect them
# Each: {customer, want_id, want_name, want_uid (optional), reward, due, expires}
var orders: Array = []

func add_money(amount: int) -> void:
	if amount > 0:
		earned_today += amount
	money += amount

func can_afford(cost: int) -> bool:
	return money >= cost

func spend(cost: int) -> bool:
	if money < cost:
		return false
	spent_today += cost
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

# The rent paid (past) or expected (future) on a day. 0 if it isn't a rent day.
func rent_on(d: int) -> int:
	if rent_history.has(d):
		return int(rent_history[d])
	if d < next_rent_day or (d - next_rent_day) % RENT_INTERVAL != 0:
		return 0
	@warning_ignore("integer_division")
	var payments_ahead: int = (d - next_rent_day) / RENT_INTERVAL
	var amount := rent
	for i in payments_ahead:
		amount = ceili(amount * (1.0 + RENT_GROWTH))
	return amount

func _pay_rent() -> void:
	var amount := rent
	rent_history[day] = amount
	rent_paid_today = amount
	money -= amount            # can go below zero
	rent = ceili(rent * (1.0 + RENT_GROWTH))
	next_rent_day += RENT_INTERVAL

func next_day() -> void:
	earned_today = 0
	spent_today = 0
	rent_paid_today = 0
	roll_events()
	day += 1
	event_log[day] = today_events.duplicate()
	var alive: Array = []
	for o in orders:
		if int(o["expires"]) >= day:
			alive.append(o)
	orders = alive
	if day >= next_rent_day:
		_pay_rent()
