extends Node2D

const SCREEN_W: float = 1080.0
const SCREEN_H: float = 1920.0
const MAX_HP: int = 10
const AI_FIRE_INTERVAL: float = 0.5
const MAX_DRAG_LENGTH: float = 400.0
const FIRE_POWER: float = 700.0

@onready var player_ship: Area2D = $Ship
@onready var ai_ship: Area2D = $ShipAI
@onready var ai_timer: Timer = $AITimer
@onready var player_ship_sprite: Sprite2D = $Ship/Ship
@onready var ai_ship_sprite: Sprite2D = $ShipAI/Ship
@onready var player_hp_label: Label = $Control/ColorRect/PlayerHP
@onready var enemy_hp_label: Label = $Control/ColorRect/EnemyHP
@onready var particles = $Particles
@onready var curtains: Sprite2D = $Curtains
@onready var waves3: Sprite2D = $Wave3
@onready var waves2: Sprite2D = $Wave2
@onready var waves1: Sprite2D = $Wave1
@onready var result_label: Label = $Control/ColorRect/StatusLabel

@onready var cannon_fire: AudioStreamPlayer2D = $CannonFire
@onready var cannon_explosion: AudioStreamPlayer2D = $CannonExplosion

@export var cannonball_scene: PackedScene

var player_hp: int = MAX_HP
var ai_hp: int = MAX_HP
var _drag_start: Vector2 = Vector2.ZERO
var _drag_current: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _can_fire: bool = true
var _game_over: bool = false

var _player_ship_origin: Vector2
var _ai_ship_origin: Vector2
var _curtains_y: float


func _ready() -> void:
	# Setup collision
	player_ship.add_to_group("player_ship")
	ai_ship.add_to_group("ai_ship")
	
	# Connect signals
	ai_timer.timeout.connect(_on_ai_timer)
	ai_timer.start(AI_FIRE_INTERVAL)
	
	# Store original positions for sinking animation reset
	_player_ship_origin = player_ship.position
	_ai_ship_origin = ai_ship.position
	_curtains_y = curtains.position.y

	result_label.visible = false
	
	# Create HP labels near each ship
	_update_hp_labels()


