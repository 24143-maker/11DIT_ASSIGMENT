extends CharacterBody2D
class_name Footballer

@export var base_speed: float = 110.0
@export var sprint_multiplier: float = 1.4

# This footballer's slot in the attacking line, as an offset from the carrier.
# x is how far BEHIND the carrier (negative), y is where across the field.
@export var line_slot: Vector2 = Vector2(-30, 0)

var is_user_controlled: bool = false
var ball_carrier: Node2D = null
var facing: Vector2 = Vector2.RIGHT

const PASS_TOLERANCE: float = 4.0

# --- Kicking ---
var kick_charge: float = 0.0
var is_charging: bool = false
var selected_kick: String = "grubber"
const CHARGE_RATE: float = 0.85

signal kick_state_changed(charging: bool, charge: float, kick_type: String)

func _ready() -> void:
	add_to_group("attackers")

func _physics_process(_delta: float) -> void:
	if is_user_controlled:
		_do_user_control()
	else:
		_do_support()


func _do_user_control() -> void:
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	var speed: float = base_speed
	if Input.is_action_pressed("sprint"):
		speed *= sprint_multiplier
	velocity = input_dir * speed
	move_and_slide()
	if input_dir.length() > 0.1:
		facing = input_dir.normalized()


func _do_support() -> void:
	if ball_carrier == null or ball_carrier == self:
		velocity = Vector2.ZERO
		return

	# Hold my slot: behind the carrier on x, at my own line position on y
	var target: Vector2 = Vector2(
		ball_carrier.global_position.x + line_slot.x,
		line_slot.y
	)
	target.x = clamp(target.x, Field.FIELD_LEFT, Field.FIELD_RIGHT)
	target.y = clamp(target.y, 24.0, Field.FIELD_BOTTOM - 24.0)

	var to_target: Vector2 = target - global_position
	if to_target.length() > 6.0:
		velocity = to_target.normalized() * base_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()


func _process(delta: float) -> void:
	if not is_user_controlled:
		return

	var ball: Ball = _get_ball()
	if ball == null or ball.carrier != self:
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
	var ball: Ball = _get_ball()
	if ball == null or ball.carrier != self:
		return
	var power: float = lerp(0.3, 1.0, kick_charge)
	print("KICK: ", selected_kick, " power ", round(power * 100), "%")
	ball.kick(global_position, facing, power, selected_kick)
	kick_charge = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not is_user_controlled:
		return
	if event.is_action_pressed("pass_left"):
		_try_pass(-1)
	elif event.is_action_pressed("pass_right"):
		_try_pass(1)


func _try_pass(direction: int) -> void:
	var target: Node2D = _find_receiver(direction)
	if target == null:
		print("no receiver on that side")
		return

	if target.global_position.x > global_position.x + PASS_TOLERANCE:
		print("FORWARD PASS!")
		GameState.do_turnover()
		return

	var ball: Ball = _get_ball()
	if ball == null:
		return
	if ball.carrier != self:
		return

	# LEAD THE PASS: aim where the receiver will be, based on their velocity
	var lead_time: float = 0.35
	var predicted: Vector2 = target.global_position + target.velocity * lead_time
	print("passing to ", target.name)
	ball.pass_to(global_position, predicted, self, target)


func _find_receiver(direction: int) -> Node2D:
	var best: Node2D = null
	var best_dist: float = 250.0
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


func _get_ball() -> Ball:
	for n in get_tree().get_nodes_in_group("ball"):
		if n is Ball:
			return n
	return null
