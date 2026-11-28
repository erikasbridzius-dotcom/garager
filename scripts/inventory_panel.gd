class_name InventoryPanel
extends Control

signal all_closed
signal hand_changed(index: int, entry: Dictionary)  # index 0 = left hand, 1 = right hand

const PAD := 14.0
const TITLE_H := 34.0
const HEADER_H := 60.0   # extra space under the title for header lines (customers, machines)
const LABEL_H := 18.0    # section label above each part of a machine window
const PART_GAP := 12.0
const MIN_W := 110.0
const HAND_ZONE_H := 90.0
const WHOLESALE_H := 30.0   # extra height for the "Buy it all" button in a customer's window

# One grid inside a window. A shelf or customer window has one; a machine window has several.
class Part:
	var tag: FurnitureTag = null   # null for the info panel of a machine
	var is_info := false
	var row := 0
	var off := Vector2.ZERO   # top-left of this part, relative to the window's grid origin
	var cp := 28.0            # pixels per small cell
	var size := Vector2.ZERO  # info panel only

class Win:
	var tag: FurnitureTag = null     # shelf / customer window: its container (null for machines)
	var machine: MachineTag = null   # machine window: the machine
	var title := ""
	var pos := Vector2.ZERO
	var content := Vector2.ZERO      # size of the grid area
	var parts: Array[Part] = []

var windows: Array[Win] = []
var hands: Array[Dictionary] = [{}, {}]

var show_hands := true:
	set(value):
		if value != show_hands:
			show_hands = value
			queue_redraw()

var _drag_win: Win = null
var _drag_off := Vector2.ZERO

var _held: Dictionary = {}
var _held_src: FurnitureTag = null   # the container it came from (null if it came from a hand)
var _held_src_hand := -1             # the hand it came from (-1 if it came from a container)
var _held_src_tile := Vector2i.ZERO
var _held_src_size := Vector2i.ONE
var _held_off := Vector2i.ZERO

var _tip_on := false
var _toast := ""
var _toast_t := 0.0

# ---------- public API ----------

func has_windows() -> bool:
	return not windows.is_empty()

func take_from_hand(i: int) -> Dictionary:
	var item := hands[i]
	hands[i] = {}
	hand_changed.emit(i, hands[i])
	queue_redraw()
	return item

func give_to_free_hand(entry: Dictionary) -> bool:
	for i in 2:
		if hands[i].is_empty():
			entry["tile"] = Vector2i.ZERO
			hands[i] = entry
			hand_changed.emit(i, entry)
			queue_redraw()
			return true
	return false

# True when both hands are empty
func can_carry_box() -> bool:
	return hands[0].is_empty() and hands[1].is_empty()

# The stand-in that fills the second hand while a two-handed item is carried
func _ghost() -> Dictionary:
	return {"ghost": true, "name": "", "size": Vector2i.ONE, "color": Color.WHITE,
		"tags": [], "price": 0, "tile": Vector2i.ZERO}

# Both hands now carry a wholesale box holding these items
func carry_box(items: Array[Dictionary]) -> bool:
	if not can_carry_box():
		return false
	var contents: Array = []
	for it in items:
		contents.append(it)
	hands[0] = {"is_box": true, "two_handed": true, "name": "Wholesale Box", "size": Vector2i(3, 2),
		"color": Color(0.55, 0.4, 0.22), "tags": [], "price": 0, "tile": Vector2i.ZERO, "contents": contents}
	hands[1] = _ghost()
	hand_changed.emit(0, hands[0])
	hand_changed.emit(1, hands[1])
	queue_redraw()
	return true

# Right-click: unpack a box that sits in a shelf
func _on_right_click(p: Vector2) -> void:
	var w := _win_at(p)
	if w != null:
		var part := _part_at(w, p)
		if part != null:
			var idx := _entry_at(part.tag, _cell_in(w, part, p))
			if idx >= 0 and part.tag.stored[idx].get("is_box", false):
				_try_unpack(part.tag, idx)
		return
	if show_hands:
		var hi := _hand_at(p)
		if hi >= 0 and hands[hi].get("is_box", false):
			_flash("Put the box on a shelf, then right-click it to unpack")

func _bigger_first(a: Dictionary, b: Dictionary) -> bool:
	var sa: Vector2i = a["size"]
	var sb: Vector2i = b["size"]
	return sa.x * sa.y > sb.x * sb.y

# Moves everything in the box into the shelf, but only if all of it fits
func _try_unpack(tag: FurnitureTag, idx: int) -> void:
	var box: Dictionary = tag.stored[idx]
	var contents: Array = box.get("contents", [])
	var cells := tag.inventory_cells()
	var occupied: Array[Rect2i] = []
	for i in tag.stored.size():
		if i == idx:
			continue   # the box's own space will be free
		var e: Dictionary = tag.stored[i]
		occupied.append(Rect2i(e["tile"], e["size"]))
	var order := contents.duplicate()
	order.sort_custom(_bigger_first)
	var spots: Array[Rect2i] = []
	var missing := 0
	for it in order:
		var r := _find_spot(occupied, cells, it["size"])
		if r.size == Vector2i.ZERO:
			missing += 1
		else:
			occupied.append(r)
		spots.append(r)
	if missing > 0:
		_flash("Not enough room: %d of %d items won't fit" % [missing, order.size()])
		return
	tag.stored.remove_at(idx)
	for i in order.size():
		var item: Dictionary = order[i]
		item["tile"] = spots[i].position
		item["size"] = spots[i].size
		tag.stored.append(item)
	_flash("Unpacked %d items" % order.size())
	queue_redraw()

