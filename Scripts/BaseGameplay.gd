# res://scripts/BaseGameplay.gd
extends Node2D

# Preloaded Scenes
var CardScene = preload("res://Scenes/Card.tscn")

# Enums
enum Mode { RUN_OUT, MAINTAIN_7 } # Mode
enum PlayType { NONE, SINGLE, PAIR, TRIPLE, QUAD, RUN } # Play Type
enum SortMode { ASCENDING, DESCENDING, SUIT }

# Stats
@export var max_health = 50
var player_health = 0
var cpu_health = 0
var attack_power = 10
var player_turn = true


# Gameplay Mode Settings
@export var mode = Mode.RUN_OUT
@export_range(1, 20, 1)
var hand_size: int = 10
@export var draw_after_empty = false
var game_over = false
@onready var sort_btn = $CanvasLayer2/sort_btn
var current_sort_mode = SortMode.ASCENDING

# Card variables
var current_play_type = PlayType.NONE
var current_play_size = 0
var current_play_rank = 0
var deck = []
var discard = []
var player_hand = []
var cpu_hand = []

# Ready 
func _ready():
	mode = Global.selected_mode
	_init_mode()
	startRound()
	current_sort_mode = SortMode.ASCENDING
	sort_btn.text = "Sort By Descending"
	sort_btn.pressed.connect(Callable(self, "on_sort_btn_pressed"))

# Initialize the mode
func _init_mode():
	match mode:
		Mode.RUN_OUT:
			hand_size       = 10
			draw_after_empty = false
			$CanvasLayer/UIRoot/HealthBarContainer.visible = false
		Mode.MAINTAIN_7:
			hand_size       = 7
			draw_after_empty = true
			$CanvasLayer/UIRoot/HealthBarContainer.visible = true

# When a round starts
func startRound():
	build_deck()
	deck.shuffle()
	player_hand = draw_cards(hand_size)
	cpu_hand = draw_cards(hand_size)
	
	if mode == Mode.MAINTAIN_7:
		player_health = max_health
		cpu_health = max_health
		update_health_ui()
	
	displayCards()
	player_turn = true
	enable_player_input(true)

func enable_player_input(on):
	$CanvasLayer2/play_cards.disabled = not on
	$CanvasLayer2/pass_btn.disabled = not on
	for card in $CanvasLayer2/Cards.get_children():
		var btn = card.get_node("TextureButton") as TextureButton
		print_debug("Card ", card.name, " button.disabled =", btn.disabled, " → setting to ", not on)
		btn.disabled = not on

func on_sort_btn_pressed():
	match current_sort_mode:
		SortMode.ASCENDING:
			current_sort_mode = SortMode.DESCENDING
			sort_btn.text = "Sort By Suits"
		SortMode.DESCENDING:
			current_sort_mode = SortMode.SUIT
			sort_btn.text = "Sort By Ascending"
		SortMode.SUIT:
			current_sort_mode = SortMode.ASCENDING
			sort_btn.text = "Sort By Descending"
	
	displayCards()

func next_turn():
	player_turn = not player_turn
	enable_player_input(player_turn)
	
	if not player_turn:
		await get_tree().create_timer(1.0).timeout
		cpu_take_turn()

func rank_power(r: int) -> int:
	if r == 2:
		return 15
	elif r == 1:
		return 14
	else:
		return r

func cpu_take_turn() -> void:
	# decide CPU play
	var sel: Array = pick_cpu_cards()

	# if no play → pass
	if sel.is_empty():
		if mode == Mode.MAINTAIN_7:
			cpu_health -= 10
			update_health_ui()
			$PlayLabel.text = "CPU passes and takes 10 damage"
		else:
			$PlayLabel.text = "CPU passes"

		_reset_trick()
		next_turn()
		return

	# perform the play
	commit_play(false, sel)

