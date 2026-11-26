class_name ShopManager
extends Node

signal shop_opened
signal shop_closed

# CLOSED = ready to open, OPEN = customers coming, WAITING_CLOSE = last customer gone, shutter still open,
# NIGHT = shutter closed, furniture unlocked, waiting for the player to start the next day
enum State { CLOSED, OPENING, OPEN, WAITING_CLOSE, CLOSING, NIGHT, STARTING }

@export var shutter: Shutter
@export var entrance: Marker3D
@export var counter_spot: Marker3D
@export var open_button: InteractTag
@export var layout_editor: LayoutEditor
@export var customer_menu: CustomerMenu
@export var customers_per_day := 3
@export var arrival_delay := 2.0

var state := State.CLOSED
var day_card: DayCard

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
	day_card = DayCard.new()
	add_child(day_card)
	open_button.interacted.connect(_on_button)
	_set_state(State.CLOSED)

# The button's prompt and availability follow the state
func _set_state(s: State) -> void:
	state = s
	match s:
		State.CLOSED:
			open_button.prompt = "Open shop"
			open_button.enabled = true
		State.WAITING_CLOSE:
			open_button.prompt = "Close shop"
			open_button.enabled = true
		State.NIGHT:
			open_button.prompt = "Start next day"
			open_button.enabled = true
		_:
			open_button.enabled = false

func _on_button() -> void:
	match state:
		State.CLOSED:
			await _open_shop()
		State.WAITING_CLOSE:
			await _close_shop()
		State.NIGHT:
			await _start_next_day()

func _open_shop() -> void:
	_set_state(State.OPENING)
	layout_editor.locked = true
	shutter.open()
	await shutter.finished
	_set_state(State.OPEN)
	shop_opened.emit()
	await _run_day()
	customer_menu.close_menu()
	_set_state(State.WAITING_CLOSE)  # shutter stays open until the player closes it

func _run_day() -> void:
	var queue: Array[CustomerData] = []
	for o in GameState.orders_due():
		queue.append(CustomerData.for_order(o))
	for i in customers_per_day:
		var d := CustomerData.new()
		d.roll()
		queue.append(d)
	for d in queue:
		await get_tree().create_timer(arrival_delay).timeout
		var c := Customer.new()
		c.data = d
		c.entrance_pos = entrance.global_position
		c.spot_pos = counter_spot.global_position
		c.clicked.connect(customer_menu.open)
		get_tree().current_scene.add_child(c)
		c.walk_in()
		await c.finished

func _close_shop() -> void:
	_set_state(State.CLOSING)
	shutter.close()
	await shutter.finished
	layout_editor.locked = false  # furniture can be moved now
	_set_state(State.NIGHT)
	shop_closed.emit()

func _start_next_day() -> void:
	_set_state(State.STARTING)
	GameState.next_day()  # new events are rolled and machines do their daily work
	var player := get_tree().current_scene.find_child("Player", true, false)
	if player != null:
		player.set("busy", true)
	await day_card.show_day(GameState.day, GameState.today_events)
	if player != null:
		player.set("busy", false)
	_set_state(State.CLOSED)