# First free spot for an item of size s (tries it rotated too). Returns an empty Rect2i if none.
func _find_spot(occupied: Array[Rect2i], cells: Vector2i, s: Vector2i) -> Rect2i:
	for rotated in [false, true]:
		var sz := Vector2i(s.y, s.x) if rotated else s
		for y in cells.y:
			for x in cells.x:
				if x + sz.x > cells.x or y + sz.y > cells.y:
					continue
				var r := Rect2i(Vector2i(x, y), sz)
				var clash := false
				for o in occupied:
					if o.intersects(r):
						clash = true
						break
				if not clash:
					return r
	return Rect2i()

# ----- wholesale button in a customer's trade window -----

func _wholesale_on(w: Win) -> bool:
	var t := _trader(w)
	return t != null and t.offers_wholesale and not t.wholesale_items().is_empty()

func _wholesale_rect(w: Win) -> Rect2:
	var b := _box(w)
	var y := b.position.y + PAD * 0.5 + TITLE_H + 2.0 + HEADER_H + 2.0
	return Rect2(b.position.x + PAD, y, b.size.x - PAD * 2.0, 24.0)

func _wholesale_problem(t: CustomerData) -> String:
	if not can_carry_box():
		return "need both hands"
	if GameState.money < t.wholesale_cost():
		return "can't afford"
	return ""

func _buy_wholesale(t: CustomerData) -> void:
	var why := _wholesale_problem(t)
	if why != "":
		t.note = "Can't: " + why
		queue_redraw()
		return
	GameState.spend(t.wholesale_cost())
	carry_box(t.take_wholesale())
	t.traded = true
	t.note = "You bought the whole lot"
	t.resolved_text = "Pleasure doing business. Mind the box, it's heavy."
	t.finished_business.emit()
	queue_redraw()

func blocks_point(p: Vector2) -> bool:
	if not _held.is_empty() or _drag_win != null or _win_at(p) != null:
		return true
	return show_hands and _hand_at(p) >= 0

# Only claim mouse events over a window or an occupied hand slot, so everything else passes through
func _has_point(point: Vector2) -> bool:
	return blocks_point(point)

# What the player clicked on in the world: machines open one big window, shelves a simple one
func open_furniture(t: FurnitureTag) -> void:
	if t is MachineTag:
		open_machine(t as MachineTag)
	else:
		open(t)

func open(t: FurnitureTag) -> void:
	for existing in windows:
		if existing.tag == t:
			_bring_to_front(existing)
			queue_redraw()
			return
	var w := Win.new()
	w.tag = t
	w.title = t.get_display_name()
	var part := Part.new()
	part.tag = t
	var cells := t.inventory_cells()
	var head := HEADER_H if t.has_header() else 0.0
	var fit_h := (size.y * 0.8 - PAD * 2.0 - TITLE_H - head) / cells.y
	var fit_w := (size.x * 0.4 - PAD * 2.0) / cells.x
	part.cp = clampf(floorf(minf(fit_h, fit_w)), 12.0, 36.0)
	w.parts.append(part)
	w.content = Vector2(cells) * part.cp
	var b := _box(w)
	w.pos = (size - b.size) / 2.0 + Vector2(30, 30) * windows.size()
	_clamp_pos(w)
	windows.append(w)
	queue_redraw()

func open_machine(m: MachineTag) -> void:
	for ex in windows:
		if ex.machine == m:
			_bring_to_front(ex)
			queue_redraw()
			return
	var w := Win.new()
	w.machine = m
	w.title = m.get_display_name()
	for s in m.sections:
		var part := Part.new()
		part.tag = s
		part.row = s.layout_row
		w.parts.append(part)
		if m.info_after != "" and s.slot == m.info_after:
			var info := Part.new()
			info.is_info = true
			info.row = s.layout_row
			w.parts.append(info)
	_fit_machine(w)
	w.pos = (size - _box(w).size) / 2.0 + Vector2(30, 30) * windows.size()
	_clamp_pos(w)
	windows.append(w)
	queue_redraw()

# Use the biggest cell size that still fits the screen
func _fit_machine(w: Win) -> void:
	var cp := 22.0
	while cp > 8.0:
		_layout_machine(w, cp)
		var b := _box(w)
		if b.size.x <= size.x - 16.0 and b.size.y <= size.y - 16.0:
			break
		cp -= 1.0

const INFO_W := 170.0
const INFO_MIN_H := 150.0

