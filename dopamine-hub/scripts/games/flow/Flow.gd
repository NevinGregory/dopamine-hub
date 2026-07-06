extends Node2D

enum PipeType { BLANK, STRAIGHT, CORNER, T_PIPE, CROSS, SOURCE, DEST }

const CELL_PADDING: int = 4
const PIPE_RADIUS: float = 20.0
const NUB_WIDTH: float = 16.0
const NUB_HEIGHT_FACTOR: float = 0.5

# Base connections for rotation=0: [top, right, bottom, left]
const BASE_CONNECTIONS: Dictionary = {
	PipeType.BLANK:    [false, false, false, false],
	PipeType.STRAIGHT: [true, false, true, false],
	PipeType.CORNER:   [true, true, false, false],
	PipeType.T_PIPE:   [true, true, true, false],
	PipeType.CROSS:    [true, true, true, true],
	PipeType.SOURCE:   [false, true, false, false],
	PipeType.DEST:     [true, false, false, false],
}

const COLOR_CELL_BG: Color = Color(0.12, 0.14, 0.16)
const COLOR_GRID_LINE: Color = Color(0.3, 0.3, 0.35)
const COLOR_PIPE_BODY: Color = Color(0.7, 0.7, 0.8)
const COLOR_SOURCE: Color = Color(0.0, 0.8, 0.9)
const COLOR_DEST: Color = Color(1.0, 0.8, 0.0)
const COLOR_CONNECTED: Color = Color(0.2, 1.0, 0.4)
const COLOR_SUCCESS_TEXT: Color = Color(0.2, 1.0, 0.4)

@onready var level_label: Label = $Control/LevelLabel
@onready var gear: Sprite2D = $Gear
@onready var gear2: Sprite2D = $Gear2
@onready var click_sound: AudioStreamPlayer2D = $Click
@onready var flow_sound: AudioStreamPlayer2D = $FlowIn
@onready var solved_sound: AudioStreamPlayer2D = $SolvedSound

var grid: Array[Dictionary] = []
var source_pos: Vector2i = Vector2i.ZERO
var dest_pos: Vector2i = Vector2i.ZERO
var _solved: bool = false
var level: int = 1
var score: int = 0

var _grid_cols: int = 10
var _grid_rows: int = 10
var _cell_size: int = 100

var _grid_offset: Vector2 = Vector2.ZERO
var _animating: bool = false
var _path_cells: Array[Vector2i] = []
var _puzzle_alpha: float = 1.0
var _cell_flash: Dictionary = {}
var _rotating_cells: Dictionary = {}  # "col,row" -> {from_angle, to_angle, elapsed, duration}
var _flow_progress: float = 0.0  # 0→1 during solved flow animation along path


func _ready() -> void:
	randomize()
	set_process(true)
	_new_puzzle()


func _calculate_grid_offset() -> void:
	var view_size: Vector2 = get_viewport_rect().size
	var available: float = view_size.x * 0.85
	_cell_size = floori(available / _grid_cols)
	var grid_pixels: float = _grid_cols * _cell_size
	var center_x: float = (view_size.x - grid_pixels) * 0.5
	var top_y: float = max(160.0, (view_size.y - grid_pixels - 200.0) * 0.5 + 80.0)
	_grid_offset = Vector2(center_x, top_y)


func _set_grid_size_for_level() -> void:
	# Progress: 5x5 -> 5x6 -> 6x6 -> 6x7 -> 7x7 -> ... capped at 9x9
	var steps: int = int((level - 1) / 2.0)
	var base: int = int(5 + steps / 2.0)
	var extra: int = steps % 2
	_grid_cols = mini(base + extra, 9)
	_grid_rows = mini(base, 9)