func pick_cpu_cards():
	match current_play_type:
		PlayType.NONE:
			randomize()
			var roll = randi() % 100

			# 1) Gather counts for pairs/triples
			var counts := {}
			for c in cpu_hand:
				var rr = c["rank"]
				counts[rr] = counts.get(rr, 0) + 1

			var pairs := []
			var triples := []
			for rr in counts.keys():
				if counts[rr] >= 2:
					var pair := []
					for c in cpu_hand:
						if c["rank"] == rr and pair.size() < 2:
							pair.append(c)
					pairs.append(pair)
				if counts[rr] >= 3:
					var triple := []
					for c in cpu_hand:
						if c["rank"] == rr and triple.size() < 3:
							triple.append(c)
					triples.append(triple)

			# 2) Gather runs (length ≥ 3, same suit)
			var runs := []
			for s in [0,1,2,3]:
				var ranks := []
				for c in cpu_hand:
					if c["suit"] == s:
						ranks.append(c["rank"])
				ranks.sort()
				var uniq := []
				for r in ranks:
					if uniq.is_empty() or uniq[-1] != r:
						uniq.append(r)
				var seq := [uniq[0]]
				for i in range(1, uniq.size()):
					if uniq[i] == uniq[i-1] + 1:
						seq.append(uniq[i])
					else:
						if seq.size() >= 3:
							runs.append({ "suit": s, "ranks": seq.duplicate() })
						seq = [uniq[i]]
				if seq.size() >= 3:
					runs.append({ "suit": s, "ranks": seq })

			# 3) Decide what to lead with
			if roll < 20 and runs.size() > 0:
				# pick a random run
				var idx = randi() % runs.size()
				var run_sel = runs[idx]
				var out := []
				for rr in run_sel["ranks"]:
					for c in cpu_hand:
						if c["suit"] == run_sel["suit"] and c["rank"] == rr:
							out.append(c)
							break
				return out

			elif roll < 40 and triples.size() > 0:
				var idx = randi() % triples.size()
				return triples[idx]

			elif roll < 60 and pairs.size() > 0:
				var idx = randi() % pairs.size()
				return pairs[idx]

			else:
				# default to lowest single
				var best = null
				for c in cpu_hand:
					if best == null or rank_power(c["rank"]) < rank_power(best["rank"]):
						best = c
				if best != null:
					return [best]
				return []

		PlayType.SINGLE:
			# Lowest single that beats the current rank
			var best_card = null
			var best_power = 999
			for card in cpu_hand:
				var p = rank_power(card["rank"])
				if p > current_play_rank and p < best_power:
					best_card = card
					best_power = p
			if best_card != null:
				return [best_card]
			return []

		PlayType.PAIR:
			# Find the lowest‐power rank with at least 2 cards that beats current
			var counts = {}
			for card in cpu_hand:
				var rr = card["rank"]
				counts[rr] = counts.get(rr, 0) + 1
			var best_rank  = null
			var best_power = 999
			for rr in counts.keys():
				if counts[rr] >= 2:
					var p = rank_power(rr)
					if p > current_play_rank and p < best_power:
						best_rank  = rr
						best_power = p
			if best_rank == null:
				return []
			var out = []
			for card in cpu_hand:
				if card["rank"] == best_rank and out.size() < 2:
					out.append(card)
			return out

		PlayType.TRIPLE:
			# Same as pair but needing 3 of a kind
			var counts = {}
			for card in cpu_hand:
				var rr = card["rank"]
				counts[rr] = counts.get(rr, 0) + 1
			var best_rank  = null
			var best_power = 999
			for rr in counts.keys():
				if counts[rr] >= 3:
					var p = rank_power(rr)
					if p > current_play_rank and p < best_power:
						best_rank  = rr
						best_power = p
			if best_rank == null:
				return []
			var out = []
			for card in cpu_hand:
				if card["rank"] == best_rank and out.size() < 3:
					out.append(card)
			return out

		PlayType.QUAD:
			# Four of a kind
			var counts = {}
			for card in cpu_hand:
				var rr = card["rank"]
				counts[rr] = counts.get(rr, 0) + 1
			var best_rank  = null
			var best_power = 999
			for rr in counts.keys():
				if counts[rr] >= 4:
					var p = rank_power(rr)
					if p > current_play_rank and p < best_power:
						best_rank  = rr
						best_power = p
			if best_rank == null:
				return []
			var out = []
			for card in cpu_hand:
				if card["rank"] == best_rank and out.size() < 4:
					out.append(card)
			return out

		PlayType.RUN:
			# Look for the lowest‐power run of the right length and suit
			var suit_map = { 0:[], 1:[], 2:[], 3:[] }
			for card in cpu_hand:
				suit_map[card["suit"]].append(card["rank"])

			var best_start      = -1
			var best_suit       = -1
			var best_high_power = 999

			for s in suit_map.keys():
				var arr = suit_map[s]
				arr.sort()
				for i in range(arr.size() - current_play_size + 1):
					var ok = true
					for j in range(current_play_size - 1):
						if arr[i + j + 1] != arr[i + j] + 1:
							ok = false
							break
					if not ok:
						continue

					var high_rank = arr[i + current_play_size - 1]
					var p = rank_power(high_rank)
					if p > current_play_rank and p < best_high_power:
						best_high_power = p
						best_start      = arr[i]
						best_suit       = s

			if best_suit < 0:
				return []

			var out = []
			for rr in range(best_start, best_start + current_play_size):
				for card in cpu_hand:
					if card["suit"] == best_suit and card["rank"] == rr:
						out.append(card)
						break
			return out

		_:
			return []

