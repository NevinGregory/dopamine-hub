extends Control

enum CardType { GAME, AD }

const AD_CARD_SCENE: String = "res://scenes/ads/AdCard.tscn"
const STARTUP_SCENE: String = "res://scenes/feed_hub/Startup.tscn"
const SWIPE_THRESHOLD: float = 60.0

var all_games: Array[String] = [
	"res://scenes/games/perfect_tap/PerfectTap.tscn",
	"res://scenes/games/pirate_duel/PirateDuel.tscn",
	"res://scenes/games/growth_chain/GrowthChain.tscn",
	#"res://scenes/games/apex_climb/ApexClimb.tscn",
	"res://scenes/games/flow/Flow.tscn",
	#"res://scenes/games/velocity_drift/VelocityDrift.tscn",
]

# Infinite queue
var _unplayed_games: Array[String] = []
var _card_queue: Array[Dictionary] = []
var _games_since_last_ad: int = 0
var _next_ad_at: int = 3

# Duplicate prevention — remember the last game shown to avoid back-to-back repeats
var _last_game_path: String = ""
var _last_was_ad: bool = false

# Three visible cards — always [prev_above, current_center, next_below]
var _cards: Array[SubViewportContainer] = [null, null, null]

# Swipe state
var _card_height: float = 0.0
var _card_offset: float = 0.0
var _touch_start_pos: Vector2 = Vector2.ZERO
var _is_swiping: bool = false
var _is_horizontal_swiping: bool = false
var _trans_tween: Tween
var _transitioning: bool = false
var _glow_fade_tween: Tween = null

@onready var _world_env: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	randomize()
	_next_ad_at = randi_range(3, 5)
	_card_height = _get_viewport_size().y
	
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	
	_refill_queue()
	
	# First card is always Startup, surround with queue cards
	_cards[0] = _create_card_from_queue()
	_cards[1] = _build_card(STARTUP_SCENE)
	_cards[2] = _create_card_from_queue()
	
	for card in _cards:
		add_child(card)
	
	_position_cards()
	_set_card_active(1, true)
	
	# Fade startup's cover from opaque to transparent on first reveal
	var cover: Control = _get_cover_node(_cards[1])
	if cover:
		cover.modulate.a = 1.0
		var cover_tween: Tween = create_tween()
		cover_tween.set_trans(Tween.TRANS_SINE)
		cover_tween.set_ease(Tween.EASE_OUT)
		cover_tween.tween_property(cover, "modulate:a", 0.0, 0.3)


func _get_viewport_size() -> Vector2:
	var s: Vector2 = Vector2(1080, 1920)
	if is_inside_tree() and get_viewport():
		s = get_viewport().get_visible_rect().size
	return s


# ── Positioning (cards 0,1,2 always at -H, 0, H + _card_offset) ──

func _position_cards() -> void:
	var w: float = _card_height * 9.0 / 16.0
	var x: float = (size.x - w) * 0.5
	
	for i in 3:
		var card: SubViewportContainer = _cards[i]
		if not is_instance_valid(card):
			continue
		card.position = Vector2(x, (i - 1) * _card_height + _card_offset)


# ── Input ──

func _on_gui_input(event: InputEvent) -> void:
	if _transitioning:
		accept_event()
		return
	
	var is_press: bool = false
	var is_release: bool = false
	var is_drag: bool = false
	var pos: Vector2 = Vector2.ZERO
	
	if event is InputEventMouseButton:
		is_press = event.pressed
		is_release = not event.pressed
		pos = event.position
	elif event is InputEventScreenTouch:
		is_press = event.pressed
		is_release = not event.pressed
		pos = event.position
	elif event is InputEventScreenDrag:
		is_drag = true
		pos = event.position
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		is_drag = true
		pos = event.position
	
	if is_press:
		_touch_start_pos = pos
		_is_swiping = false
		_is_horizontal_swiping = false
		_forward_press(pos)
	elif is_release:
		var dy: float = pos.y - _touch_start_pos.y
		if _is_horizontal_swiping:
			_is_horizontal_swiping = false
		elif abs(dy) >= SWIPE_THRESHOLD and not _is_swiping:
			_forward_release(pos)
		
		if _is_swiping:
			_commit_swipe()
		else:
			_forward_release(pos)
		
		_is_swiping = false
		_is_horizontal_swiping = false
	elif is_drag:
		var dx: float = pos.x - _touch_start_pos.x
		var dy: float = pos.y - _touch_start_pos.y
		
		if not _is_swiping and not _is_horizontal_swiping:
			if abs(dy) > SWIPE_THRESHOLD:
				_is_swiping = true
				_forward_release(pos)  # cancel hold on current card
				accept_event()
				_kill_tween()
				_set_card_active(1, false)
			elif abs(dx) > SWIPE_THRESHOLD:
				_is_horizontal_swiping = true
				accept_event()
		
		if _is_swiping:
			accept_event()
			_card_offset = dy
			_position_cards()
		elif _is_horizontal_swiping:
			accept_event()
			_forward_drag(pos)


