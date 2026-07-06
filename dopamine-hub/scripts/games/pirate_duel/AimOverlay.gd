extends Node2D

# Dedicated high-z overlay whose _draw delegates to the parent PirateDuel,
# so the aim trajectory renders ABOVE gameplay sprites.

func _draw() -> void:
	var p: Node = get_parent()
	if p and p.has_method("draw_aim_overlay"):
		p.draw_aim_overlay(self)
