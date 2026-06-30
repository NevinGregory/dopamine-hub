extends Control

enum CardType { GAME, AD }

const AD_CARD_SCENE: String = "res://scenes/ads/AdCard.tscn"
const SWIPE_THRESHOLD: float = 60.0

var all_games: Array[String] = [
	"res://scenes/games/perfect_tap/PerfectTap.tscn",
	"res://scenes/games/pirate_duel/PirateDuel.tscn",
	"res://scenes/games/growth_chain/GrowthChain.tscn",
	"res://scenes/games/apex_climb/ApexClimb.tscn",
	"res://scenes/games/symmetry/Symmetry.tscn",
	"res://scenes/games/velocity_drift/VelocityDrift.tscn",
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
var _trans_tween: Tween
var _transitioning: bool = false


func _ready() -> void:
	randomize()
	_next_ad_at = randi_range(3, 5)
	_card_height = _get_viewport_size().y
	
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	
	_refill_queue()
	
	for i in 3:
		var card: SubViewportContainer = _create_card_from_queue()
		_cards[i] = card
		add_child(card)
	
	_position_cards()
	_set_card_active(1, true)


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
	elif is_release:
		var dy: float = pos.y - _touch_start_pos.y
		if abs(dy) < SWIPE_THRESHOLD:
			_forward_tap(pos)
		else:
			_commit_swipe()
		_is_swiping = false
	elif is_drag:
		var dy: float = pos.y - _touch_start_pos.y
		if not _is_swiping and abs(dy) > SWIPE_THRESHOLD:
			_is_swiping = true
			accept_event()
			_kill_tween()
			_set_card_active(1, false)
		if _is_swiping:
			accept_event()
			_card_offset = dy
			_position_cards()


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
	_transitioning = true
	_kill_tween()
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
	_transitioning = false


func _on_snap_done() -> void:
	_card_offset = 0.0
	_position_cards()
	_set_card_active(1, true)
	_transitioning = false


# ── Tap forwarding ──

func _forward_tap(pos: Vector2) -> void:
	var card: SubViewportContainer = _cards[1]
	if not is_instance_valid(card) or card.get_child_count() == 0:
		return
	
	var viewport: SubViewport = card.get_child(0)
	if not viewport:
		return
	
	var local_pos: Vector2 = pos - card.position
	
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = local_pos
	viewport.push_input(press)
	
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = local_pos
	viewport.push_input(release)


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
	vp.transparent_bg = true
	vp.handle_input_locally = true
	svc.add_child(vp)
	
	var scene: PackedScene = load(scene_path)
	if scene:
		var inst: Node = scene.instantiate()
		vp.add_child(inst)
		inst.set_process(false)
		inst.set_physics_process(false)
	
	return svc


# ── Card lifecycle ──

func _set_card_active(index: int, active: bool) -> void:
	var card: SubViewportContainer = _cards[index]
	if not is_instance_valid(card) or card.get_child_count() == 0:
		return
	
	var vp: SubViewport = card.get_child(0)
	if not vp or vp.get_child_count() == 0:
		return
	
	var node: Node = vp.get_child(0)
	node.set_process(active)
	node.set_physics_process(active)


func _kill_tween() -> void:
	if _trans_tween and _trans_tween.is_valid():
		_trans_tween.kill()
