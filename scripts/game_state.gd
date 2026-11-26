extends Node

signal money_changed(amount: int)
signal day_changed(day: int)

var money := 100:
	set(value):
		money = value
		money_changed.emit(money)

var day := 1:
	set(value):
		day = value
		day_changed.emit(day)

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

func next_day() -> void:
	day += 1
	var alive: Array = []
	for o in orders:
		if int(o["expires"]) >= day:
			alive.append(o)
	orders = alive
