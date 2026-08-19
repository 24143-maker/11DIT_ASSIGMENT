extends Area2D
class_name Ball
# The ball. Fake "height" lets 2D kicks arc, bounce and roll.
# Passes HOME on their target so they always arrive.

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow

const GRAVITY: float = 900.0
const CATCH_DISTANCE: float = 18.0
const PICKUP_DISTANCE: float = 14.0
const LOOSE_FRICTION: float = 1.6

const PASS_DURATION: float = 0.40   # every pass takes this long, whatever the distance
const PASS_MAX_TIME: float = 1.20   # hard timeout: pass always resolves, never flies away
const INTERCEPT_DISTANCE: float = 15.0   # a defender this close cuts the pass out
const FIELD_CATCH_DIST: float = 22.0     # fullback fielding a kick out of the air
const FIELD_CATCH_HEIGHT: float = 60.0   # he can take it up to this height

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

# Pass homing
var pass_target: Node2D = null
var pass_timer: float = 0.0

# Stops the kicker instantly re-collecting their own kick
var pickup_lockout: float = 0.0

signal caught(by: Node2D)
signal picked_up(by: Node2D)
signal became_loose(pos: Vector2)
signal kicked(from_pos: Vector2)


func _ready() -> void:
	add_to_group("ball")
	collision_layer = 8
	collision_mask = 0      # catching and pickups are distance-based


func _physics_process(delta: float) -> void:
	if pickup_lockout > 0.0:
		pickup_lockout -= delta

	if carrier != null and not in_flight and not is_loose:
		global_position = carrier.global_position
		sprite.position.y = 0.0
		return

	if is_loose:
		_do_loose(delta)
		return

	if not in_flight:
		return

	if kick_type == "pass":
		_do_pass(delta)
	else:
		_do_kick_flight(delta)


# ---------- PASS: homes on the receiver, always arrives ----------

func _do_pass(delta: float) -> void:
	pass_timer += delta

	if pass_target == null or not is_instance_valid(pass_target):
		_go_loose()
		return

	# A defender in the passing lane knocks it down
	var blocker: Node2D = null
	if not GameState.player_defending():
		blocker = _nearest_defender(INTERCEPT_DISTANCE)
	if blocker != null:
		print("INTERCEPTED by ", blocker.name)
		GameState.turnover_position = global_position
		velocity_2d = velocity_2d * 0.25
		carrier = null
		_go_loose()
		return

	var to_target: Vector2 = pass_target.global_position - global_position
	var dist: float = to_target.length()

	# Arrived
	if dist < CATCH_DISTANCE:
		_attempt_catch(pass_target)
		return

	# Timed out — drop it here rather than sail on forever
	if pass_timer > PASS_MAX_TIME:
		velocity_2d = Vector2.ZERO
		_go_loose()
		return

	# Speed is set so we cover the remaining distance in the remaining time
	var time_left: float = max(PASS_DURATION - pass_timer, 0.05)
	var speed: float = dist / time_left
	global_position += to_target.normalized() * speed * delta

	# Small cosmetic arc
	var t: float = clamp(pass_timer / PASS_DURATION, 0.0, 1.0)
	height = sin(t * PI) * 10.0
	sprite.position.y = -height


# ---------- KICK: real flight with gravity and bounce ----------

func _do_kick_flight(delta: float) -> void:
	global_position += velocity_2d * delta
	velocity_2d = velocity_2d.lerp(Vector2.ZERO, friction * delta)

	height_speed -= GRAVITY * delta
	height += height_speed * delta
	sprite.position.y = -height

	if height <= 0.0:
		height = 0.0
		if bounciness > 0.05 and abs(height_speed) > 40.0:
			height_speed = -height_speed * bounciness
			velocity_2d.y += randf_range(-25.0, 25.0)
		else:
			height_speed = 0.0
			_go_loose()

	_clamp_to_field()


# ---------- LOOSE ----------

func _do_loose(delta: float) -> void:
	global_position += velocity_2d * delta
	velocity_2d = velocity_2d.lerp(Vector2.ZERO, LOOSE_FRICTION * delta)
	if velocity_2d.length() < 5.0:
		velocity_2d = Vector2.ZERO
	_clamp_to_field()

	if pickup_lockout > 0.0:
		return

	var grabber: Node2D = _nearest_anyone(PICKUP_DISTANCE)
	if grabber != null:
		_pick_up(grabber)


func _go_loose() -> void:
	in_flight = false
	is_loose = true
	pass_target = null
	height = 0.0
	height_speed = 0.0
	sprite.position.y = 0.0
	became_loose.emit(global_position)


func _pick_up(who: Node2D) -> void:
	GameState.turnover_position = global_position
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


func _nearest_defender(radius: float) -> Node2D:
	var best: Node2D = null
	var best_dist: float = radius
	for d in get_tree().get_nodes_in_group("defenders"):
		var dist: float = global_position.distance_to(d.global_position)
		if dist < best_dist:
			best_dist = dist
			best = d
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
	pass_target = null
	pickup_lockout = 0.0
	global_position = who.global_position


func pass_to(thrower: Node2D, receiver: Node2D) -> void:
	carrier = null
	is_loose = false
	passer = thrower
	pass_target = receiver
	pass_timer = 0.0
	global_position = thrower.global_position
	velocity_2d = Vector2.ZERO
	height = 0.0
	height_speed = 0.0
	in_flight = true
	kick_type = "pass"
	pickup_lockout = 0.15


func kick(from: Vector2, direction: Vector2, power: float, type: String) -> void:
	carrier = null
	is_loose = false
	passer = null
	pass_target = null
	global_position = from
	in_flight = true
	kick_type = type
	pickup_lockout = 0.6      # you can't instantly re-collect your own kick
	direction = direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	match type:
		"grubber":
			velocity_2d = direction * (330.0 * power)
			height_speed = 70.0            # enough hop that it actually travels
			bounciness = 0.5
			friction = 0.45
		"bomb":
			velocity_2d = direction * (120.0 * power)
			height_speed = 420.0 * power
			bounciness = 0.0
			friction = 0.5
		"long":
			velocity_2d = direction * (430.0 * power)
			height_speed = 200.0 * power
			bounciness = 0.25
			friction = 0.5

	print("KICK ", type, " power ", round(power * 100), "% dir ", direction)
	kicked.emit(from)


# Defender takes a kick cleanly — a fullback fielding a bomb or grubber
func _field_kick(fielder: Node2D) -> void:
	GameState.turnover_position = fielder.global_position
	in_flight = false
	is_loose = false
	velocity_2d = Vector2.ZERO
	height = 0.0
	height_speed = 0.0
	sprite.position.y = 0.0
	carrier = fielder
	global_position = fielder.global_position
	print("FIELDED by ", fielder.name)
	picked_up.emit(fielder)


func _attempt_catch(catcher: Node2D) -> void:
	in_flight = false
	is_loose = false
	pass_target = null
	velocity_2d = Vector2.ZERO
	height = 0.0
	height_speed = 0.0
	sprite.position.y = 0.0

	var hands: int = 65
	if "hands_stat" in catcher:
		hands = catcher.hands_stat
	var roll: int = randi_range(0, 40)

	if hands + roll > 40:
		carrier = catcher
		global_position = catcher.global_position
		caught.emit(catcher)
	else:
		carrier = null
		_go_loose()