# ── Swipe commit ──

func _commit_swipe() -> void:
	if _card_offset < -_card_height * 0.3:
		_swipe_next()
	elif _card_offset > _card_height * 0.3:
		_swipe_prev()
	else:
		_snap_back()


func _swipe_next() -> void:
	_animate_offset(-_card_height, _on_advance_next)


func _swipe_prev() -> void:
	_animate_offset(_card_height, _on_advance_prev)


func _snap_back() -> void:
	_animate_offset(0.0, _on_snap_done)


func _animate_offset(target: float, callback: Callable) -> void:
	_reset_environment()
	_transitioning = true
	_kill_tween()
	
	# Set all cards' covers to opaque before transition
	for i in 3:
		var cover: Control = _get_cover_node(_cards[i])
		if cover:
			cover.modulate.a = 1.0
	
	_trans_tween = create_tween()
	_trans_tween.set_trans(Tween.TRANS_CUBIC)
	_trans_tween.set_ease(Tween.EASE_OUT)
	_trans_tween.tween_method(_animate_offset_step, _card_offset, target, 0.30)
	_trans_tween.finished.connect(callback)


func _animate_offset_step(val: float) -> void:
	_card_offset = val
	_position_cards()


func _on_advance_next() -> void:
	# Card 0 slid off the top — recycle to bottom
	var off_card: SubViewportContainer = _cards.pop_front()
	if is_instance_valid(off_card):
		off_card.queue_free()
	
	var new_card: SubViewportContainer = _create_card_safe()
	_cards.append(new_card)
	add_child(_cards[2])
	
	_card_offset = 0.0
	_position_cards()
	_set_card_active(1, true)
	_update_environment_for_active_card()
	
	# Fade cover on new center card from opaque to transparent
	var cover: Control = _get_cover_node(_cards[1])
	if cover:
		cover.modulate.a = 1.0
		var cover_tween: Tween = create_tween()
		cover_tween.set_trans(Tween.TRANS_SINE)
		cover_tween.set_ease(Tween.EASE_OUT)
		cover_tween.tween_property(cover, "modulate:a", 0.0, 0.3)
	
	_transitioning = false


func _on_advance_prev() -> void:
	# Card 2 slid off the bottom — recycle to top
	var off_card: SubViewportContainer = _cards.pop_back()
	if is_instance_valid(off_card):
		off_card.queue_free()
	
	var new_card: SubViewportContainer = _create_card_safe()
	_cards.push_front(new_card)
	add_child(_cards[0])
	
	_card_offset = 0.0
	_position_cards()
	_set_card_active(1, true)
	_update_environment_for_active_card()
	
	# Fade cover on new center card from opaque to transparent
	var cover: Control = _get_cover_node(_cards[1])
	if cover:
		cover.modulate.a = 1.0
		var cover_tween: Tween = create_tween()
		cover_tween.set_trans(Tween.TRANS_SINE)
		cover_tween.set_ease(Tween.EASE_OUT)
		cover_tween.tween_property(cover, "modulate:a", 0.0, 0.3)
	
	_transitioning = false


