extends CharacterBody2D
class_name Footballer
# Every attacking player uses this one script.
# The human controls whichever footballer currently has the ball.

@export var base_speed: float = 115.0
@export var sprint_multiplier: float = 1.35
@export var hands_stat: int = 65
@export var strength_stat: int = 50

# Where this player stands in the attacking line.
# x = how far BEHIND the carrier. y = fixed lane across the field.
@export var line_slot: Vector2 = Vector2(-30, 272)

var is_user_controlled: bool = false
var ball_carrier: Node2D = null
var facing: Vector2 = Vector2.RIGHT

# True right after being tackled: can pass, cannot run.
var is_playing_the_ball: bool = false

const PASS_TOLERANCE: float = 6.0
const PASS_RANGE: float = 260.0
const HELD_SPEED_MULT: float = 0.5    # slowed down while a defender has hold of you

# Kicking
var kick_charge: float = 0.0
var is_charging: bool = false
var selected_kick: String = "grubber"
const CHARGE_RATE: float = 0.85

signal kick_state_changed(charging: bool, charge: float, kick_type: String)
signal played_the_ball()


func _ready() -> void:
	add_to_group("attackers")


func _physics_process(_delta: float) -> void:
	if is_user_controlled:
		_do_user_control()
	else:
		_do_support()


func _do_user_control() -> void:
	# Playing the ball: rooted to the spot, pass only
	if is_playing_the_ball:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var speed: float = base_speed
	if Input.is_action_pressed("sprint"):
		speed *= sprint_multiplier
	if is_being_held():
		speed *= HELD_SPEED_MULT

	velocity = input_dir * speed
	move_and_slide()

	if input_dir.length() > 0.1:
		facing = input_dir.normalized()


func _do_support() -> void:
	if ball_carrier == null or ball_carrier == self:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var target := Vector2(ball_carrier.global_position.x + line_slot.x, line_slot.y)
	target.x = clamp(target.x, Field.FIELD_LEFT - 40.0, Field.FIELD_RIGHT)
	target.y = clamp(target.y, 24.0, Field.FIELD_BOTTOM - 24.0)

	var to_target: Vector2 = target - global_position
	if to_target.length() > 6.0:
		velocity = to_target.normalized() * base_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()


# Am I currently in a defender's grasp?
func is_being_held() -> bool:
	for d in get_tree().get_nodes_in_group("defenders"):
		if d.state == Defender.State.CHASE:
			if global_position.distance_to(d.global_position) < d.tackle_radius:
				return true
	return false


# ---------- KICKING ----------

func _process(delta: float) -> void:
	if not is_user_controlled:
		return

	var ball: Ball = get_ball()
	if ball == null or ball.carrier != self or is_playing_the_ball:
		if is_charging:
			is_charging = false
			kick_state_changed.emit(false, 0.0, selected_kick)
		return

	if Input.is_action_just_pressed("kick"):
		is_charging = true
		kick_charge = 0.0

	if is_charging:
		kick_charge = min(kick_charge + CHARGE_RATE * delta, 1.0)
		if Input.is_action_just_pressed("kick_grubber"):
			selected_kick = "grubber"
		if Input.is_action_just_pressed("kick_bomb"):
			selected_kick = "bomb"
		if Input.is_action_just_pressed("kick_long"):
			selected_kick = "long"
		kick_state_changed.emit(true, kick_charge, selected_kick)

	if Input.is_action_just_released("kick") and is_charging:
		_do_kick()
		is_charging = false
		kick_state_changed.emit(false, 0.0, selected_kick)


func _do_kick() -> void:
	var ball: Ball = get_ball()
	if ball == null or ball.carrier != self:
		return
	var power: float = lerp(0.35, 1.0, kick_charge)
	ball.kick(global_position, facing, power, selected_kick)
	kick_charge = 0.0


# ---------- PASSING ----------

func _unhandled_input(event: InputEvent) -> void:
	if not is_user_controlled:
		return
	if event.is_action_pressed("pass_left"):
		_try_pass(-1)
	elif event.is_action_pressed("pass_right"):
		_try_pass(1)


func _try_pass(direction: int) -> void:
	var ball: Ball = get_ball()
	if ball == null or ball.carrier != self:
		return

	var target: Node2D = _find_receiver(direction)
	if target == null:
		return

	# Forward pass = turnover
	if target.global_position.x > global_position.x + PASS_TOLERANCE:
		print("FORWARD PASS!")
		is_playing_the_ball = false
		GameState.do_turnover()
		return

	# If this pass is the play-the-ball, it restarts open play
	if is_playing_the_ball:
		is_playing_the_ball = false
		played_the_ball.emit()

	# Lead the pass so it arrives in front of a running receiver
	var predicted: Vector2 = target.global_position + target.velocity * 0.4
	ball.pass_to(global_position, predicted, self, target)


func _find_receiver(direction: int) -> Node2D:
	var best: Node2D = null
	var best_dist: float = PASS_RANGE
	for mate in get_tree().get_nodes_in_group("attackers"):
		if mate == self:
			continue
		var offset: Vector2 = mate.global_position - global_position
		if sign(offset.y) != direction:
			continue
		if offset.x > PASS_TOLERANCE:
			continue
		var d: float = offset.length()
		if d < best_dist:
			best_dist = d
			best = mate
	return best


func get_ball() -> Ball:
	for n in get_tree().get_nodes_in_group("ball"):
		if n is Ball:
			return n
	return null