# Arranges a machine's parts in rows (parts with the same row sit side by side)
func _layout_machine(w: Win, cp: float) -> void:
	var row_ids: Array[int] = []
	for part in w.parts:
		if not row_ids.has(part.row):
			row_ids.append(part.row)
	row_ids.sort()
	var y := 0.0
	var max_w := 0.0
	for r in row_ids:
		var grid_h := 0.0
		for part in w.parts:
			if part.row != r or part.is_info:
				continue
			part.cp = cp * part.tag.cell_scale
			part.size = Vector2(part.tag.inventory_cells()) * part.cp
			grid_h = maxf(grid_h, part.size.y)
		var x := 0.0
		var row_h := 0.0
		for part in w.parts:
			if part.row != r:
				continue
			if part.is_info:
				part.size = Vector2(INFO_W, maxf(grid_h, INFO_MIN_H))
			part.off = Vector2(x, y + LABEL_H)
			x += part.size.x + PART_GAP
			row_h = maxf(row_h, part.size.y + LABEL_H)
		max_w = maxf(max_w, x - PART_GAP)
		y += row_h + PART_GAP
	w.content = Vector2(max_w, y - PART_GAP)

func open_customer(c: Customer) -> void:
	open(c.data.container())
	if not c.leaving.is_connected(_on_customer_leaving):
		c.leaving.connect(_on_customer_leaving)

func _on_customer_leaving(c: Customer) -> void:
	for w in windows.duplicate():
		if w.tag != null and w.tag.trader == c.data:
			if not _held.is_empty() and _held_src == w.tag:
				_return_held()
				_held = {}
			close_window(w)

func close_customers() -> void:
	for w in windows.duplicate():
		if _trader(w) != null:
			close_window(w)

func close_window(w: Win) -> void:
	windows.erase(w)
	if windows.is_empty():
		all_closed.emit()
	queue_redraw()

func close_all() -> void:
	var had := not windows.is_empty()
	if not _held.is_empty():
		_return_held()
		_held = {}
	windows.clear()
	if had:
		all_closed.emit()
	queue_redraw()

# ---------- geometry ----------

func _trader(w: Win) -> CustomerData:
	if w.tag != null:
		return w.tag.trader
	return null

func _has_header(w: Win) -> bool:
	if w.machine != null:
		return not w.machine.status_lines().is_empty()
	return w.tag != null and w.tag.has_header()

func _header_lines(w: Win) -> Array:
	if w.machine != null:
		return w.machine.status_lines()
	if w.tag != null:
		return w.tag.header_lines()
	return []

func _header_h(w: Win) -> float:
	var h := HEADER_H if _has_header(w) else 0.0
	if _wholesale_on(w):
		h += WHOLESALE_H
	return h

func _box(w: Win) -> Rect2:
	var width := maxf(w.content.x + PAD * 2.0, MIN_W)
	return Rect2(w.pos, Vector2(width, w.content.y + PAD * 2.0 + TITLE_H + _header_h(w)))

func _grid_origin(w: Win) -> Vector2:
	return w.pos + Vector2(PAD, PAD + TITLE_H + _header_h(w))

func _part_origin(w: Win, part: Part) -> Vector2:
	return _grid_origin(w) + part.off

func _close_rect(w: Win) -> Rect2:
	var b := _box(w)
	return Rect2(b.end.x - 28.0, b.position.y + 6.0, 22.0, 22.0)

func _dismiss_rect(w: Win) -> Rect2:
	var b := _box(w)
	return Rect2(b.end.x - 28.0 - 88.0, b.position.y + 6.0, 82.0, 22.0)

func _title_rect(w: Win) -> Rect2:
	var b := _box(w)
	return Rect2(b.position, Vector2(b.size.x, PAD + TITLE_H + _header_h(w)))

func _hand_slot_rect(i: int) -> Rect2:
	var x := 30.0 if i == 0 else size.x - 30.0 - 90.0
	return Rect2(x, size.y - 100.0, 90.0, 90.0)

func _middle_slot_rect() -> Rect2:
	return Rect2((size.x - 130.0) / 2.0, size.y - 100.0, 130.0, 90.0)

func _hand_at(p: Vector2) -> int:
	if hands[0].get("two_handed", false):
		return 0 if _middle_slot_rect().has_point(p) else -1
	for i in 2:
		if not hands[i].is_empty() and _hand_slot_rect(i).has_point(p):
			return i
	return -1

func _in_hand_zone(p: Vector2) -> bool:
	return p.y >= size.y - HAND_ZONE_H

# Which hand receives an item dropped at p: the side you drop on, else the free one
func _target_hand(p: Vector2) -> int:
	var pref := 0 if p.x < size.x / 2.0 else 1
	if hands[pref].is_empty():
		return pref
	var other := 1 - pref
	if hands[other].is_empty():
		return other
	return -1

func _clamp_pos(w: Win) -> void:
	var b := _box(w)
	w.pos.x = clampf(w.pos.x, 0.0, maxf(0.0, size.x - b.size.x))
	w.pos.y = clampf(w.pos.y, 0.0, maxf(0.0, size.y - b.size.y))

