extends Node2D

func _on_run_out_button_pressed() -> void:
	Global.selected_mode = preload("res://Scripts/BaseGameplay.gd").Mode.RUN_OUT
	get_tree().change_scene_to_file("res://scenes/BaseGameplay.tscn")

func _on_maintain_7_button_pressed() -> void:
	Global.selected_mode = preload("res://Scripts/BaseGameplay.gd").Mode.MAINTAIN_7
	get_tree().change_scene_to_file("res://scenes/BaseGameplay.tscn")
