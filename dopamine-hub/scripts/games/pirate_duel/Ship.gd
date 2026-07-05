extends Area2D

const ROCK_SPEED: float = 0.4
const ROCK_ANGLE: float = 0.04

@onready var ship_sprite: Sprite2D = $Ship


func _process(_delta: float) -> void:
	ship_sprite.rotation = sin(Time.get_ticks_msec() * 0.001 * ROCK_SPEED * TAU) * ROCK_ANGLE