func _on_snap_done() -> void:
	_card_offset = 0.0
	_position_cards()
	_set_card_active(1, true)
	_update_environment_for_active_card()
	
	# Fade cover on center card from opaque to transparent
	var cover: Control = _get_cover_node(_cards[1])
	if cover:
		cover.modulate.a = 1.0
		var cover_tween: Tween = create_tween()
		cover_tween.set_trans(Tween.TRANS_SINE)
		cover_tween.set_ease(Tween.EASE_OUT)
		cover_tween.tween_property(cover, "modulate:a", 0.0, 0.3)
	
	_transitioning = false


# ── Tap forwarding ──

func _forward_press(pos: Vector2) -> void:
	var card: SubViewportContainer = _cards[1]
	if not is_instance_valid(card) or card.get_child_count() == 0:
		return
	
	var viewport: SubViewport = card.get_child(0)
	if not viewport:
		return
	
	var local_pos: Vector2 = pos - card.position
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = local_pos
	viewport.push_input(ev)


func _forward_release(pos: Vector2) -> void:
	var card: SubViewportContainer = _cards[1]
	if not is_instance_valid(card) or card.get_child_count() == 0:
		return
	
	var viewport: SubViewport = card.get_child(0)
	if not viewport:
		return
	
	var local_pos: Vector2 = pos - card.position
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = local_pos
	viewport.push_input(ev)


func _forward_drag(pos: Vector2) -> void:
	var card: SubViewportContainer = _cards[1]
	if not is_instance_valid(card) or card.get_child_count() == 0:
		return
	
	var viewport: SubViewport = card.get_child(0)
	if not viewport:
		return
	
	var local_pos: Vector2 = pos - card.position
	
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.position = local_pos
	viewport.push_input(drag)


# ── Infinite queue ──

func _refill_queue() -> void:
	if _unplayed_games.is_empty():
		_unplayed_games = all_games.duplicate()
		_unplayed_games.shuffle()
	
	var batch: int = randi_range(3, 5)
	for _i in batch:
		if _card_queue.size() >= 12:
			break
		_games_since_last_ad += 1
		
		if _games_since_last_ad >= _next_ad_at and not _unplayed_games.is_empty():
			_games_since_last_ad = 0
			_next_ad_at = randi_range(3, 5)
			_card_queue.append({ type = CardType.AD, path = AD_CARD_SCENE })
		
		if not _unplayed_games.is_empty():
			_card_queue.append({ type = CardType.GAME, path = _unplayed_games.pop_front() })


func _pop_from_queue() -> Dictionary:
	if _card_queue.size() < 3:
		_refill_queue()
	return _card_queue.pop_front()


func _pop_safe() -> Dictionary:
	# Skip queue entries that would repeat the same game or place two ads in a row
	for _attempt in min(_card_queue.size(), 3):
		_refill_queue()
		if _card_queue.size() == 0:
			break
		
		var peek: Dictionary = _card_queue[0]
		var peek_path: String = AD_CARD_SCENE if peek.type == CardType.AD else peek.path
		
		var is_dup: bool = false
		if peek.type == CardType.GAME and peek_path == _last_game_path:
			is_dup = true
		elif peek.type == CardType.AD and _last_was_ad:
			is_dup = true
		
		if is_dup and _card_queue.size() > 1:
			_card_queue.append(_card_queue.pop_front())
			continue
		
		break
	
	var data: Dictionary = _card_queue.pop_front()
	
	if data.type == CardType.GAME:
		_last_game_path = data.path
		_last_was_ad = false
	else:
		_last_was_ad = true
	
	return data


# ── Card building ──

func _create_card_from_queue() -> SubViewportContainer:
	var data: Dictionary = _pop_from_queue()
	var path: String = AD_CARD_SCENE if data.type == CardType.AD else data.path
	return _build_card(path)


func _create_card_safe() -> SubViewportContainer:
	var data: Dictionary = _pop_safe()
	var path: String = AD_CARD_SCENE if data.type == CardType.AD else data.path
	return _build_card(path)