func _new_puzzle() -> void:
	_solved = false
	_animating = false
	_path_cells.clear()
	_flow_progress = 0.0

	# Set grid size for current level (before grid init)
	_set_grid_size_for_level()

	# Reset grid with new dimensions
	grid.clear()
	for i in _grid_rows * _grid_cols:
		grid.append({ "pipe_type": PipeType.STRAIGHT, "rotation": 0 })

	# Source always top-left, destination always bottom-right
	source_pos = Vector2i(0, 0)
	dest_pos = Vector2i(_grid_cols - 1, _grid_rows - 1)

	# Generate path from source to dest
	var path: Array[Vector2i] = _generate_path(source_pos, dest_pos)

	if path.is_empty() or path[-1] != dest_pos:
		# fallback: simple straight-ish path
		path = _simple_fallback_path(source_pos, dest_pos)

	# Recalculate offset for new grid size
	_calculate_grid_offset()

	# Mark path cells
	_path_cells = path.duplicate()

	# Place SOURCE at path[0]
	var first_step_dir: int = _direction_from_to(path[0], path[1])
	var source_rot: int = _source_rotation_for_dir(first_step_dir)
	_set_cell(path[0].x, path[0].y, PipeType.SOURCE, source_rot)

	# Place DEST at path[-1]
	var last_step_dir: int = _direction_from_to(path[-2], path[-1])
	var dest_rot: int = _dest_rotation_for_dir(last_step_dir)
	_set_cell(path[-1].x, path[-1].y, PipeType.DEST, dest_rot)

	# Set middle path cells
	for i in range(1, path.size() - 1):
		var prev: Vector2i = path[i - 1]
		var curr: Vector2i = path[i]
		var next_cell: Vector2i = path[i + 1]
		var in_dir: int = _direction_from_to(prev, curr)  # direction we entered curr from
		var out_dir: int = _direction_from_to(curr, next_cell)  # direction we leave curr to

		# in_dir and out_dir are absolute directions.
		# The cell's connection at (in_dir + 2) % 4 must be open (entering from opposite side)
		# and connection at out_dir must be open.
		var cell_in_side: int = (in_dir + 2) % 4  # side of cell that faces prev
		var cell_out_side: int = out_dir  # side of cell that faces next

		if cell_in_side == cell_out_side:
			# shouldn't happen in a valid path
			_set_cell(curr.x, curr.y, PipeType.STRAIGHT, 0)
		elif (cell_in_side + 2) % 4 == cell_out_side:
			# straight through
			var rot: int = _straight_rotation_for(cell_in_side, cell_out_side)
			_set_cell(curr.x, curr.y, PipeType.STRAIGHT, rot)
		else:
			# corner turn
			var rot: int = _corner_rotation_for(cell_in_side, cell_out_side)
			_set_cell(curr.x, curr.y, PipeType.CORNER, rot)

	# Fill off-path cells with BLANK (non-interactive boxes)
	for row in _grid_rows:
		for col in _grid_cols:
			if not _is_path_cell(Vector2i(col, row)):
				_set_cell(col, row, PipeType.BLANK, 0)

	# Randomly rotate all cells (including source/dest) to hide solution
	for row in _grid_rows:
		for col in _grid_cols:
			var r: int = randi() % 4
			var idx: int = row * _grid_cols + col
			grid[idx].rotation = r

	_update_labels()
	# Fade-in animation
	_puzzle_alpha = 0.0
	var fade_tween: Tween = create_tween()
	fade_tween.tween_method(_set_puzzle_alpha, 0.0, 1.0, 0.3).set_ease(Tween.EASE_OUT)


func _set_puzzle_alpha(v: float) -> void:
	_puzzle_alpha = v
	queue_redraw()