func _win_at(p: Vector2) -> Win:
	for i in range(windows.size() - 1, -1, -1):
		if _box(windows[i]).has_point(p):
			return windows[i]
	return null

# Which grid of the window is under p (null if none)
func _part_at(w: Win, p: Vector2) -> Part:
	for part in w.parts:
		if part.is_info:
			continue
		var r := Rect2(_part_origin(w, part), Vector2(part.tag.inventory_cells()) * part.cp)
		if r.has_point(p):
			return part
	return null

func _action_rect(w: Win, part: Part) -> Rect2:
	var o := _part_origin(w, part)
	return Rect2(o.x, o.y + part.size.y - 28.0, part.size.x, 28.0)

func _bring_to_front(w: Win) -> void:
	windows.erase(w)
	windows.append(w)

func _cell_in(w: Win, part: Part, p: Vector2) -> Vector2i:
	var q := (p - _part_origin(w, part)) / part.cp
	return Vector2i(floori(q.x), floori(q.y))

func _in_grid(part: Part, cell: Vector2i) -> bool:
	var c := part.tag.inventory_cells()
	return cell.x >= 0 and cell.y >= 0 and cell.x < c.x and cell.y < c.y

func _entry_at(tag: FurnitureTag, cell: Vector2i) -> int:
	for i in range(tag.stored.size() - 1, -1, -1):
		var e: Dictionary = tag.stored[i]
		var t: Vector2i = e["tile"]
		var s: Vector2i = e["size"]
		if Rect2i(t, s).has_point(cell):
			return i
	return -1

func _fits(tag: FurnitureTag, tile: Vector2i, isize: Vector2i) -> bool:
	var c := tag.inventory_cells()
	if tile.x < 0 or tile.y < 0 or tile.x + isize.x > c.x or tile.y + isize.y > c.y:
		return false
	var r := Rect2i(tile, isize)
	for e in tag.stored:
		var t: Vector2i = e["tile"]
		var s: Vector2i = e["size"]
		if Rect2i(t, s).intersects(r):
			return false
	return true

# ---------- trading and machine rules ----------

# Returns "" if putting the held item into dest (null = a hand) is allowed, else the reason why not
func _trade_check(dest: FurnitureTag) -> String:
	if _held.get("is_box", false) and dest != null and (dest.trader != null or dest.machine != null):
		return "Boxes only go on shelves"
	if dest != null and dest.machine != null:
		var why := dest.machine.accepts(dest.slot, _held)
		if why != "":
			return why
	var src_trader: CustomerData = _held_src.trader if _held_src != null else null
	var dst_trader: CustomerData = dest.trader if dest != null else null
	if src_trader == dst_trader:
		return ""  # no customer involved, or just moving things around in the customer's own bag
	if src_trader != null and dst_trader != null:
		return "Finish with one customer first"
	if src_trader != null:
		var ask: int = _held.get("ask", 0)
		if GameState.money < ask:
			return "Can't afford § %d" % ask
		return ""
	return dst_trader.sale_problem(_held)

func _trade_commit(dest: FurnitureTag) -> void:
	var src_trader: CustomerData = _held_src.trader if _held_src != null else null
	var dst_trader: CustomerData = dest.trader if dest != null else null
	if src_trader == dst_trader:
		return
	if src_trader != null:
		var ask: int = _held.get("ask", 0)
		GameState.spend(ask)
		src_trader.complete_purchase(_held)
	elif dst_trader != null:
		GameState.add_money(dst_trader.receive_sale(_held))

func _say(reason: String, dest: FurnitureTag) -> void:
	var trd: CustomerData = null
	if dest != null and dest.trader != null:
		trd = dest.trader
	elif _held_src != null and _held_src.trader != null:
		trd = _held_src.trader
	if trd != null:
		trd.note = reason
	else:
		_flash(reason)

func _flash(text: String) -> void:
	_toast = text
	_toast_t = 2.0
	queue_redraw()

# ---------- input ----------

