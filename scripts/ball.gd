extends Area2D
class_name Ball

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow

const GRAVITY: float = 900.0
const CATCH_DISTANCE: float = 12.0   # how close the ball must get to be caught

var velocity_2d: Vector2 = Vector2.ZERO
var height: float = 0.0
var height_speed: float = 0.0
var bounciness: float = 0.0
var friction: float = 0.0
var in_flight: bool = false
var kick_type: String = ""
var passer: Node2D = null
var target_receiver: Node2D = null   # who this pass is aimed at

# Who is currently holding the ball. When set, the ball follows them.
var carrier: Node2D = null

signal landed(pos: Vector2)
signal caught(by: Node2D)

func _ready() -> void:
	add_to_group("ball")

func _physics_process(delta: float) -> void:
	# If someone is carrying the ball, stick to them and do nothing else
	if carrier != null and not in_flight:
		global_position = carrier.global_position
		sprite.position.y = 0.0
		return

	if not in_flight:
		return

	# Move across the ground
	global_position += velocity_2d * delta
	velocity_2d = velocity_2d.lerp(Vector2.ZERO, friction * delta)

	# Fake vertical movement
	height_speed -= GRAVITY * delta
	height += height_speed * delta

	# Draw the ball above its shadow
	sprite.position.y = -height
	shadow.scale = Vector2(0.018, 0.012) * clamp(1.0 - height / 300.0, 0.4, 1.0)

	# --- PASS: check if it has reached the intended receiver ---
	if kick_type == "pass" and target_receiver != null:
		var d: float = global_position.distance_to(target_receiver.global_position)
		if d < CATCH_DISTANCE:
			_attempt_catch(target_receiver)
			return

	# --- Ground / bounce handling ---
	if height <= 0.0:
		height = 0.0
		if bounciness > 0.05 and abs(height_speed) > 40.0:
			height_speed = -height_speed * bounciness
			velocity_2d.y += randf_range(-25.0, 25.0)
		else:
			height_speed = 0.0
			if velocity_2d.length() < 15.0:
				in_flight = false
			landed.emit(global_position)

	# Safety net: stop the ball if it leaves the field
	if global_position.x < 0 or global_position.x > 896 or global_position.y < 0 or global_position.y > 544:
		in_flight = false
		velocity_2d = Vector2.ZERO
		height = 0.0
		height_speed = 0.0


func pass_to(from: Vector2, to: Vector2, thrower: Node2D, receiver: Node2D, speed: float = 200.0) -> void:
	carrier = null
	passer = thrower
	target_receiver = receiver
	global_position = from
	velocity_2d = (to - from).normalized() * speed
	height = 6.0
	height_speed = 0.0
	bounciness = 0.0
	friction = 0.0
	in_flight = true
	kick_type = "pass"


func kick(from: Vector2, direction: Vector2, power: float, type: String) -> void:
	carrier = null
	passer = null
	target_receiver = null
	global_position = from
	in_flight = true
	kick_type = type
	direction = direction.normalized()

	match type:
		"grubber":
			velocity_2d = direction * (300.0 * power)
			height_speed = 30.0
			bounciness = 0.45
			friction = 1.1
		"bomb":
			velocity_2d = direction * (110.0 * power)
			height_speed = 400.0 * power
			bounciness = 0.0
			friction = 0.6
		"long":
			velocity_2d = direction * (420.0 * power)
			height_speed = 190.0 * power
			bounciness = 0.25
			friction = 0.8


func _attempt_catch(catcher: Node2D) -> void:
	in_flight = false
	velocity_2d = Vector2.ZERO
	height = 0.0
	height_speed = 0.0
	target_receiver = null

	var hands: int = 60
	if "hands_stat" in catcher:
		hands = catcher.hands_stat

	var roll: int = randi_range(0, 40)

	if hands + roll > 50:
		carrier = catcher
		global_position = catcher.global_position
		caught.emit(catcher)
		print("CAUGHT by ", catcher.name)
	else:
		# Dropped it — knock-on, turnover
		carrier = null
		print("KNOCK ON!")
		GameState.do_turnover()
