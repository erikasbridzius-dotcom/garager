class_name CustomerMenu
extends CanvasLayer

var inventory_panel: InventoryPanel

func _ready() -> void:
	inventory_panel = get_tree().current_scene.find_child("InventoryPanel", true, false) as InventoryPanel
	if inventory_panel == null:
		push_error("CustomerMenu: could not find the InventoryPanel node.")

func open(c: Customer) -> void:
	if inventory_panel != null:
		inventory_panel.open_customer(c)

func close_menu() -> void:
	if inventory_panel != null:
		inventory_panel.close_customers()
