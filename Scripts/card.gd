# res://scripts/Card.gd
extends Node2D

# Enums
enum Suits {
	SPADE,
	HEART,
	CLUB,
	DIAMOND,
}

# ranks
@export_range(1, 13, 1)
var rank = 1

# suits
@export
var suit = Suits.SPADE

# Card positions
var original_position
var select_offset_y = -15
var original_global_position = Vector2.ZERO
var selected = false

func _ready() -> void:
	$TextureButton.toggle_mode = true
	$TextureButton.connect("toggled", Callable(self, "on_card_toggled"))
	update_texture()

func update_texture() -> void:
	var suit_names = ["spades","hearts","clubs","diamonds"]
	var filename = "%d_%s_white.png" % [rank, suit_names[suit]]
	var path = "res://Assets/Cards/" + filename

	# 1) Load the Texture2D
	var tex: Texture2D = load(path)
	if not tex:
		push_error("Card image missing: %s" % path)
		return

	# 2) Assign to the button’s texture_normal
	var btn = $TextureButton
	btn.texture_normal = tex

	# 3) Center its pivot so global_position lands at the card’s center
	btn.pivot_offset = tex.get_size() * 0.5

func record_original():
	original_global_position = global_position

func on_card_toggled(pressed):
	print("toggled:", pressed)
	if pressed:
		translate(Vector2(0, select_offset_y))
		selected = true
	else:
		translate(Vector2(0, -select_offset_y))
		selected = false
