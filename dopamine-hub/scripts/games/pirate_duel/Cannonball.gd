extends Area2D

const GRAVITY: float = 600.0

var from_player: bool = false
var velocity: Vector2 = Vector2.ZERO
var _screen_size: Vector2 = Vector2(1080, 1920)


func _ready() -> void:
	_screen_size = get_viewport_rect().size
	add_to_group("cannonball")


func _physics_process(delta: float) -> void:
	velocity.y += GRAVITY * delta
	position += velocity * delta
	
	# Remove if off-screen
	if position.y < -100 or position.y > _screen_size.y + 100 or \
	   position.x < -100 or position.x > _screen_size.x + 100:
		queue_free()