func update_health_ui():
	$CanvasLayer/UIRoot/HealthBarContainer/PlayerUI/PlayerHP.value = player_health
	$CanvasLayer/UIRoot/HealthBarContainer/CPUUI/CPUHP.value = cpu_health

# build the deck
func build_deck():
	deck.clear()
	var suitCount = 4
	for s in range(suitCount):
		for rank in range(1,14):
			deck.append({"rank": rank, "suit": s})

# Draw cards to both player and enemy
func draw_cards(n):
	var out = []
	for i in range(n):
		if deck.is_empty():
			break
		out.append(deck.pop_back())
	return out

# show the cards on the screen
func displayCards():
	# clear old
	for old in $CanvasLayer2/Cards.get_children():
		old.queue_free()

	# get a sorted copy of player_hand
	var hand_sorted = get_sorted_player_hand()

	for i in range(hand_sorted.size()):
		var data = hand_sorted[i]
		var slot = $CanvasLayer2/CardSlots.get_child(i)

		var c = CardScene.instantiate()
		c.rank = data["rank"]
		c.suit = data["suit"]
		c.update_texture()

		$CanvasLayer2/Cards.add_child(c)

		# center sprite on the slot
		var tex  := c.get_node("TextureButton").texture_normal as Texture2D
		var half := tex.get_size() * 0.5
		c.position = $CanvasLayer2/Cards.to_local(slot.global_position) - half

	# update CPU count
	$CPUHandCountLabel.text = "CPU Hand: %d" % cpu_hand.size()

func get_sorted_player_hand():
	var temp   = player_hand.duplicate()
	var result = []
	while temp.size() > 0:
		var best_idx = 0
		for j in range(1, temp.size()):
			if compare_cards(temp[j], temp[best_idx]) < 0:
				best_idx = j
		result.append(temp[best_idx])
		temp.remove_at(best_idx)
	return result

func compare_cards(a, b):
	match current_sort_mode:
		SortMode.ASCENDING:
			return rank_power(a["rank"]) - rank_power(b["rank"])
		SortMode.DESCENDING:
			return rank_power(b["rank"]) - rank_power(a["rank"])
		SortMode.SUIT:
			var sa = a["suit"]
			var sb = b["suit"]
			if sa != sb:
				return sa - sb
			return rank_power(a["rank"]) - rank_power(b["rank"])
	return 0

# When play cards is pressed
func _on_play_cards_pressed() -> void:
	if not player_turn:
		return

	var sel: Array = get_selected_cards()
	if sel.is_empty():
		$PlayLabel.text = "Select at least one card!"
		return

	if not cards_check(sel):
		return

	commit_play(true, sel)

func _reset_trick() -> void:
	current_play_type = PlayType.NONE
	current_play_size = 0
	current_play_rank = 0

# Find what cards were selected by player
func get_selected_cards():
	var picks = []       
	
	for card in $CanvasLayer2/Cards.get_children():
		if card.selected:
			picks.append({
				"node": card,
				"rank": card.rank,
				"suit": card.suit
			})
	print(picks)
	return picks

# Check if the cards attempted to be played are legal
func cards_check(cards):
	var pt = determine_play_type(cards)
	if pt == PlayType.NONE:
		print("Not a valid combo!")
		return false
	
	var sz = cards.size()
	var rank = determine_power(cards)
	
	if current_play_type == PlayType.NONE: 
		return true
	
	if pt != current_play_type:
		print("Must follow the same play type!")
		return false
	if sz != current_play_size:
		print("Must play %d cards!" % current_play_size)
		return false
	
	if rank <= current_play_rank:
		print("Must play higher!")
		return false
	
	return true

# Determine the power of the cards to check legality
func determine_power(played_cards):
	var best = -1
	for entry in played_cards:
		var p = rank_power(entry["rank"])
		if p > best:
			best = p
	return best

