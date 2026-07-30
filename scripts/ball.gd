extends Area2D
class_name Ball

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow

const GRAVITY: float = 900.0

var velocity_2d: Vector2 = Vector2.ZERO
var height: float = 0.0
var height_speed: float = 0.0
var bounciness: float = 0.0
var friction: float = 0.0
var in_flight: bool = false
var kick_type: String = ""
var passer: Node2D = null

signal landed(pos: Vector2)
signal caught(by: Node2D)

func _physics_process(delta: float) -> void:
	if not in_flight:
		return

	# Move across the ground
	global_position += velocity_2d * delta
	velocity_2d = velocity_2d.lerp(Vector2.ZERO, friction * delta)

	# Fake vertical movement
	height_speed -= GRAVITY * delta
	height += height_speed * delta

	if height <= 0.0:
		height = 0.0
		if bounciness > 0.05 and abs(height_speed) > 40.0:
			height_speed = -height_speed * bounciness
			# The unpredictable grubber bounce
			velocity_2d.y += randf_range(-25.0, 25.0)
		else:
			height_speed = 0.0
			if velocity_2d.length() < 15.0:
				in_flight = false
			landed.emit(global_position)

	# Draw the ball above its shadow
	sprite.position.y = -height
	shadow.scale = Vector2.ONE * clamp(1.0 - height / 300.0, 0.3, 1.0)


func pass_to(from: Vector2, to: Vector2, thrower: Node2D, speed: float = 260.0) -> void:
	passer = thrower
	global_position = from
	velocity_2d = (to - from).normalized() * speed
	height = 12.0
	height_speed = 0.0
	bounciness = 0.0
	friction = 0.0
	in_flight = true
	kick_type = "pass"


func kick(from: Vector2, direction: Vector2, power: float, type: String) -> void:
	passer = null
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


func _on_body_entered(body: Node2D) -> void:
	# Only a pass can be caught this way, and only when low and in flight
	if kick_type != "pass":
		return
	if not in_flight:
		return
	if height > 20.0:
		return
	if not body.is_in_group("attackers"):
		return
	if body == passer:
		return

	_attempt_catch(body)


func _attempt_catch(catcher: Node2D) -> void:
	var hands: int = 60
	if "hands_stat" in catcher:
		hands = catcher.hands_stat

	var roll: int = randi_range(0, 40)

	if hands + roll > 50:
		in_flight = false
		velocity_2d = Vector2.ZERO
		height = 0.0
		height_speed = 0.0
		caught.emit(catcher)
		print("CAUGHT by ", catcher.name)
	else:
		in_flight = false
		print("KNOCK ON!")
		GameState.do_turnover()