func _process(delta: float) -> void:
		# machine windows follow their sections' size (the workbench grids grow to fit an item)
	for w in windows:
		if w.machine != null:
			_fit_machine(w)
			_clamp_pos(w)
	if _toast_t > 0.0:
		_toast_t -= delta
		queue_redraw()
	# keeps the tooltip from sticking when the mouse leaves a window
	var on := not _hover_entry(get_local_mouse_position()).is_empty()
	if on or _tip_on:
		queue_redraw()
	_tip_on = on

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(mb.position)
			else:
				_on_release(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not _held.is_empty():
				_return_held()
				_held = {}
				queue_redraw()
			else:
				_on_right_click(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_win != null:
			_drag_win.pos = mm.position - _drag_off
			_clamp_pos(_drag_win)
		queue_redraw()

func _on_press(p: Vector2) -> void:
	var w := _win_at(p)
	if w == null:
		# No window here: maybe the player is taking an item out of a hand
		var hi := _hand_at(p) if show_hands else -1
		if hi >= 0:
			var it: Dictionary = hands[hi]
			var hs: Vector2i = it["size"]
			_held = it
			_held_src = null
			_held_src_hand = hi
			_held_src_tile = Vector2i.ZERO
			_held_src_size = hs
			_held_off = Vector2i(floori(hs.x / 2.0), floori(hs.y / 2.0))
			hands[hi] = {}
			if it.get("two_handed", false):
				hands[1 - hi] = {}   # the stand-in in the other hand
				hand_changed.emit(1 - hi, hands[1 - hi])
			hand_changed.emit(hi, hands[hi])
			queue_redraw()
		return
	_bring_to_front(w)
	if _close_rect(w).has_point(p):
		close_window(w)
		return
	var trd := _trader(w)
	if trd != null and _dismiss_rect(w).has_point(p):
		trd.dismissed.emit()
		return
	if trd != null and _wholesale_on(w) and _wholesale_rect(w).has_point(p):
		_buy_wholesale(trd)
		return
	if _title_rect(w).has_point(p):
		_drag_win = w
		_drag_off = p - w.pos
		queue_redraw()
		return
	if w.machine != null and w.machine.action_label() != "":
		for ip in w.parts:
			if ip.is_info and _action_rect(w, ip).has_point(p):
				if w.machine.action_enabled():
					w.machine.on_action()
				queue_redraw()
				return
	var part := _part_at(w, p)
	if part != null:
		var cell := _cell_in(w, part, p)
		var idx := _entry_at(part.tag, cell)
		if idx >= 0:
			var e: Dictionary = part.tag.stored[idx]
			if trd != null:
				if not e.get("for_sale", false):
					trd.note = "Not for sale"
					queue_redraw()
					return
				trd.note = ""
			part.tag.stored.remove_at(idx)
			_held = e
			_held_src = part.tag
			_held_src_hand = -1
			_held_src_tile = e["tile"]
			_held_src_size = e["size"]
			_held_off = cell - _held_src_tile
	queue_redraw()

func _on_release(p: Vector2) -> void:
	_drag_win = null
	if _held.is_empty():
		return
	var placed := false
	var w := _win_at(p)
	if w != null:
		var part := _part_at(w, p)
		if part != null:
			var cell := _cell_in(w, part, p)
			var tile := cell - _held_off
			var hsize: Vector2i = _held["size"]
			if _in_grid(part, cell) and _fits(part.tag, tile, hsize):
				var why := _trade_check(part.tag)
				if why == "":
					_trade_commit(part.tag)
					_held["tile"] = tile
					part.tag.stored.append(_held)
					placed = true
				else:
					_say(why, part.tag)
	elif show_hands and _in_hand_zone(p):
		if _held.get("two_handed", false):
			if can_carry_box():   # both hands are free
				var why3 := _trade_check(null)
				if why3 == "":
					_trade_commit(null)
					_held["tile"] = Vector2i.ZERO
					hands[0] = _held
					hands[1] = _ghost()
					hand_changed.emit(0, hands[0])
					hand_changed.emit(1, hands[1])
					placed = true
				else:
					_say(why3, null)
			else:
				_flash("Needs both hands free")
		else:
			var th := _target_hand(p)
			if th >= 0:
				var why2 := _trade_check(null)
				if why2 == "":
					_trade_commit(null)
					_held["tile"] = Vector2i.ZERO
					hands[th] = _held
					hand_changed.emit(th, hands[th])
					placed = true
				else:
					_say(why2, null)
	if not placed:
		_return_held()
	_held = {}
	queue_redraw()

func _return_held() -> void:
	_held["tile"] = _held_src_tile
	_held["size"] = _held_src_size
	if _held_src_hand >= 0:
		hands[_held_src_hand] = _held
		hand_changed.emit(_held_src_hand, hands[_held_src_hand])
		if _held.get("two_handed", false):
			hands[1] = _ghost()
			hand_changed.emit(1, hands[1])
	else:
		_held_src.stored.append(_held)

func _rotate_held(clockwise: bool) -> void:
	var s: Vector2i = _held["size"]
	var off := _held_off
	var new_off: Vector2i
	if clockwise:
		new_off = Vector2i(s.y - 1 - off.y, off.x)
	else:
		new_off = Vector2i(off.y, s.x - 1 - off.x)
	_held["size"] = Vector2i(s.y, s.x)
	_held_off = new_off
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		if not _held.is_empty():
			_return_held()
			_held = {}
			queue_redraw()
		elif not windows.is_empty():
			close_window(windows[windows.size() - 1])
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and not _held.is_empty():
		_rotate_held(not event.shift_pressed)
		get_viewport().set_input_as_handled()

# ---------- hover tooltip ----------

func _hover_entry(p: Vector2) -> Dictionary:
	if not _held.is_empty() or _drag_win != null:
		return {}
	var w := _win_at(p)
	if w != null:
		var part := _part_at(w, p)
		if part != null:
			var idx := _entry_at(part.tag, _cell_in(w, part, p))
			if idx >= 0:
				return part.tag.stored[idx]
		return {}
	if show_hands:
		var hi := _hand_at(p)
		if hi >= 0:
			if hands[hi].get("ghost", false):
				return hands[0]
			return hands[hi]
	return {}

func _tooltip_lines(e: Dictionary) -> Array:
	var grey := Color(0.7, 0.72, 0.8)
	var gold := Color(1, 0.9, 0.3)
	var lines: Array = []
	if e.get("is_box", false):
		var contents: Array = e.get("contents", [])
		var worth := 0
		for it in contents:
			worth += ItemDB.value_of(it)
		lines.append(["Wholesale Box", Color.WHITE])
		lines.append(["Contains: %d items" % contents.size(), grey])
		lines.append(["Worth about: § %d" % worth, gold])
		lines.append(["Right-click on a shelf to unpack", gold])
		return lines
	lines.append([str(e.get("name", "?")), Color.WHITE])
	var tags: Array = e.get("tags", [])
	var cat := str(tags[0]).capitalize() if tags.size() > 0 else "Unknown"
	lines.append(["Type: " + cat, grey])
	var quality := "Standard"
	if tags.size() > 1:
		quality = ", ".join(PackedStringArray(tags.slice(1))).capitalize()
	lines.append(["Quality: " + quality, grey])
	var s: Vector2i = e.get("size", Vector2i.ONE)
	lines.append(["Size: %d x %d" % [s.x, s.y], grey])
	if e.has("charge"):
		lines.append(["Charge: %d%%" % int(e["charge"]), grey])
	if e.has("bought"):
		lines.append(["Purchased for: § %d" % int(e["bought"]), grey])
	else:
		lines.append(["Purchased for: —", grey])
	if e.get("for_sale", false):
		lines.append(["Asking: § %d" % int(e.get("ask", 0)), gold])
	if e.get("two_handed", false):
		lines.append(["Two-handed", grey])
	lines.append(["Est. value: § %d" % ItemDB.value_of(e), gold])
	return lines

func _draw_tooltip(font: Font) -> void:
	var p := get_local_mouse_position()
	var e := _hover_entry(p)
	if e.is_empty():
		return
	var lines := _tooltip_lines(e)
	var fs := 13
	var lh := 18.0
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	w += 20.0
	var h := lines.size() * lh + 12.0
	var x := p.x - w - 16.0
	if x < 4.0:
		x = p.x + 20.0
	var y := clampf(p.y - h / 2.0, 4.0, maxf(4.0, size.y - h - 4.0))
	var r := Rect2(x, y, w, h)
	draw_rect(r, Color(0.06, 0.06, 0.09, 0.95))
	draw_rect(r, Color(0.5, 0.5, 0.62), false, 1.5)
	for i in lines.size():
		draw_string(font, Vector2(x + 10.0, y + 6.0 + i * lh + 13.0), lines[i][0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs + (2 if i == 0 else 0), lines[i][1])

func _draw_toast(font: Font) -> void:
	var fs := 15
	var w := font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 24.0
	var r := Rect2((size.x - w) / 2.0, size.y - HAND_ZONE_H - 40.0, w, 28.0)
	draw_rect(r, Color(0.35, 0.1, 0.1, 0.95))
	draw_rect(r, Color(0.9, 0.4, 0.4), false, 1.5)
	draw_string(font, r.position + Vector2(12.0, 19.0), _toast, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

# ---------- drawing ----------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	if show_hands:
		_draw_hands(font)
	for w in windows:
		_draw_window(w, font)
	if not _held.is_empty():
		_draw_held(font)
	_draw_tooltip(font)
	if _toast_t > 0.0:
		_draw_toast(font)

func _draw_slot_item(font: Font, slot: Rect2, item: Dictionary) -> void:
	var s: Vector2i = item["size"]
	var col: Color = item["color"]
	var nm: String = item["name"]
	if item.get("is_box", false):
		nm = "Box x%d" % (item.get("contents", []) as Array).size()
	var cp := minf(minf((slot.size.x - 12.0) / s.x, (slot.size.y - 12.0) / s.y), 28.0)
	_draw_item(font, slot.get_center() - Vector2(s) * cp / 2.0, cp, s, col, nm, 1.0)

func _draw_hands(font: Font) -> void:
	var holding := not _held.is_empty()
	if not holding and hands[0].is_empty() and hands[1].is_empty():
		return
	var carrying: bool = hands[0].get("two_handed", false)
	var held_two: bool = holding and _held.get("two_handed", false)
	var mp := get_local_mouse_position()
	var target := -1   # 0/1 = a hand, 2 = the middle slot
	if holding:
		var any_free: bool
		if held_two:
			any_free = hands[0].is_empty() and hands[1].is_empty()
		else:
			any_free = hands[0].is_empty() or hands[1].is_empty()
		var band := Color(0.2, 0.7, 0.4, 0.28) if any_free else Color(0.8, 0.25, 0.25, 0.28)
		if _in_hand_zone(mp) and _win_at(mp) == null:
			band.a = 0.5
			if held_two:
				target = 2 if any_free else -1
			else:
				target = _target_hand(mp)
		draw_rect(Rect2(0, size.y - HAND_ZONE_H, size.x, HAND_ZONE_H), band)
		var label := "Drop to hold" if any_free else "Hands full"
		if held_two and not any_free:
			label = "Needs both hands free"
		elif any_free and _held_src != null and _held_src.trader != null:
			label = "Buy for § %d" % int(_held.get("ask", 0))
		draw_string(font, Vector2(0, size.y - HAND_ZONE_H + 18.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(1, 1, 1, 0.85))
	if carrying:
		var m := _middle_slot_rect()
		draw_rect(m, Color(0.1, 0.1, 0.13, 0.9))
		draw_rect(m, Color(0.5, 0.5, 0.6), false, 2.0)
		_draw_slot_item(font, m, hands[0])
		for i in 2:
			var busy := _hand_slot_rect(i)
			draw_rect(busy, Color(0.08, 0.08, 0.1, 0.7))
			draw_rect(busy, Color(0.3, 0.3, 0.36), false, 2.0)
			draw_string(font, busy.position + Vector2(0, 50), "Busy",
				HORIZONTAL_ALIGNMENT_CENTER, busy.size.x, 14, Color(1, 1, 1, 0.35))
		return
	if held_two:
		var m2 := _middle_slot_rect()
		draw_rect(m2, Color(0.1, 0.1, 0.13, 0.9))
		draw_rect(m2, Color(1, 0.9, 0.2) if target == 2 else Color(0.5, 0.5, 0.6), false, 3.0 if target == 2 else 2.0)
		draw_string(font, m2.position + Vector2(0, 50), "Both hands",
			HORIZONTAL_ALIGNMENT_CENTER, m2.size.x, 14, Color(1, 1, 1, 0.5))
		return
	for i in 2:
		var item: Dictionary = hands[i]
		if item.is_empty() and not holding:
			continue
		var slot := _hand_slot_rect(i)
		draw_rect(slot, Color(0.1, 0.1, 0.13, 0.9))
		var edge := Color(1, 0.9, 0.2) if i == target else Color(0.5, 0.5, 0.6)
		draw_rect(slot, edge, false, 3.0 if i == target else 2.0)
		if item.is_empty():
			var side := "Left hand" if i == 0 else "Right hand"
			draw_string(font, slot.position + Vector2(0, 50), side,
				HORIZONTAL_ALIGNMENT_CENTER, slot.size.x, 14, Color(1, 1, 1, 0.5))
			continue
		_draw_slot_item(font, slot, item)

func _draw_window(w: Win, font: Font) -> void:
	var box := _box(w)

	draw_rect(box.grow(3.0), Color(0, 0, 0, 0.35))
	draw_rect(box, Color(0.1, 0.1, 0.13))
	draw_rect(Rect2(box.position, Vector2(box.size.x, PAD * 0.5 + TITLE_H)), Color(0.17, 0.17, 0.22))
	draw_rect(box, Color(0.4, 0.4, 0.5), false, 2.0)
	draw_string(font, box.position + Vector2(PAD, PAD + 14.0), w.title,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - PAD - 40.0, 20, Color.WHITE)

	var cr := _close_rect(w)
	draw_rect(cr, Color(0.35, 0.15, 0.15))
	draw_string(font, cr.position + Vector2(6, 17), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

	var trd := _trader(w)
	if trd != null:
		var dr := _dismiss_rect(w)
		draw_rect(dr, Color(0.3, 0.2, 0.12))
		draw_string(font, dr.position + Vector2(0, 16), "Send away",
			HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 13, Color.WHITE)
	if _has_header(w):
		var lines := _header_lines(w)
		var colors: Array[Color] = [Color.WHITE, Color(0.95, 0.85, 0.35), Color(1.0, 0.65, 0.45)]
		var y0 := box.position.y + PAD * 0.5 + TITLE_H + 2.0
		for i in mini(lines.size(), 3):
			draw_string(font, Vector2(box.position.x + PAD, y0 + i * 20.0 + 15.0), str(lines[i]),
				HORIZONTAL_ALIGNMENT_LEFT, box.size.x - PAD * 2.0, 15, colors[i])
	if trd != null and _wholesale_on(w):
		var wr := _wholesale_rect(w)
		var why := _wholesale_problem(trd)
		var ok := why == ""
		draw_rect(wr, Color(0.2, 0.45, 0.3) if ok else Color(0.22, 0.22, 0.27))
		draw_rect(wr, Color(0.5, 0.8, 0.6) if ok else Color(0.4, 0.4, 0.48), false, 1.5)
		var wlabel := "Buy all § %d (-%d%%)" % [trd.wholesale_cost(), roundi(CustomerData.WHOLESALE_DISCOUNT * 100.0)]
		if not ok:
			wlabel = "Buy all § %d - %s" % [trd.wholesale_cost(), why]
		draw_string(font, wr.position + Vector2(0, 17.0), wlabel, HORIZONTAL_ALIGNMENT_CENTER,
			wr.size.x, 13, Color.WHITE if ok else Color(0.65, 0.65, 0.72))
	for part in w.parts:
		if part.is_info:
			_draw_info(w, part, font)
		else:
			_draw_part(w, part, font, trd)

func _draw_info(w: Win, part: Part, font: Font) -> void:
	var o := _part_origin(w, part)
	var r := Rect2(o, part.size)
	draw_string(font, o + Vector2(0, -5.0), w.machine.info_title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.78, 0.9))
	draw_rect(r, Color(0.13, 0.13, 0.17))
	draw_rect(r, Color(0.35, 0.35, 0.45), false, 1.0)
	var lines: Array = w.machine.info_lines()
	for i in lines.size():
		draw_string(font, o + Vector2(8.0, 20.0 + i * 18.0), str(lines[i][0]),
		HORIZONTAL_ALIGNMENT_LEFT, part.size.x - 16.0, 14, lines[i][1])
	if w.machine.action_label() != "":
		var ar := _action_rect(w, part)
		var on: bool = w.machine.action_enabled()
		draw_rect(ar, Color(0.2, 0.5, 0.3) if on else Color(0.25, 0.25, 0.3))
		draw_rect(ar, Color(0.5, 0.8, 0.6) if on else Color(0.4, 0.4, 0.48), false, 1.5)
		draw_string(font, ar.position + Vector2(0, 19.0), w.machine.action_label(),
		HORIZONTAL_ALIGNMENT_CENTER, ar.size.x, 15, Color.WHITE if on else Color(0.6, 0.6, 0.68))

func _draw_part(w: Win, part: Part, font: Font, trd: CustomerData) -> void:
	var gp := _part_origin(w, part)
	var tag := part.tag
	var cells := tag.inventory_cells()
	var big := tag.inventory_big_cells
	var sub := float(tag.inventory_sub)
	var cp := part.cp

	if w.machine != null:
		draw_string(font, gp + Vector2(0, -5.0), tag.get_display_name(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.78, 0.9))

	for bx in big.x:
		for by in big.y:
			var shade := Color(0.15, 0.15, 0.19) if (bx + by) % 2 == 0 else Color(0.18, 0.18, 0.23)
			draw_rect(Rect2(gp + Vector2(bx, by) * cp * sub, Vector2(cp, cp) * sub), shade)
	for x in cells.x:
		for y in cells.y:
			draw_rect(Rect2(gp + Vector2(x, y) * cp, Vector2(cp, cp)), Color(0.28, 0.28, 0.34), false, 1.0)
	for bx in big.x:
		for by in big.y:
			draw_rect(Rect2(gp + Vector2(bx, by) * cp * sub, Vector2(cp, cp) * sub), Color(0.6, 0.6, 0.7), false, 2.0)

	for e in tag.stored:
		var t: Vector2i = e.get("tile", Vector2i.ZERO)
		var s: Vector2i = e.get("size", Vector2i.ONE)
		var col: Color = e.get("color", Color.WHITE)
		var nm: String = e.get("name", "?")
		var ipos := gp + Vector2(t) * cp
		_draw_item(font, ipos, cp, s, col, nm, 1.0)
		if trd != null:
			var r := Rect2(ipos, Vector2(s) * cp).grow(-2.0)
			if e.get("for_sale", false):
				draw_string(font, Vector2(r.position.x + 3.0, r.end.y - 3.0), "§%d" % int(e.get("ask", 0)),
					HORIZONTAL_ALIGNMENT_LEFT, maxf(r.size.x - 4.0, 1.0), 12, Color(1, 0.9, 0.3))
			else:
				draw_rect(r, Color(0, 0, 0, 0.5))

func _draw_held(font: Font) -> void:
	var p := get_local_mouse_position()
	var hsize: Vector2i = _held["size"]
	var col: Color = _held["color"]
	var nm: String = _held["name"]
	var w := _win_at(p)
	if w != null:
		var part := _part_at(w, p)
		if part != null:
			var cell := _cell_in(w, part, p)
			var tile := cell - _held_off
			var ok := _fits(part.tag, tile, hsize) and _trade_check(part.tag) == ""
			var tint: Color = col if ok else Color(0.9, 0.2, 0.2)
			_draw_item(font, _part_origin(w, part) + Vector2(tile) * part.cp, part.cp, hsize, tint, nm, 0.8)
			return
	var cp := 28.0
	if not windows.is_empty():
		cp = windows[windows.size() - 1].parts[0].cp
	var pos := p - (Vector2(_held_off) + Vector2(0.5, 0.5)) * cp
	_draw_item(font, pos, cp, hsize, col, nm, 0.8)

func _draw_item(font: Font, pos: Vector2, cp: float, isize: Vector2i, col: Color, nm: String, alpha: float) -> void:
	var r := Rect2(pos, Vector2(isize) * cp).grow(-2.0)
	draw_rect(r, Color(col.r, col.g, col.b, alpha))
	draw_string(font, r.position + Vector2(4, 14), nm, HORIZONTAL_ALIGNMENT_LEFT,
		maxf(r.size.x - 6.0, 1.0), 12, Color(1, 1, 1, alpha))