# Determine what play type is being attempted to play
func determine_play_type(cards):
	var n = cards.size()
	
	if n == 1:
		return PlayType.SINGLE
	
	var ranks = []
	var suits = []
	for d in cards:
		ranks.append(d["rank"])
		suits.append(d["suit"])
	ranks.sort()
	
	# 2,3,4 of kind?
	if ranks.count(ranks[0]) == n: 
		if n ==2:
			return PlayType.PAIR
		if n == 3: 
			return PlayType.TRIPLE
		if n == 4: 
			return PlayType.QUAD
	
	# run?
	if n >= 3:
		var ok = true
		for i in range(n-1):
			if ranks[i+1] != ranks[i] + 1:
				ok = false
				break
		if ok:
			var first_suit = suits[0]
			for s in suits:
				if s != first_suit:
					ok = false
					break
		if ok:
			return PlayType.RUN
	return PlayType.NONE

# Actually playing the cards
func commit_play(by_player: bool, sel: Array) -> void:
	# show what happened
	var who = "Player" if by_player else "CPU"
	$PlayLabel.text = "%s played: %s" % [ who, cards_to_text(sel) ]

	# remove cards from the appropriate hand & scene
	if by_player:
		for entry in sel:
			entry.node.queue_free()
			for i in range(player_hand.size()):
				var d = player_hand[i]
				if d["rank"] == entry["rank"] and d["suit"] == entry["suit"]:
					player_hand.remove_at(i)
					break
	else:
		for entry in sel:
			for i in range(cpu_hand.size()):
				var d = cpu_hand[i]
				if d["rank"] == entry["rank"] and d["suit"] == entry["suit"]:
					cpu_hand.remove_at(i)
					break
	
	# 2a) In MAINTAIN_7 mode, if a hand empties, redraw 7
	if mode == Mode.MAINTAIN_7:
		if by_player and player_hand.is_empty():
			player_hand = draw_cards(hand_size)
			displayCards()
		elif not by_player and cpu_hand.is_empty():
			cpu_hand = draw_cards(hand_size)
			$CPUHandCountLabel.text = "CPU Hand: %d" % cpu_hand.size()
	
	# 2b) Health‐based victory in MAINTAIN_7
	if mode == Mode.MAINTAIN_7:
		if cpu_health <= 0:
			$PlayLabel.text = "You win!"
			show_game_over()
			return
		if player_health <= 0:
			$PlayLabel.text = "CPU wins!"
			show_game_over()
			return
	
	# update CPU count label (common to both modes)
	$CPUHandCountLabel.text = "CPU Hand: %d" % cpu_hand.size()

	# check for a run-out win
	if mode == Mode.RUN_OUT:
		if by_player and player_hand.is_empty():
			$PlayLabel.text = "You win!"
			show_game_over()
			return
		if (not by_player) and cpu_hand.is_empty():
			$PlayLabel.text = "CPU wins!"
			show_game_over()
			return

	# record trick state
	var pt  = determine_play_type(sel)
	var pwr = determine_power(sel)
	if current_play_type == PlayType.NONE:
		current_play_type = pt
		current_play_size = sel.size()
	current_play_rank = pwr

	next_turn()

func cards_to_text(played_cards):
	var parts: Array = []
	# rank_names[1] = "Ace", [11] = "Jack", [12] = "Queen", [13] = "King"
	var rank_names := [
		"", "Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10",
		"Jack", "Queen", "King"
	]
	# use plural, capitalized suits
	var suit_names := ["Spades","Hearts","Clubs","Diamonds"]

	for entry in played_cards:
		var r = entry["rank"]
		var s = suit_names[ entry["suit"] ]
		parts.append("%s %s" % [ rank_names[r], s ])

	return ", ".join(parts)

func show_game_over():
	$CanvasLayer/ContinueOverlay.visible = true
	game_over = true
	$CanvasLayer/ContinueOverlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	print_debug("▶▶▶ GAME OVER – overlay shown")

func _input(event: InputEvent):
	if not game_over:
		return
	
	print_debug("⮕ Got input in game_over:", event)
	
	if event is InputEventKey and event.pressed:
		print_debug("⮕ key pressed, returning to menu")
		_return_to_menu()
	elif event is InputEventMouseButton and event.pressed:
		print_debug("⮕ key pressed, returning to menu")
		_return_to_menu()

func _return_to_menu():
	get_tree().change_scene_to_file("res://Scenes/main_menu.tscn")

func _on_pass_btn_pressed() -> void:
	if not player_turn:
		return

	if mode == Mode.MAINTAIN_7:
		# 7-card mode: player takes 10 damage
		player_health -= 10
		update_health_ui()
		$PlayLabel.text = "Player passes and takes 10 damage"
	else:
		# run-out mode: no damage
		$PlayLabel.text = "Player passes"

	# reset the current trick
	current_play_type = PlayType.NONE
	current_play_size = 0
	current_play_rank = 0

	# hand off to CPU
	next_turn()
