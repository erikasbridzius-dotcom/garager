extends Node

const PATH := "res://Data/items.json"

var defs: Dictionary = {}
var tag_multipliers: Dictionary = {}

func _ready() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("ItemDB: cannot open " + PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ItemDB: " + PATH + " is not valid JSON")
		return
	var data: Dictionary = parsed
	tag_multipliers = data.get("tag_price_multipliers", {})
	for d in data.get("items", []):
		defs[str(d["id"])] = d

# A fresh item, ready to put into an inventory or a hand
func make_item(id: String) -> Dictionary:
	if not defs.has(id):
		push_error("ItemDB: unknown item id '%s'" % id)
		return {}
	var d: Dictionary = defs[id]
	var sz: Array = d.get("size", [1, 1])
	var tags: Array = []
	for t in d.get("tags", []):
		tags.append(str(t))
	var item := {
		"id": id,
		"name": str(d.get("name", id)),
		"size": Vector2i(int(sz[0]), int(sz[1])),
		"color": Color.html(str(d.get("color", "#cccccc"))),
		"tags": tags,
		"price": int(d.get("price", 0)),
		"tile": Vector2i.ZERO,
	}
	if d.get("two_handed", false):
		item["two_handed"] = true
	if d.has("charge"):
		item["charge"] = int(d["charge"])
	return item

func has_all_tags(entry: Dictionary, wanted: Array) -> bool:
	var tags: Array = entry.get("tags", [])
	for w in wanted:
		if not tags.has(w):
			return false
	return true

# Market value: the default price times the multiplier of each tag the item has, and today's events
func value_of(entry: Dictionary) -> int:
	var v := float(entry.get("price", 0))
	var tags: Array = entry.get("tags", [])
	for t in tags:
		v *= float(tag_multipliers.get(t, 1.0))
	v *= GameState.event_multiplier(tags)
	return maxi(1, roundi(v))
