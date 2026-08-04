extends Area2D
class_name Ball

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow

const GRAVITY: float = 900.0
const CATCH_DISTANCE: float = 14.0

var velocity_2d: Vector2 = Vector2.ZERO
var height: float = 0.0
var height_speed: float = 0.0
var bounciness: float = 0.0
var friction: float = 0.0
var in_flight: bool = false
var kick_type: String = ""
var passer: Node2D = null
var target_receiver: Node2D = null

var carrier: Node2D = null

signal landed(pos: Vector2)
signal caught(by: Node2D)

func _ready() -> void:
	add_to_group("ball")

func _physics_process(delta: float) -> void:
	# Follow the carrier when held
	if carrier != null and not in_flight:
		global_position = carrier.global_position
		sprite.position.y = 0.0
		return

	if not in_flight:
		return

	global_position += velocity_2d * delta
	velocity_2d = velocity_2d.lerp(Vector2.ZERO, friction * delta)

	height_speed -= GRAVITY * delta
	height += height_speed * delta

	sprite.position.y = -height

	# PASS: resolve the moment it reaches the receiver (catch OR knock-on)
	if kick_type == "pass" and target_receiver != null:
		var d: float = global_position.distance_to(target_receiver.global_position)
		if d < CATCH_DISTANCE:
			_attempt_catch(target_receiver)
			return

	# Ground / bounce
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

	# Safety net: a pass that somehow overshoots is a knock-on, not a lost ball
	if global_position.x < 4 or global_position.x > 892 or global_position.y < 4 or global_position.y > 540:
		in_flight = false
		velocity_2d = Vector2.ZERO
		height = 0.0
		height_speed = 0.0
		if kick_type == "pass":
			print("pass went to ground — KNOCK ON")
			carrier = null
			GameState.do_turnover()


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

	if hands + roll > 40:
		carrier = catcher
		global_position = catcher.global_position
		caught.emit(catcher)
		print("CAUGHT by ", catcher.name)
	else:
		carrier = null
		print("KNOCK ON!")
		GameState.do_turnover()
