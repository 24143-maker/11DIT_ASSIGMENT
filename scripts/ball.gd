extends Area2D
class_name Ball
# The ball. Uses a fake "height" value so 2D kicks can arc, bounce and roll.

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow

const GRAVITY: float = 900.0
const CATCH_DISTANCE: float = 18.0
const PICKUP_DISTANCE: float = 14.0
const LOOSE_FRICTION: float = 2.0

var velocity_2d: Vector2 = Vector2.ZERO
var height: float = 0.0
var height_speed: float = 0.0
var bounciness: float = 0.0
var friction: float = 0.0

var in_flight: bool = false
var is_loose: bool = false
var kick_type: String = ""
var passer: Node2D = null
var carrier: Node2D = null

signal caught(by: Node2D)
signal picked_up(by: Node2D)
signal became_loose(pos: Vector2)


func _ready() -> void:
	add_to_group("ball")


func _physics_process(delta: float) -> void:
	if carrier != null and not in_flight and not is_loose:
		global_position = carrier.global_position
		sprite.position.y = 0.0
		return

	if is_loose:
		_do_loose(delta)
		return

	if not in_flight:
		return

	global_position += velocity_2d * delta
	velocity_2d = velocity_2d.lerp(Vector2.ZERO, friction * delta)

	height_speed -= GRAVITY * delta
	height += height_speed * delta
	sprite.position.y = -height

	# A pass is caught by whichever attacker it reaches
	if kick_type == "pass":
		var catcher: Node2D = _nearest_attacker(CATCH_DISTANCE)
		if catcher != null:
			_attempt_catch(catcher)
			return

	if height <= 0.0:
		height = 0.0
		if bounciness > 0.05 and abs(height_speed) > 40.0:
			height_speed = -height_speed * bounciness
			velocity_2d.y += randf_range(-25.0, 25.0)   # unpredictable grubber bounce
		else:
			height_speed = 0.0
			_go_loose()

	_clamp_to_field()


func _do_loose(delta: float) -> void:
	global_position += velocity_2d * delta
	velocity_2d = velocity_2d.lerp(Vector2.ZERO, LOOSE_FRICTION * delta)
	if velocity_2d.length() < 5.0:
		velocity_2d = Vector2.ZERO
	_clamp_to_field()

	var grabber: Node2D = _nearest_anyone(PICKUP_DISTANCE)
	if grabber != null:
		_pick_up(grabber)


func _go_loose() -> void:
	in_flight = false
	is_loose = true
	height = 0.0
	height_speed = 0.0
	sprite.position.y = 0.0
	became_loose.emit(global_position)


func _pick_up(who: Node2D) -> void:
	is_loose = false
	in_flight = false
	velocity_2d = Vector2.ZERO
	carrier = who
	global_position = who.global_position
	picked_up.emit(who)


func _clamp_to_field() -> void:
	if global_position.x < 4.0:
		global_position.x = 4.0
		velocity_2d.x = abs(velocity_2d.x) * 0.4
	elif global_position.x > 892.0:
		global_position.x = 892.0
		velocity_2d.x = -abs(velocity_2d.x) * 0.4
	if global_position.y < 4.0:
		global_position.y = 4.0
		velocity_2d.y = abs(velocity_2d.y) * 0.4
	elif global_position.y > 540.0:
		global_position.y = 540.0
		velocity_2d.y = -abs(velocity_2d.y) * 0.4


func _nearest_attacker(radius: float) -> Node2D:
	var best: Node2D = null
	var best_dist: float = radius
	for a in get_tree().get_nodes_in_group("attackers"):
		if a == passer:
			continue
		var d: float = global_position.distance_to(a.global_position)
		if d < best_dist:
			best_dist = d
			best = a
	return best


func _nearest_anyone(radius: float) -> Node2D:
	var best: Node2D = null
	var best_dist: float = radius
	for grp in ["attackers", "defenders"]:
		for n in get_tree().get_nodes_in_group(grp):
			var d: float = global_position.distance_to(n.global_position)
			if d < best_dist:
				best_dist = d
				best = n
	return best


# ---------- LAUNCHERS ----------

func give_to(who: Node2D) -> void:
	carrier = who
	in_flight = false
	is_loose = false
	velocity_2d = Vector2.ZERO
	height = 0.0
	height_speed = 0.0
	passer = null
	global_position = who.global_position


func pass_to(from: Vector2, to: Vector2, thrower: Node2D, _receiver: Node2D, speed: float = 210.0) -> void:
	carrier = null
	is_loose = false
	passer = thrower
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
	is_loose = false
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
			friction = 0.9
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
	var hands: int = 60
	if "hands_stat" in catcher:
		hands = catcher.hands_stat
	var roll: int = randi_range(0, 40)

	if hands + roll > 45:
		in_flight = false
		is_loose = false
		velocity_2d = Vector2.ZERO
		height = 0.0
		height_speed = 0.0
		carrier = catcher
		global_position = catcher.global_position
		caught.emit(catcher)
	else:
		carrier = null
		velocity_2d = velocity_2d * 0.3
		_go_loose()