func _set_cell(col: int, row: int, pipe_type: PipeType, r: int) -> void:
	var idx: int = row * _grid_cols + col
	grid[idx] = { "pipe_type": pipe_type, "rotation": r }


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _direction_from_to(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var diff: Vector2i = to_cell - from_cell
	if diff.x == 1: return 1  # right
	if diff.x == -1: return 3  # left
	if diff.y == 1: return 2  # down
	if diff.y == -1: return 0  # up
	return -1


func _opposite_dir(d: int) -> int:
	return (d + 2) % 4


# SOURCE base opens at index 1 (right). Need rotation so it opens at `dir`.
func _source_rotation_for_dir(dir: int) -> int:
	return (dir - 1 + 4) % 4


# DEST base opens at index 0 (top). Need rotation so it opens at `dir` (side facing prev cell).
func _dest_rotation_for_dir(in_dir: int) -> int:
	# DEST base opens at direction 0 (top).
	# The previous path cell is at direction (in_dir + 2) % 4 from dest.
	# Dest must open toward that cell.
	return (in_dir + 2) % 4


# For STRAIGHT: base [top, right, bottom, left] opens at 0 and 2.
# Need rotation so opens at side_a and side_b (which are opposite).
func _straight_rotation_for(side_a: int, _side_b: int) -> int:
	# Since STRAIGHT opens at r and (r+2)%4, r must be one of the sides.
	# side_a and side_b are opposite (confirmed by caller).
	return side_a % 4


# For CORNER: base [top, right, bottom, left] opens at 0 and 1.
# Need rotation so opens at side_a and side_b (adjacent, clockwise order).
func _corner_rotation_for(side_a: int, side_b: int) -> int:
	# CORNER at rotation r opens at r and (r+1)%4.
	# Try both orderings
	if (side_a + 1) % 4 == side_b:
		return side_a % 4
	else:  # (side_b + 1) % 4 == side_a
		return side_b % 4


func _is_path_cell(pos: Vector2i) -> bool:
	for p in _path_cells:
		if p == pos:
			return true
	return false


func _generate_path(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var max_steps: int = 50
	var path: Array[Vector2i] = [start]
	var current: Vector2i = start
	var visited: Array[Vector2i] = [start]

	for _step in max_steps:
		if current == end:
			return path

		var neighbors: Array[Vector2i] = []
		var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

		for d in dirs:
			var next_cell: Vector2i = current + d
			if next_cell.x >= 0 and next_cell.x < _grid_cols and next_cell.y >= 0 and next_cell.y < _grid_rows:
				if not _has_visited(visited, next_cell):
					neighbors.append(next_cell)

		if neighbors.is_empty():
			# Dead end, backtrack
			if path.size() <= 1:
				return []
			path.pop_back()
			current = path[-1]
			continue

		# Prefer moving toward dest (70%) vs random (30%)
		var target: Vector2i
		if randf() < 0.2:
			# Pick neighbor closest to end
			var best_dist: int = 999
			for n in neighbors:
				var dist: int = _manhattan(n, end)
				if dist < best_dist:
					best_dist = dist
					target = n
		else:
			target = neighbors[randi() % neighbors.size()]

		path.append(target)
		visited.append(target)
		current = target

	return path  # may or may not have reached dest


func _has_visited(arr: Array[Vector2i], pos: Vector2i) -> bool:
	for p in arr:
		if p == pos:
			return true
	return false


func _simple_fallback_path(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	# Generate a simple path by going horizontal then vertical
	var path: Array[Vector2i] = [start]
	var current: Vector2i = start

	# Go horizontal
	while current.x != end.x:
		var step: int = 1 if end.x > current.x else -1
		current = Vector2i(current.x + step, current.y)
		path.append(current)

	# Go vertical
	while current.y != end.y:
		var step: int = 1 if end.y > current.y else -1
		current = Vector2i(current.x, current.y + step)
		path.append(current)

	return path


func _get_connections(pipe_type: PipeType, r: int) -> Array[bool]:
	var base: Array = BASE_CONNECTIONS[pipe_type]
	var result: Array[bool] = [false, false, false, false]
	for i in 4:
		result[(i + r) % 4] = base[i]
	return result


func _input(event: InputEvent) -> void:
	
	if _animating or _solved:
		return

	if (event is InputEventMouseButton and event.pressed) or \
	   (event is InputEventScreenTouch and event.pressed):
		var pos: Vector2 = event.position

		var local_pos: Vector2 = pos - _grid_offset
		var col: int = int(local_pos.x / _cell_size)
		var row: int = int(local_pos.y / _cell_size)

		if col >= 0 and col < _grid_cols and row >= 0 and row < _grid_rows:
			# Skip BLANK cells — they're locked boxes
			var idx: int = row * _grid_cols + col
			if grid[idx].pipe_type == PipeType.BLANK:
				return
			click_sound.playing = true
			Haptics.light()
			_rotate_cell(col, row)
			if _validate_flow():
				_on_solved()
		get_viewport().set_input_as_handled()


func _rotate_cell(col: int, row: int) -> void:
	var idx: int = row * _grid_cols + col
	var new_rot: int = (grid[idx].rotation + 1) % 4
	var anim_key: String = "%d,%d" % [col, row]
	
	# Start rotation animation (old angle -> new angle)
	_rotating_cells[anim_key] = {
		"from_angle": grid[idx].rotation * PI / 2.0,
		"to_angle": new_rot * PI / 2.0,
		"elapsed": 0.0,
		"duration": 0.15
	}
	
	# Commit rotation immediately (so validation uses the new state)
	grid[idx].rotation = new_rot
	set_process(true)
	
	# Flash feedback
	_cell_flash[anim_key] = 0.12


func _validate_flow() -> bool:
	if grid.is_empty():
		_solved = false
		return false

	var visited: Array[Vector2i] = []
	var queue: Array[Vector2i] = [source_pos]
	visited.append(source_pos)

	while not queue.is_empty():
		var curr: Vector2i = queue.pop_front()
		var idx: int = curr.y * _grid_cols + curr.x
		var data: Dictionary = grid[idx]
		var conns: Array[bool] = _get_connections(data.pipe_type, data.rotation)

		# Check each direction
		var dirs: Array = [
			Vector2i(0, -1),  # top (dir 0)
			Vector2i(1, 0),   # right (dir 1)
			Vector2i(0, 1),   # bottom (dir 2)
			Vector2i(-1, 0),  # left (dir 3)
		]

		for d_idx in 4:
			if not conns[d_idx]:
				continue  # no opening on this side

			var neighbor: Vector2i = curr + dirs[d_idx]
			if neighbor.x < 0 or neighbor.x >= _grid_cols or neighbor.y < 0 or neighbor.y >= _grid_rows:
				continue

			if _has_visited(visited, neighbor):
				continue

			var n_idx: int = neighbor.y * _grid_cols + neighbor.x
			var n_data: Dictionary = grid[n_idx]
			var n_conns: Array[bool] = _get_connections(n_data.pipe_type, n_data.rotation)
			var opposite_side: int = (d_idx + 2) % 4

			if not n_conns[opposite_side]:
				continue  # neighbor doesn't open toward us

			if neighbor == dest_pos:
				_solved = true
				return true

			visited.append(neighbor)
			queue.append(neighbor)

	_solved = false
	return false


func _on_solved() -> void:
	_solved = true
	_animating = true
	_flow_progress = 0.0
	
	Haptics.success()
	rotate_360(gear)
	rotate_360(gear2)
	
	# Animate flow along the path
	var duration: float = max(1.0, _path_cells.size() * 0.12)
	var flow_tween: Tween = create_tween()
	flow_tween.set_ease(Tween.EASE_IN)
	flow_tween.tween_method(_set_flow_progress, 0.0, 1.0, duration)
	flow_tween.tween_callback(_on_flow_complete)


func _set_flow_progress(v: float) -> void:
	# Play tick sound each time a new cell on the path turns green
	var prev_cell: int = floori(_flow_progress * _path_cells.size())
	var new_cell: int = floori(v * _path_cells.size())
	if new_cell > prev_cell and new_cell < _path_cells.size():
		flow_sound.play()
	_flow_progress = v
	queue_redraw()


func _on_flow_complete() -> void:
	score += 1
	level += 1
	if is_instance_valid(solved_sound):
		solved_sound.play()
	_update_labels()
	queue_redraw()

	# After 1.5 seconds, start new puzzle
	get_tree().create_timer(1.0).timeout.connect(_on_solved_timer_end, CONNECT_ONE_SHOT)


func _on_solved_timer_end() -> void:
	_new_puzzle()


func _update_labels() -> void:
	level_label.text = "Level %d" % level


func _process(delta: float) -> void:
	var redraw: bool = false
	
	# Advance rotation animations
	for key in _rotating_cells.keys():
		var anim: Dictionary = _rotating_cells[key]
		anim.elapsed += delta
		if anim.elapsed >= anim.duration:
			_rotating_cells.erase(key)
		redraw = true
	
	# Advance flash feedback
	for key in _cell_flash.keys():
		_cell_flash[key] -= delta
		if _cell_flash[key] <= 0.0:
			_cell_flash.erase(key)
		redraw = true
	
	if redraw:
		queue_redraw()


func _draw_rounded_rect(rect: Rect2, color: Color, radius: float = 8.0) -> void:
	var pos: Vector2 = rect.position
	var size: Vector2 = rect.size
	var r: float = min(radius, size.x * 0.5, size.y * 0.5)
	# Body
	draw_rect(Rect2(pos.x + r, pos.y, size.x - r * 2.0, size.y), color)
	draw_rect(Rect2(pos.x, pos.y + r, r, size.y - r * 2.0), color)
	draw_rect(Rect2(pos.x + size.x - r, pos.y + r, r, size.y - r * 2.0), color)
	# Four corner circles
	draw_circle(pos + Vector2(r, r), r, color)
	draw_circle(pos + Vector2(size.x - r, r), r, color)
	draw_circle(pos + Vector2(r, size.y - r), r, color)
	draw_circle(pos + Vector2(size.x - r, size.y - r), r, color)


func _draw() -> void:
	if grid.is_empty():
		return

	for row in _grid_rows:
		for col in _grid_cols:
			_draw_cell(col, row)


func _draw_cell(col: int, row: int) -> void:
	var idx: int = row * _grid_cols + col
	var data: Dictionary = grid[idx]
	var cell_pos: Vector2 = _grid_offset + Vector2(col * _cell_size, row * _cell_size)
	var rect: Rect2 = Rect2(cell_pos, Vector2(_cell_size, _cell_size))

	# Draw cell background (rounded)
	_draw_rounded_rect(rect, COLOR_CELL_BG * _puzzle_alpha, 8.0)

	# BLANK cells are empty boxes — no pipe, no nubs
	if data.pipe_type == PipeType.BLANK:
		return

	var center: Vector2 = cell_pos + Vector2(_cell_size * 0.5, _cell_size * 0.5)
	var _conns: Array[bool] = _get_connections(data.pipe_type, data.rotation)

	# Determine color
	var pipe_color: Color = COLOR_PIPE_BODY
	if data.pipe_type == PipeType.SOURCE:
		pipe_color = COLOR_SOURCE
	elif data.pipe_type == PipeType.DEST:
		pipe_color = COLOR_DEST

	# Flow animation — progressively color path cells green from source to dest
	if _flow_progress > 0.0 and _is_path_cell(Vector2i(col, row)):
		var cell_idx: int = -1
		for i in range(_path_cells.size()):
			if _path_cells[i].x == col and _path_cells[i].y == row:
				cell_idx = i
				break
		if cell_idx >= 0:
			var threshold: float = float(cell_idx) / float(_path_cells.size())
			if _flow_progress >= threshold:
				pipe_color = COLOR_CONNECTED
	
	# Fully solved — all path cells green (covers edge case where flow just finished)
	if _solved and _flow_progress >= 1.0 and _is_path_cell(Vector2i(col, row)):
		pipe_color = COLOR_CONNECTED

	# Fade-in multiplier
	pipe_color *= _puzzle_alpha

	# Flash feedback on rotate
	var flash_key: String = "%d,%d" % [col, row]
	if _cell_flash.has(flash_key):
		var flash_ratio: float = _cell_flash[flash_key] / 0.12
		pipe_color = pipe_color.lightened(flash_ratio * 0.4)

	# Compute visual rotation angle (interpolated during animation)
	var angle: float = data.rotation * PI / 2.0
	var anim_key: String = "%d,%d" % [col, row]
	if _rotating_cells.has(anim_key):
		var anim: Dictionary = _rotating_cells[anim_key]
		var t: float = clamp(anim.elapsed / anim.duration, 0.0, 1.0)
		# Smoothstep for nice easing
		t = t * t * (3.0 - 2.0 * t)
		angle = lerp_angle(anim.from_angle, anim.to_angle, t)
	
	# Get base connections at rotation 0 (transform handles the rotation)
	var base_conns: Array[bool] = _get_connections(data.pipe_type, 0)
	
	# Set transform to rotate around cell center
	draw_set_transform(center, angle)
	
	# Draw connection nubs at rotation-0 positions (transform rotates them)
	var hw: float = _cell_size * 0.5
	var nub_h_frac: float = _cell_size * 0.5
	
	# Top nub (dir 0)
	if base_conns[0]:
		draw_rect(Rect2(-NUB_WIDTH * 0.5, -hw, NUB_WIDTH, nub_h_frac), pipe_color)
	# Right nub (dir 1)
	if base_conns[1]:
		draw_rect(Rect2(0, -NUB_WIDTH * 0.5, nub_h_frac, NUB_WIDTH), pipe_color)
	# Bottom nub (dir 2)
	if base_conns[2]:
		draw_rect(Rect2(-NUB_WIDTH * 0.5, 0, NUB_WIDTH, nub_h_frac), pipe_color)
	# Left nub (dir 3)
	if base_conns[3]:
		draw_rect(Rect2(-nub_h_frac, -NUB_WIDTH * 0.5, nub_h_frac, NUB_WIDTH), pipe_color)
	
	# Draw pipe body at local origin
	if data.pipe_type == PipeType.SOURCE or data.pipe_type == PipeType.DEST:
		var outer_r: float = PIPE_RADIUS + 4.0
		draw_circle(Vector2.ZERO, outer_r, pipe_color)
		draw_circle(Vector2.ZERO, PIPE_RADIUS * 0.55, COLOR_CELL_BG * _puzzle_alpha)
		draw_circle(Vector2.ZERO, 4.0, pipe_color)
	else:
		draw_circle(Vector2.ZERO, PIPE_RADIUS, pipe_color)
	
	# Reset transform
	draw_set_transform(Vector2.ZERO, 0.0)

func rotate_360(o: Node2D) -> void:
	var tween := create_tween()
	var target_rot: float = o.rotation + TAU
	tween.tween_property(o, "rotation", target_rot, 2.0)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)


func get_env_overrides() -> Dictionary:
	return {
		glow_enabled = true,
		glow_intensity = 0.2,
		glow_bloom = 0.6,
		glow_hdr_threshold = 0.3,
	}