func _process(_delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	waves3.position.x = 540.0 + sin(t * 0.5 * PI) * 15.0
	waves2.position.x = 540.0 + sin(t * 0.5 * PI) * 25.0
	waves1.position.x = 540.0 + sin(t * 0.5 * PI) * 30.0

func _make_hp_label(x: float, y: float) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(x - 60, y)
	label.size = Vector2(120, 30)
	add_child(label)
	return label


func _update_hp_labels() -> void:
	player_hp_label.text = "%d" % [player_hp]
	enemy_hp_label.text = "%d" % [ai_hp]


func _input(event: InputEvent) -> void:
	if _game_over:
		return
	
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		
		if event.pressed:
			_drag_start = pos
			_drag_current = pos
			_is_dragging = true
		else:
			if _is_dragging and _can_fire:
				_fire_cannonball()
			_is_dragging = false
	
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		if _is_dragging:
			_drag_current = event.position




func _fire_cannonball() -> void:
	_can_fire = false
	
	var source: Vector2 = player_ship_sprite.global_position
	var drag_vec: Vector2 = _drag_current - _drag_start
	var drag_len: float = min(drag_vec.length(), MAX_DRAG_LENGTH)
	
	# Slingshot: fire in OPPOSITE direction of drag
	var fire_dir: Vector2 = -drag_vec.normalized() if drag_vec.length() > 0 else Vector2.RIGHT
	var power: float = FIRE_POWER * (0.5 + 0.5 * drag_len / MAX_DRAG_LENGTH)
	var velocity: Vector2 = fire_dir * power
	
	var ball: Area2D = cannonball_scene.instantiate()
	ball.from_player = true
	ball.velocity = velocity
	ball.global_position = source
	add_child(ball)
	
	ball.area_entered.connect(_on_cannonball_hit.bind(ball))
	
	cannon_fire.play()
	
	# Short cooldown between shots
	get_tree().create_timer(1.0).timeout.connect(func(): _can_fire = true, CONNECT_ONE_SHOT)


func _on_cannonball_hit(other: Area2D, ball: Area2D) -> void:
	if not is_instance_valid(ball):
		return
	
	var hit_pos: Vector2 = ball.global_position
	
	# Check if hitting a ship
	if other.is_in_group("player_ship") and not ball.from_player:
		player_hp -= 1
		_update_hp_labels()
		_trigger_explosion(hit_pos)
		_shake_screen()
		ball.queue_free()
		if player_hp <= 0:
			_end_game(false)
		return
	
	if other.is_in_group("ai_ship") and ball.from_player:
		ai_hp -= 1
		_update_hp_labels()
		_trigger_explosion(hit_pos)
		ball.queue_free()
		if ai_hp <= 0:
			_end_game(true)
		return
	
	# Cannonball hitting another cannonball
	if other.is_in_group("cannonball") and other != ball:
		_trigger_explosion(hit_pos)
		ball.queue_free()
		if is_instance_valid(other):
			other.queue_free()


func _on_ai_timer() -> void:
	if _game_over:
		return
	
	# AI fires from right side toward player (left side)
	var source: Vector2 = ai_ship_sprite.global_position
	var target: Vector2 = Vector2(
		randf_range(30, SCREEN_W * 0.4),
		randf_range(SCREEN_H * 0.1, SCREEN_H * 0.9)
	)
		
	var drag_vec: Vector2 = target - source
	var fire_dir: Vector2 = (target - source).normalized()  # toward player
	var power: float = FIRE_POWER * (0.5 + 0.5 * min(drag_vec.length(), MAX_DRAG_LENGTH) / MAX_DRAG_LENGTH)
	var velocity: Vector2 = fire_dir * power
	
	var ball: Area2D = cannonball_scene.instantiate()
	ball.from_player = false
	ball.velocity = velocity
	ball.global_position = source
	add_child(ball)
	ball.area_entered.connect(_on_cannonball_hit.bind(ball))
	
	cannon_fire.play()
	
	# Next shot in 2-4 seconds
	ai_timer.start(randf_range(2.0, 4.0))


func _trigger_explosion(pos: Vector2) -> void:
	cannon_explosion.play()
	if not is_instance_valid(particles):
		return
	particles.global_position = pos
	particles.restart()


func _shake_screen() -> void:
	var shake: Tween = create_tween()
	shake.set_trans(Tween.TRANS_SINE)
	shake.tween_property(self, "position:x", 12.0, 0.03)
	shake.tween_property(self, "position:x", -10.0, 0.03)
	shake.tween_property(self, "position:x", 6.0, 0.03)
	shake.tween_property(self, "position:x", -4.0, 0.03)
	shake.tween_property(self, "position:x", 0.0, 0.03)


func _end_game(player_won: bool) -> void:
	_game_over = true
	ai_timer.stop()
	
	result_label.visible = true
	if player_won:
		result_label.text = "YOU WIN!"
	else:
		result_label.text = "YOU LOSE!"
	
	# Sink losing ship + drop curtains
	var loser: Area2D = ai_ship if player_won else player_ship
	var sink_dist: float = 500.0
	var sink_tween: Tween = create_tween().set_parallel(true)
	sink_tween.set_trans(Tween.TRANS_SINE)
	sink_tween.set_ease(Tween.EASE_IN)
	sink_tween.tween_property(loser, "position:y", loser.position.y + sink_dist, 1.2)
	sink_tween.tween_property(curtains, "position:y", 960.0, 1.0)
	
	# After curtain covers, reset
	get_tree().create_timer(1.5).timeout.connect(_reset_after_curtain, CONNECT_ONE_SHOT)


func _reset_after_curtain() -> void:
	# Reset ship positions
	player_ship.position = _player_ship_origin
	ai_ship.position = _ai_ship_origin
	
	# Free all remaining cannonballs
	for child in get_children():
		if child is Area2D and child != player_ship and child != ai_ship:
			if child.has_method("get_script"):
				var s = child.get_script()
				if s and s.resource_path == cannonball_scene.resource_path:
					child.queue_free()
	
	player_hp = MAX_HP
	ai_hp = MAX_HP
	_game_over = false
	_can_fire = true
	_update_hp_labels()
	result_label.visible = false
	
	# Raise curtains back up
	var raise_tween: Tween = create_tween()
	raise_tween.set_trans(Tween.TRANS_SINE)
	raise_tween.set_ease(Tween.EASE_OUT)
	raise_tween.tween_property(curtains, "position:y", _curtains_y, 0.6)
	raise_tween.finished.connect(_on_curtains_up)


func _on_curtains_up() -> void:
	ai_timer.start(AI_FIRE_INTERVAL)


func _restart_game() -> void:	
	# Reset ship positions
	player_ship.position = _player_ship_origin
	ai_ship.position = _ai_ship_origin
	
	# Free all remaining cannonballs
	for child in get_children():
		if child is Area2D and child != player_ship and child != ai_ship:
			if child.has_method("get_script"):
				var s = child.get_script()
				if s and s.resource_path == cannonball_scene.resource_path:
					child.queue_free()
	
	player_hp = MAX_HP
	ai_hp = MAX_HP
	_game_over = false
	_can_fire = true
	_update_hp_labels()
	result_label.visible = false
	ai_timer.start(AI_FIRE_INTERVAL)
