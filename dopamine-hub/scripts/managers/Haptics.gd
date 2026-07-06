extends Node

# Simple mobile haptic feedback wrapper. No-ops safely on desktop.
# Uses Godot's built-in Input.vibrate_handheld(duration_ms, amplitude).

var enabled: bool = true


func _vibrate(duration_ms: int, amplitude: float = -1.0) -> void:
	if not enabled:
		return
	Input.vibrate_handheld(duration_ms, amplitude)


func light() -> void:
	_vibrate(15, 0.4)


func medium() -> void:
	_vibrate(40, 0.7)


func heavy() -> void:
	_vibrate(90, 1.0)


func success() -> void:
	# quick double-tap feel for positive events
	_vibrate(25, 0.6)