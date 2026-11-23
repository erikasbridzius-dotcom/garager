class_name CustomerMenu
extends CanvasLayer

var inventory_panel: InventoryPanel
var layout_editor: LayoutEditor
var player: Node3D

var _customer: Customer = null
var _panel: PanelContainer
var _title: Label
var _info: Label
var _hands_box: VBoxContainer
var _items_grid: GridContainer

func _ready() -> void:
	layer = 2
	add_to_group("ui_blocker")
	var root := get_tree().current_scene
	inventory_panel = root.find_child("InventoryPanel", true, false) as InventoryPanel
	layout_editor = root.find_child("ShopEditor", true, false) as LayoutEditor
	player = root.find_child("Player", true, false) as Node3D
	if inventory_panel == null or layout_editor == null or player == null:
		push_error("CustomerMenu: could not find InventoryPanel, ShopEditor or Player nodes.")
		set_process(false)
		return
	_build()
	_panel.visible = false
	inventory_panel.hand_changed.connect(func(_i, _e): _refresh())
	GameState.money_changed.connect(func(_m): _refresh())

func _process(_delta: float) -> void:
	_panel.visible = _customer != null and not layout_editor.editing

func blocks_point(p: Vector2) -> bool:
	return _panel != null and _panel.visible and _panel.get_global_rect().has_point(p)

# ---------- opening and closing ----------

func open(c: Customer) -> void:
	if _customer != null and _customer != c:
		_unhook()
	_customer = c
	if not c.leaving.is_connected(_on_customer_leaving):
		c.leaving.connect(_on_customer_leaving)
	if not c.conversation_ended.is_connected(_on_customer_done):
		c.conversation_ended.connect(_on_customer_done)
	_refresh()

func close_menu() -> void:
	_unhook()
	_customer = null
	_panel.visible = false

func _unhook() -> void:
	if _customer != null and is_instance_valid(_customer):
		if _customer.leaving.is_connected(_on_customer_leaving):
			_customer.leaving.disconnect(_on_customer_leaving)
		if _customer.conversation_ended.is_connected(_on_customer_done):
			_customer.conversation_ended.disconnect(_on_customer_done)

func _on_customer_leaving() -> void:
	# Customer is leaving due to impatience (no trade happened)
	_close_and_unlean()

func _on_customer_done() -> void:
	# Customer finished being dismissed after a trade
	close_menu()

func _finish() -> void:
	# Called by "Send away" button - dismisses the customer
	var c := _customer
	_close_and_unlean()
	if c != null and is_instance_valid(c):
		c.finish_conversation()

func _close_and_unlean() -> void:
	close_menu()
	# Unlean the player when the menu is closed
	if player != null and player.get("leaning") == true:
		player.unlean()

func _cancel() -> void:
	# ESC or X button - just closes menu, customer stays
	_close_and_unlean()

# ---------- building the UI ----------

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -400.0
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

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	_panel.add_child(root_box)

	var header := HBoxContainer.new()
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_cancel)
	header.add_child(close_btn)
	root_box.add_child(header)

	_info = Label.new()
	root_box.add_child(_info)

	root_box.add_child(_section("Your hands"))
	_hands_box = VBoxContainer.new()
	root_box.add_child(_hands_box)

	root_box.add_child(_section("Customer's items"))
	_items_grid = GridContainer.new()
	root_box.add_child(_items_grid)

	var done_btn := Button.new()
	done_btn.text = "Send away"
	done_btn.pressed.connect(_on_done)
	root_box.add_child(done_btn)

func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	return l

func _row(text: String, btn: Button) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(btn)
	return h

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _tag_text(item: Dictionary) -> String:
	var tags := ", ".join(PackedStringArray(item["tags"]))
	return "%s  (worth §%d)" % [tags, ItemDB.value_of(item)]

# ---------- refreshing the content ----------

func _refresh() -> void:
	if _customer == null:
		return
	var d := _customer.data
	_title.text = d.display_name
	var wants_text := "nothing right now"
	if not d.wants.is_empty():
		wants_text = ", ".join(PackedStringArray(d.wants))
	_info.text = "Wants: %s\nBudget: § %d (you'll pay what they can afford)" % [wants_text, d.budget]

	_clear(_hands_box)
	for i in 2:
		var item: Dictionary = inventory_panel.hands[i]
		var side := "Left" if i == 0 else "Right"
		if item.is_empty():
			var empty := Label.new()
			empty.text = "%s hand: empty" % side
			_hands_box.add_child(empty)
			continue
		var offer := _offer_for(item)
		var btn := Button.new()
		if d.wants.is_empty() or not ItemDB.has_all_tags(item, d.wants):
			btn.text = "Not wanted"
			btn.disabled = true
		else:
			var pay: int = min(offer, _customer.data.budget)
			if pay < offer:
				btn.text = "Sell §%d (over budget, you keep §%d)" % [offer, _customer.data.budget]
			else:
				btn.text = "Sell §%d" % offer
			btn.pressed.connect(_sell.bind(i))
		_hands_box.add_child(_row("%s: %s\n%s" % [side, item["name"], _tag_text(item)], btn))

	_clear(_items_grid)
	if d.inventory.is_empty():
		var none := Label.new()
		none.text = "Carrying nothing"
		_items_grid.add_child(none)
	var free_hand := inventory_panel.hands[0].is_empty() or inventory_panel.hands[1].is_empty()
	for entry in d.inventory:
		var b := Button.new()
		var ask: int = entry["ask"]
		if not entry["for_sale"]:
			b.text = "Not selling"
			b.disabled = true
		elif GameState.money < ask:
			b.text = "Can't afford §%d" % ask
			b.disabled = true
		elif not free_hand:
			b.text = "Hands full"
			b.disabled = true
		else:
			b.text = "Buy §%d" % ask
			b.pressed.connect(_buy.bind(entry))
		_items_grid.add_child(_row("%s\n%s" % [entry["name"], _tag_text(entry)], b))

# ---------- trading ----------

func _offer_for(item: Dictionary) -> int:
	return roundi(ItemDB.value_of(item) * _customer.data.pay_factor)

func _sell(hand: int) -> void:
	var item: Dictionary = inventory_panel.hands[hand]
	if item.is_empty():
		return
	var offer := _offer_for(item)
	# Always attempt the sale; if over budget, player "loses out" on some money
	# but the sale still completes. Customer pays min(offer, budget) to avoid going
	# deeply negative, and the remainder is "lost".
	var pay: int = min(offer, _customer.data.budget)
	inventory_panel.take_from_hand(hand)
	GameState.add_money(pay)
	# Deduct what we could from budget; any excess was "lost"
	_customer.data.budget -= pay
	_customer.data.wants = []
	_customer.traded = true
	_after_trade()

func _buy(entry: Dictionary) -> void:
	var ask: int = entry["ask"]
	if not GameState.spend(ask):
		return
	var item := entry.duplicate()
	item.erase("for_sale")
	item.erase("ask")
	if not inventory_panel.give_to_free_hand(item):
		GameState.add_money(ask)
		return
	_customer.data.inventory.erase(entry)
	_customer.traded = true
	_after_trade()

func _after_trade() -> void:
	var d := _customer.data
	var still_selling := false
	for e in d.inventory:
		if e["for_sale"]:
			still_selling = true
	if d.wants.is_empty() and not still_selling:
		_finish()  # customer finishes being dismissed after trade
	else:
		_refresh()

func _on_done() -> void:
	if _customer != null:
		_finish()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _customer != null:
			_cancel()