func _build_card(scene_path: String) -> SubViewportContainer:
	var card_size: Vector2 = Vector2(_card_height * 9.0 / 16.0, _card_height)
	
	var svc: SubViewportContainer = SubViewportContainer.new()
	svc.size = card_size
	svc.custom_minimum_size = card_size
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var vp: SubViewport = SubViewport.new()
	vp.size = card_size
	vp.transparent_bg = false
	vp.handle_input_locally = true
	vp.audio_listener_enable_2d = true
	svc.add_child(vp)
	
	# Store path as metadata — scene loads on first activation
	vp.set_meta("scene_path", scene_path)
	
	return svc


func _ensure_card_loaded(vp: SubViewport) -> void:
	if vp.get_child_count() > 0:
		return  # already loaded
	var path: String = vp.get_meta("scene_path", "")
	if not path:
		return
	var scene: PackedScene = load(path)
	if not scene:
		return
	var inst: Node = scene.instantiate()
	vp.add_child(inst)
	inst.set_process(false)
	inst.set_physics_process(false)
	inst.set_process_input(false)


# ── Card lifecycle ──

func _set_card_active(index: int, active: bool) -> void:
	var card: SubViewportContainer = _cards[index]
	if not is_instance_valid(card) or card.get_child_count() == 0:
		return
	
	var vp: SubViewport = card.get_child(0)
	if not vp:
		return
	
	# Load scene on first activation
	if active:
		_ensure_card_loaded(vp)
	
	if vp.get_child_count() == 0:
		return
	
	var node: Node = vp.get_child(0)
	node.set_process(active)
	node.set_physics_process(active)
	node.set_process_input(active)


func _reset_environment() -> void:
	if not is_instance_valid(_world_env) or not _world_env.environment:
		return
	var env: Environment = _world_env.environment
	env.glow_enabled = false
	env.glow_intensity = 1.0
	env.glow_bloom = 0.5
	env.glow_hdr_threshold = 1.0


func _apply_environment(overrides: Dictionary) -> void:
	if not is_instance_valid(_world_env) or not _world_env.environment:
		return
	var env: Environment = _world_env.environment
	if overrides.has("glow_enabled"):
		env.glow_enabled = overrides.glow_enabled
	if overrides.has("glow_intensity"):
		env.glow_intensity = overrides.glow_intensity
	if overrides.has("glow_bloom"):
		env.glow_bloom = overrides.glow_bloom
	if overrides.has("glow_hdr_threshold"):
		env.glow_hdr_threshold = overrides.glow_hdr_threshold


func _update_environment_for_active_card() -> void:
	_reset_environment()
	
	# Kill any in-progress glow fade
	if _glow_fade_tween and _glow_fade_tween.is_valid():
		_glow_fade_tween.kill()
	_glow_fade_tween = null
	
	var card: SubViewportContainer = _cards[1]
	if not is_instance_valid(card) or card.get_child_count() == 0:
		return
	
	var vp: SubViewport = card.get_child(0)
	if not vp or vp.get_child_count() == 0:
		return
	
	var node: Node = vp.get_child(0)
	if node.has_method("get_env_overrides"):
		var overrides: Dictionary = node.get_env_overrides()
		_apply_environment(overrides)
		
		# Fade glow intensity in from 0
		if not is_instance_valid(_world_env) or not _world_env.environment:
			return
		var target_intensity: float = overrides.get("glow_intensity", 1.0)
		_world_env.environment.glow_intensity = 0.0
		
		_glow_fade_tween = create_tween()
		_glow_fade_tween.set_trans(Tween.TRANS_SINE)
		_glow_fade_tween.set_ease(Tween.EASE_OUT)
		_glow_fade_tween.tween_property(_world_env.environment, "glow_intensity", target_intensity, 0.15)


func _kill_tween() -> void:
	if _trans_tween and _trans_tween.is_valid():
		_trans_tween.kill()


func _get_cover_node(card: SubViewportContainer) -> Control:
	"""Get the Cover overlay node from the game scene inside a card's subviewport."""
	if not is_instance_valid(card) or card.get_child_count() == 0:
		return null
	var vp: SubViewport = card.get_child(0)
	if not vp or vp.get_child_count() == 0:
		return null
	var game_root: Node = vp.get_child(0)
	if not game_root.has_node("Cover"):
		return null
	return game_root.get_node("Cover")
