class_name CustomerMenu
extends CanvasLayer

var inventory_panel: InventoryPanel
var layout_editor: LayoutEditor

var _customer: Customer = null
var _stage := ""   # "start" = first choices, "done" = after a decision, "trading" = trade window is open
var _panel: PanelContainer
var _title: Label
var _text: Label
var _options: VBoxContainer

func _ready() -> void:
	layer = 2
	add_to_group("ui_blocker")
	var root := get_tree().current_scene
	inventory_panel = root.find_child("InventoryPanel", true, false) as InventoryPanel
	layout_editor = root.find_child("ShopEditor", true, false) as LayoutEditor
	if inventory_panel == null or layout_editor == null:
		push_error("CustomerMenu: could not find InventoryPanel and ShopEditor nodes.")
		set_process(false)
		return
	_build()
	_panel.visible = false
	inventory_panel.hand_changed.connect(func(_i, _e): _on_hands_changed())

func _process(_delta: float) -> void:
	_panel.visible = _customer != null and _stage != "trading" and not layout_editor.editing

func blocks_point(p: Vector2) -> bool:
	return _panel != null and _panel.visible and _panel.get_global_rect().has_point(p)

# ---------- opening and closing ----------

func open(c: Customer) -> void:
	_unhook()
	_customer = c
	if not c.leaving.is_connected(_on_customer_leaving):
		c.leaving.connect(_on_customer_leaving)
	c.hush()
	_show_start()

func close_menu() -> void:
	_unhook()
	_customer = null
	_stage = ""
	if _panel != null:
		_panel.visible = false
	if inventory_panel != null:
		inventory_panel.close_customers()

func _unhook() -> void:
	if _customer != null and is_instance_valid(_customer) \
			and _customer.leaving.is_connected(_on_customer_leaving):
		_customer.leaving.disconnect(_on_customer_leaving)

func _on_customer_leaving(c: Customer) -> void:
	if c == _customer:
		_customer = null
		_stage = ""
		_panel.visible = false

func _on_hands_changed() -> void:
	if _customer != null and _stage == "start":
		_show_start()  # buttons that needed a free hand or an item may now work

# ---------- building the UI ----------

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -320.0
	_panel.offset_right = -20.0
	_panel.offset_top = 20.0
	_panel.offset_bottom = 20.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.border_color = Color(0.45, 0.45, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(270, 0)
	box.add_child(_text)

	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 4)
	box.add_child(_options)

func _opt(label: String, cb: Callable, enabled := true) -> Dictionary:
	return {"label": label, "cb": cb, "enabled": enabled}

# Shows what the customer says and the buttons to answer
func _say(text: String, options: Array) -> void:
	_title.text = _customer.data.display_name
	_text.text = text
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()
	for o in options:
		var b := Button.new()
		b.text = o["label"]
		b.disabled = not o["enabled"]
		b.pressed.connect(o["cb"])
		_options.add_child(b)

# ---------- conversations ----------

func _show_start() -> void:
	_stage = "start"
	var d := _customer.data
	if d.resolved_text != "":
		_stage = "done"
		_say(d.resolved_text, [_opt("Bye", _send_away)])
		return
	match d.kind:
		"print_offer", "restore_offer":
			_show_offer()
		"pickup":
			_show_pickup()
		_:
			_say(d.dialogue_text(), [
				_opt("Let's trade", _start_trade),
				_opt("Not today", _send_away),
			])

func _start_trade() -> void:
	_stage = "trading"
	inventory_panel.open_customer(_customer)

func _send_away() -> void:
	var d := _customer.data
	close_menu()
	d.dismissed.emit()

func _show_offer() -> void:
	var d := _customer.data
	var free := inventory_panel.hands[0].is_empty() or inventory_panel.hands[1].is_empty()
	_say(d.offer_text(), [
		_opt("Deal" if free else "Deal (free a hand first)", _accept_offer, free),
		_opt("No thanks", _send_away),
	])

func _accept_offer() -> void:
	var d := _customer.data
	if d.resolved_text != "":
		return
	var item: Dictionary = (d.offer["give"] as Dictionary).duplicate(true)
	if not inventory_panel.give_to_free_hand(item):
		return
	GameState.add_order(d.make_order())
	d.resolved_text = d.accepted_text()
	_stage = "done"
	_say(d.resolved_text, [_opt("Bye", _send_away)])
	d.finished_business.emit()  # they head out on their own after a moment

func _show_pickup() -> void:
	var d := _customer.data
	var has_it := _hand_with(d.order) >= 0
	_say(d.pickup_text(), [
		_opt("Here you go" if has_it else "Here you go (not in your hands)", _hand_over, has_it),
		_opt("Not yet", _send_away),
		_opt("Can't do it", _cancel_order),
	])

# Which hand holds what this order wants (-1 if none)
func _hand_with(o: Dictionary) -> int:
	for i in 2:
		var it: Dictionary = inventory_panel.hands[i]
		if it.is_empty():
			continue
		if str(it.get("id", "")) != str(o["want_id"]):
			continue
		if o.has("want_uid") and it.get("order_uid", -1) != o["want_uid"]:
			continue
		return i
	return -1

func _hand_over() -> void:
	var d := _customer.data
	if d.resolved_text != "":
		return
	var i := _hand_with(d.order)
	if i < 0:
		return
	inventory_panel.take_from_hand(i)
	var reward := int(d.order["reward"])
	GameState.add_money(reward)
	GameState.remove_order(d.order)
	d.resolved_text = "Perfect, thank you! Here's § %d." % reward
	_stage = "done"
	_say(d.resolved_text, [_opt("Bye", _send_away)])
	d.finished_business.emit()

func _cancel_order() -> void:
	var d := _customer.data
	if d.resolved_text != "":
		return
	GameState.remove_order(d.order)
	d.resolved_text = "Shame. I'll find someone else."
	_stage = "done"
	_say(d.resolved_text, [_opt("Bye", _send_away)])
	d.finished_business.emit()
