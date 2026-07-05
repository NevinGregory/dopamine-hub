extends Node

@onready var bubble_indicators: Node2D = $BubbleIndicators
@onready var bubble: Sprite2D = $Bubble
@onready var round_score_label: Label = $Background/RoundScore
@onready var total_score_label: Label = $Background/TotalScore
@onready var status_label: Label = $Background/StatusLabel
@onready var inflate_sound: AudioStreamPlayer2D = $inflate_sound
@onready var pop_sound: AudioStreamPlayer2D = $pop_sound
@onready var cashout_sound: AudioStreamPlayer2D = $cashout_sound
@onready var particles: GPUParticles2D = $Particles

@export var min_pop_size: float = 2.0
@export var max_pop_size: float = 5.0
@export var grow_rate: float = 0.8  # scale increase per second while held
@export var starting_scale: float = 0.3
@export var float_duration: float = 0.8
@export var float_height: float = 300.0
@export var sway_amplitude: float = 60.0
@export var sway_frequency: float = 3.0

var _pop_scales: Array[float] = []  # hidden pop thresholds per bubble
var _current_bubble_index: int = 0
var _total_score: int = 0
var _game_over: bool = false
var _is_popped: bool = false
var _is_cashing_out: bool = false
var _is_holding: bool = false
var _current_scale: float = 0.0
var _bubble_start_pos: Vector2
var _indicator_dots: Array[Node]


func _ready() -> void:
	_bubble_start_pos = bubble.position
	_indicator_dots = bubble_indicators.get_children()
	_generate_pop_scales()
	_start_bubble()


func _generate_pop_scales() -> void:
	_pop_scales.clear()
	for _i in 5:
		_pop_scales.append(randf_range(min_pop_size, max_pop_size))


func _start_bubble() -> void:

	if _current_bubble_index >= 5:
		_end_game()
		return
	
	_is_popped = false
	_is_cashing_out = false
	_is_holding = false
	_current_scale = starting_scale
	bubble.position = _bubble_start_pos
	bubble.scale = Vector2(starting_scale, starting_scale)
	bubble.visible = true
	bubble.modulate.a = 1.0
	round_score_label.text = "0"
	status_label.text = ""
	_update_labels()
	_update_indicators()


func _update_labels() -> void:
	total_score_label.text = "Total: %d" % _total_score


func _update_indicators() -> void:
	var max_dots: int = _indicator_dots.size()
	for i in max_dots:
		var dot := _indicator_dots[i] as CanvasItem
		if not dot:
			continue
		
		if i < _current_bubble_index:
			dot.modulate = Color(1, 1, 1, 0.6)  # done
		elif i == _current_bubble_index:
			if _is_popped:
				dot.modulate = Color(1, 0.3, 0.3, 0.8)  # popped
			else:
				dot.modulate = Color(1, 1, 1, 0.9)  # active
		else:
			dot.modulate = Color(1, 1, 1, 0.3)  # pending


func _process(delta: float) -> void:
	if _is_popped or _is_cashing_out or _game_over:
		return
	
	if _is_holding:
		_current_scale += grow_rate * delta
		
		if _current_scale >= _pop_scales[_current_bubble_index]:
			_current_scale = _pop_scales[_current_bubble_index]
			bubble.scale = Vector2(_current_scale, _current_scale)
			_pop_bubble()
			return
		
		bubble.scale = Vector2(_current_scale, _current_scale)
		round_score_label.text = str(int(_current_scale * 10))


func _input(event: InputEvent) -> void:
	if _game_over:
		if (event is InputEventMouseButton and event.pressed) or \
		   (event is InputEventScreenTouch and event.pressed):
			_reset_game()
		return
	
	# Press down — start holding
	if (event is InputEventMouseButton and event.pressed) or \
	   (event is InputEventScreenTouch and event.pressed):
		if not _is_popped and not _is_cashing_out:
			inflate_sound.play()
			_is_holding = true
	
	# Release — cash out
	if (event is InputEventMouseButton and not event.pressed) or \
	   (event is InputEventScreenTouch and not event.pressed):
		if _is_holding and not _is_popped and not _is_cashing_out:
			_cash_out()
		_is_holding = false


func _pop_bubble() -> void:
	inflate_sound.stop()
	_is_popped = true
	_is_holding = false
	bubble.visible = false
	
	# Match particle ring to bubble's current size
	var tex := bubble.texture
	var tex_w: float = tex.get_width() if tex else 256
	var bubble_radius: float = tex_w * bubble.scale.x * 0.5
	var mat := particles.process_material as ParticleProcessMaterial
	if mat:
		mat.emission_ring_inner_radius = bubble_radius / particles.scale.x
	
	particles.position = bubble.position
	particles.restart()
	pop_sound.play()
	_update_indicators()
	
	get_tree().create_timer(0.6).timeout.connect(_advance_bubble)


func _cash_out() -> void:
	if _is_cashing_out:
		return
	inflate_sound.stop()
	_is_cashing_out = true
	_is_holding = false
	
	var points: int = int(_current_scale * 10)
	_total_score += points
	cashout_sound.play()
	
	round_score_label.text = "+%d" % points
	_update_labels()
	_update_indicators()
	
	# Clone the bubble — original resets immediately, clone floats lazily away
	var clone: Sprite2D = bubble.duplicate()
	clone.position = bubble.position
	clone.scale = bubble.scale
	clone.modulate.a = 1.0
	add_child(clone)
	
	var start_pos: Vector2 = clone.position
	var float_tween := create_tween()
	float_tween.set_trans(Tween.TRANS_LINEAR)
	float_tween.set_ease(Tween.EASE_IN_OUT)
	float_tween.tween_method(
		func(p: float):
			clone.position = Vector2(
				start_pos.x + sin(p * PI * sway_frequency) * sway_amplitude * (1.0 - p),
				start_pos.y - float_height * p
			)
	,
	0.0, 1.0, float_duration
	)
	float_tween.finished.connect(clone.queue_free)
	
	# Advance immediately — no delay
	_advance_bubble()


func _advance_bubble() -> void:
	_current_bubble_index += 1
	round_score_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_start_bubble()


func _end_game() -> void:
	_game_over = true
	status_label.text = "Final Score: %d" % _total_score
	bubble.visible = false


func _reset_game() -> void:
	_total_score = 0
	_current_bubble_index = 0
	_game_over = false
	_generate_pop_scales()
	_start_bubble()
