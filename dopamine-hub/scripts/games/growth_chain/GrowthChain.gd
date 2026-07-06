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

# Streak multiplier
var _streak: int = 0

# Approach cue state (reset per bubble)
var _wobble_time: float = 0.0
var _haptic_tick_time: float = 0.0


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
	bubble.modulate = Color(1, 1, 1, 1)
	round_score_label.scale = Vector2(1.0, 1.0)  # reset streak-pop scale
	inflate_sound.pitch_scale = 1.0
	_wobble_time = 0.0
	_haptic_tick_time = 0.0
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
		
		# --- Approach cues ---
		var threshold: float = _pop_scales[_current_bubble_index]
		var danger: float = clampf((_current_scale - starting_scale) / (threshold - starting_scale), 0.0, 1.0)
		
		# a) Colour shift toward red
		bubble.modulate = Color(1, 1, 1).lerp(Color(1, 0.35, 0.3), danger)
		
		# c) Audio pitch ramp
		inflate_sound.pitch_scale = lerpf(1.0, 1.8, danger)
		
		# d) Proximity haptic ticks at danger > 0.75
		if danger > 0.75:
			_haptic_tick_time += delta
			if _haptic_tick_time >= 0.12:
				_haptic_tick_time = 0.0
				Haptics.light()
		else:
			_haptic_tick_time = 0.0
		
		# Compute base scale for visual
		var visual_scale: Vector2 = Vector2(_current_scale, _current_scale)
		
		# b) Wobble at danger > 0.6
		if danger > 0.6:
			_wobble_time += delta
			var wobble_strength: float = (danger - 0.6) / 0.4  # 0→1 over the danger band
			var wobble_amp: float = wobble_strength * 0.04  # max 4% scale jitter
			var wobble_offset: float = sin(_wobble_time * 60.0) * wobble_amp
			visual_scale.x += wobble_offset
			visual_scale.y -= wobble_offset * 0.5  # slight squash opposite
		else:
			_wobble_time = 0.0
		
		bubble.scale = visual_scale
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
	inflate_sound.pitch_scale = 1.0
	_is_popped = true
	_is_holding = false
	_streak = 0
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
	Haptics.heavy()
	_update_indicators()
	
	get_tree().create_timer(0.6).timeout.connect(_advance_bubble)


func _cash_out() -> void:
	if _is_cashing_out:
		return
	inflate_sound.stop()
	inflate_sound.pitch_scale = 1.0
	_is_cashing_out = true
	_is_holding = false
	
	_streak += 1
	var mult: int = clampi(_streak + 1, 1, 5)
	var raw_points: int = int(_current_scale * 10)
	var points: int = raw_points * mult
	_total_score += points
	cashout_sound.play()
	Haptics.success()
	
	if mult > 1:
		round_score_label.text = "+%d (x%d)" % [points, mult]
	else:
		round_score_label.text = "+%d" % points
	_update_labels()
	_update_indicators()
	
	# Streak visual — pop the round score label
	if mult > 1:
		var pop_tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop_tween.tween_property(round_score_label, "scale", Vector2(1.5, 1.5), 0.1)
		pop_tween.tween_property(round_score_label, "scale", Vector2(1.0, 1.0), 0.2)
	
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
	_streak = 0
	_game_over = false
	_generate_pop_scales()
	_start_bubble()
