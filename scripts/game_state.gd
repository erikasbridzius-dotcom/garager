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

func add_money(amount: int) -> void:
	money += amount

func can_afford(cost: int) -> bool:
	return money >= cost

func spend(cost: int) -> bool:
	if money < cost:
		return false
	money -= cost
	return true

func next_day() -> void:
	day += 1
