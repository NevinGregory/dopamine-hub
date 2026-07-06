extends Node2D

@onready var orb_area: Sprite2D = $Orb
@onready var score_label: Label = $Background/ScoreLabel
@onready var orb_outline: Sprite2D = $OrbOutline
@onready var hit_sounds: Node = $hit_sounds
@onready var miss_sound_audio: AudioStreamPlayer2D = $miss_sound
@onready var miss_particles: GPUParticles2D = $Particles

@export var orb_radius: float = 40.0
@export var outline_grow_duration: float = 1.2
@export var initial_speed: float = 300.0
@export var mid_curve_strength: float = 40000.0

var base_speed: float = 300.0
var current_speed: float = 300.0
var score: int = 0
var screen_size: Vector2
var _heading_right: bool = true
var _last_hit_index: int = -1


func _ready() -> void:
	screen_size = get_viewport_rect().size
	score_label.text = "0"
	base_speed = initial_speed
	current_speed = initial_speed
	_start_orb()


func _process(delta: float) -> void:
	var movement: float = current_speed * delta
	
	if _heading_right:
		orb_area.position.x += movement
		if orb_area.position.x >= screen_size.x - orb_radius:
			orb_area.position.x = screen_size.x - orb_radius
			_heading_right = false
			_play_random_hit()
	else:
		orb_area.position.x -= movement
		if orb_area.position.x <= orb_radius:
			orb_area.position.x = orb_radius
			_heading_right = true
			_play_random_hit()


func _start_orb() -> void:
	current_speed = base_speed
	orb_area.position.x = orb_radius
	_heading_right = true


func _input(event: InputEvent) -> void:
	
	if (event is InputEventMouseButton and event.pressed) or \
	   (event is InputEventScreenTouch and event.pressed):
		_on_tap()
		get_viewport().set_input_as_handled()


func _on_tap() -> void:
	var tap_x: float = orb_area.position.x
	var threshold: float = screen_size.x * 0.1
	var dist: float = abs(tap_x - screen_size.x / 2.0)
	
	if dist < threshold:
		_on_hit(tap_x)
	else:
		_on_miss()


func _on_hit(_tap_x: float) -> void:
	score += 1
	score_label.text = str(score)
	_increase_speed()
	# print("Perfect Tap: HIT  — score: %d, speed: %.1f" % [score, current_speed])
	_play_random_hit()
	_spawn_outline_effect(Vector2(_tap_x, orb_area.position.y))
	Haptics.light()


func _spawn_outline_effect(pos: Vector2) -> void:
	if not is_instance_valid(orb_outline):
		return
	
	var clone: Sprite2D = orb_outline.duplicate()
	clone.position = pos
	clone.self_modulate.a = 1.0
	clone.visible = true
	add_child(clone)
	
	var grow: Tween = create_tween()
	grow.set_trans(Tween.TRANS_SINE)
	grow.tween_property(clone, "scale", Vector2(30, 30), outline_grow_duration)
	grow.tween_property(clone, "self_modulate:a", 0.0, outline_grow_duration * 0.7)
	
	get_tree().create_timer(5.0).timeout.connect(clone.queue_free.bind(), CONNECT_ONE_SHOT)
	
	clone.add_to_group("outline_rings")
	clone.set_meta("grow_tween", grow)


func _play_random_hit() -> void:
	var children: Array[Node] = hit_sounds.get_children()
	if children.is_empty():
		return
	
	var pool: Array[AudioStreamPlayer2D] = []
	for child in children:
		pool.append(child)
	
	if pool.size() > 1 and _last_hit_index >= 0:
		pool.remove_at(_last_hit_index)
	
	var chosen: int = randi() % pool.size()
	var player: AudioStreamPlayer2D = pool[chosen]
	_last_hit_index = children.find(player)
	player.play()


func _on_miss() -> void:
	score = 0
	score_label.text = "0"
	current_speed = base_speed
	miss_sound_audio.play()
	miss_particles.position = orb_area.position
	miss_particles.restart()
	_fade_out_rings()
	_shake_screen()
	_start_orb()
	Haptics.heavy()


func _fade_out_rings() -> void:
	for ring in get_tree().get_nodes_in_group("outline_rings"):
		if not is_instance_valid(ring):
			continue
		var old_tween: Tween = ring.get_meta("grow_tween", null) as Tween
		if old_tween and old_tween.is_valid():
			old_tween.kill()
		
		var fade: Tween = create_tween()
		fade.tween_property(ring, "self_modulate:a", 0.0, 0.25)
		fade.tween_property(ring, "scale", ring.scale * 1.5, 0.25)
		fade.finished.connect(ring.queue_free)


func _shake_screen() -> void:
	var shake: Tween = create_tween()
	shake.set_trans(Tween.TRANS_SINE)
	shake.tween_property(self, "position:x", 18.0, 0.04)
	shake.tween_property(self, "position:x", -14.0, 0.04)
	shake.tween_property(self, "position:x", 10.0, 0.04)
	shake.tween_property(self, "position:x", -6.0, 0.04)
	shake.tween_property(self, "position:x", 0.0, 0.04)

func _increase_speed() -> void:
	if current_speed >= 2000:
		current_speed = 2000
		return
	if current_speed < 800.0:
		current_speed += 60.0
	elif current_speed < 1300.0:
		current_speed += floor(mid_curve_strength / current_speed)
	else:
		current_speed += 40.0


func get_env_overrides() -> Dictionary:
	return {
		glow_enabled = true,
		glow_intensity = 1.62,
		glow_bloom = 0.6,
		glow_hdr_threshold = 0.3,
	}
