class_name ShopManager
extends Node

signal shop_opened
signal shop_closed

enum State { CLOSED, OPENING, OPEN, CLOSING }

@export var shutter: Shutter
@export var entrance: Marker3D
@export var counter_spot: Marker3D
@export var open_button: InteractTag
@export var layout_editor: LayoutEditor
@export var customer_menu: CustomerMenu
@export var customers_per_day := 3
@export var arrival_delay := 2.0

var state := State.CLOSED

func _ready() -> void:
	var root := get_tree().current_scene
	if shutter == null:
		shutter = root.find_child("Shutter", true, false) as Shutter
	if entrance == null:
		entrance = root.find_child("Entrance", true, false) as Marker3D
	if counter_spot == null:
		counter_spot = root.find_child("CounterSpot", true, false) as Marker3D
	if open_button == null:
		open_button = root.find_child("OpenShopTag", true, false) as InteractTag
	if layout_editor == null:
		layout_editor = root.find_child("ShopEditor", true, false) as LayoutEditor
	if customer_menu == null:
		customer_menu = root.find_child("CustomerMenu", true, false) as CustomerMenu
	if shutter == null or entrance == null or counter_spot == null or open_button == null \
			or layout_editor == null or customer_menu == null:
		push_error("ShopManager: missing Shutter, Entrance, CounterSpot, OpenShopTag, ShopEditor or CustomerMenu.")
		return
	open_button.prompt = "Open shop"
	open_button.interacted.connect(open_shop)

func open_shop() -> void:
	if state != State.CLOSED:
		return
	state = State.OPENING
	open_button.enabled = false
	layout_editor.locked = true
	shutter.open()
	await shutter.finished
	state = State.OPEN
	shop_opened.emit()
	await _run_day()
	await _close_shop()

func _run_day() -> void:
	for i in customers_per_day:
		await get_tree().create_timer(arrival_delay).timeout
		var c := Customer.new()
		c.data = CustomerData.new()
		c.data.roll()
		c.entrance_pos = entrance.global_position
		c.spot_pos = counter_spot.global_position
		c.clicked.connect(customer_menu.open)
		get_tree().current_scene.add_child(c)
		c.walk_in()
		await c.finished

func _close_shop() -> void:
	state = State.CLOSING
	customer_menu.close_menu()
	shutter.close()
	await shutter.finished
	GameState.next_day()
	state = State.CLOSED
	layout_editor.locked = false
	open_button.enabled = true
	shop_closed.emit()
