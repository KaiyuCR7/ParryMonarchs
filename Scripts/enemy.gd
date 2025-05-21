extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready():
	$AnimationPlayer.play("enemy_idle")

func enemy_animation_end():
	$AnimationPlayer.play("enemy_idle")
