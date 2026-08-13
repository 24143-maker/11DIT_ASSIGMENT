extends CharacterBody2D
class_name Footballer
# Every attacking player uses this script.
# The human controls whichever footballer currently has the ball.

@export var base_speed: float = 115.0
@export var sprint_multiplier: float = 1.62      # ~186 px/s: genuinely outruns cover
@export var hands_stat: int = 70
@export var strength_stat: int = 50
@export var line_slot: Vector2 = Vector2(-30, 272)
@export var player_name: String = "Player"

# Stamina
@export var stamina_max: float = 3.2             # seconds of full sprint
@export var stamina_drain: float = 1.0
@export var stamina_regen: float = 0.55
@export var tired_speed_mult: float = 0.82

var is_user_controlled: bool = false
var ball_carrier: Node2D = null
var facing: Vector2 = Vector2.RIGHT
var is_playing_the_ball: bool = false

var chase_ball_pos: Vector2 = Vector2.ZERO
var is_chasing_ball: bool = false
var advance_to_x: float = -1.0

var stamina: float = 3.2
var is_sprinting: bool = false

const PASS_TOLERANCE: float = 6.0
const PASS_RANGE: float = 280.0
const AVOID_RADIUS: float = 30.0
const AVOID_STRENGTH: float = 95.0

# ---- Kick aiming ----
var is_aiming: bool = false
var aim_dir: Vector2 = Vector2.RIGHT
var kick_charge: float = 0.0
var selected_kick: String = "grubber"
var _aim_start_ms: int = 0
var _aim_last_ms: int = 0
var aim_arrow: Node2D = null

const CHARGE_SECONDS: float = 0.9
const AIM_TURN_SPEED: float = 2.0

signal kick_state_changed(charging: bool, charge: float, kick_type: String)
signal played_the_ball()


func _ready() -> void:
	add_to_group("attackers")
	stamina = stamina_max
	# Layer 2 = attackers. Mask 1 = field walls only, so players never
	# physically shove each other (that caused jitter and ruck drift).
	collision_layer = 2
	collision_mask = 1
	_build_arrow()
	for a in ["kick", "kick_grubber", "kick_bomb", "kick_long"]:
		if not InputMap.has_action(a):
			push_warning("Input action missing: " + a)


func _build_arrow() -> void:
	aim_arrow = Node2D.new()
	aim_arrow.z_index = 20
	add_child(aim_arrow)

	var shaft := Polygon2D.new()
	shaft.polygon = PackedVector2Array([
		Vector2(0, -2), Vector2(34, -2), Vector2(34, 2), Vector2(0, 2)
	])
	shaft.color = Color(1, 1, 0.2, 0.9)
	aim_arrow.add_child(shaft)

	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(34, -7), Vector2(48, 0), Vector2(34, 7)
	])
	head.color = Color(1, 1, 0.2, 0.95)
	aim_arrow.add_child(head)

	aim_arrow.visible = false


# ---------- MOVEMENT ----------

func _physics_process(delta: float) -> void:
	# Stamina ticks for EVERY player in EVERY state, so standing in the
	# ruck or jogging in support both recover you.
	_update_stamina(delta)

	if is_aiming:
		velocity = Vector2.ZERO
		return

	if is_user_controlled:
		_do_user_control()
	elif is_chasing_ball:
		_do_chase_ball()
	else:
		_do_support()


func _update_stamina(delta: float) -> void:
	var wants_sprint: bool = (
		is_user_controlled
		and not is_playing_the_ball
		and Input.is_action_pressed("sprint")
		and velocity.length() > 10.0
	)
	if is_chasing_ball:
		wants_sprint = true

	is_sprinting = wants_sprint and stamina > 0.0

	if is_sprinting:
		stamina = max(stamina - stamina_drain * delta, 0.0)
	else:
		stamina = min(stamina + stamina_regen * delta, stamina_max)


func _do_user_control() -> void:
	if is_playing_the_ball:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var speed: float = base_speed
	if is_sprinting:
		speed *= sprint_multiplier
	elif stamina <= 0.05:
		speed *= tired_speed_mult

	# Being held drags you down hard — you can't tow defenders to the line
	var held: int = count_holders()
	if held == 1:
		speed *= 0.38
	elif held >= 2:
		speed *= 0.15

	velocity = input_dir * speed
	move_and_slide()

	if input_dir.length() > 0.1:
		facing = input_dir.normalized()


func _do_chase_ball() -> void:
	var to_ball: Vector2 = chase_ball_pos - global_position
	if to_ball.length() > 12.0:
		var spd: float = base_speed * sprint_multiplier
		if stamina <= 0.05:
			spd = base_speed
		velocity = _avoid(to_ball.normalized() * spd)
	else:
		velocity = Vector2.ZERO
	move_and_slide()


func _do_support() -> void:
	# No carrier (ball loose or in the air): come up in a line at running pace
	if ball_carrier == null or ball_carrier == self:
		if advance_to_x >= 0.0:
			var t := Vector2(advance_to_x, line_slot.y)
			var to_t: Vector2 = t - global_position
			if to_t.length() > 8.0:
				velocity = _avoid(to_t.normalized() * base_speed)
			else:
				velocity = Vector2.ZERO
		else:
			velocity = Vector2.ZERO
		move_and_slide()
		return

	var target := Vector2(ball_carrier.global_position.x + line_slot.x, line_slot.y)
	target.x = clamp(target.x, Field.FIELD_LEFT - 60.0, Field.FIELD_RIGHT)
	target.y = clamp(target.y, 24.0, Field.FIELD_BOTTOM - 24.0)

	var to_target: Vector2 = target - global_position
	if to_target.length() > 6.0:
		velocity = _avoid(to_target.normalized() * base_speed)
	else:
		velocity = Vector2.ZERO
	move_and_slide()


# Steer around other players instead of running into them
func _avoid(desired: Vector2) -> Vector2:
	var push := Vector2.ZERO
	for grp in ["attackers", "defenders"]:
		for other in get_tree().get_nodes_in_group(grp):
			if other == self:
				continue
			var away: Vector2 = global_position - other.global_position
			var d: float = away.length()
			if d < 0.01 or d > AVOID_RADIUS:
				continue
			var strength: float = (1.0 - d / AVOID_RADIUS) * AVOID_STRENGTH
			push += away.normalized() * strength
	if push == Vector2.ZERO:
		return desired
	return (desired + push).normalized() * desired.length()


func count_holders() -> int:
	var n: int = 0
	for d in get_tree().get_nodes_in_group("defenders"):
		if d.state == Defender.State.CHASE or d.state == Defender.State.COVER:
			if global_position.distance_to(d.global_position) < d.tackle_radius:
				n += 1
	return n


func is_being_held() -> bool:
	return count_holders() > 0


# ---------- KICK AIMING (time is frozen while aiming) ----------

func _process(_delta: float) -> void:
	if not is_user_controlled:
		if is_aiming:
			_cancel_aim()
		return

	var ball: Ball = get_ball()
	if ball == null or ball.carrier != self or is_playing_the_ball:
		if is_aiming:
			_cancel_aim()
		return

	if Input.is_action_just_pressed("kick") and not is_aiming:
		_start_aim()

	if is_aiming:
		_update_aim()

	if Input.is_action_just_released("kick") and is_aiming:
		_release_kick()


func _start_aim() -> void:
	is_aiming = true
	kick_charge = 0.0
	_aim_start_ms = Time.get_ticks_msec()
	_aim_last_ms = _aim_start_ms
	aim_dir = facing if facing.length() > 0.1 else Vector2.RIGHT
	aim_arrow.visible = true
	Engine.time_scale = 0.0


func _update_aim() -> void:
	var elapsed: float = float(Time.get_ticks_msec() - _aim_start_ms) / 1000.0
	kick_charge = clamp(elapsed / CHARGE_SECONDS, 0.0, 1.0)

	var now: int = Time.get_ticks_msec()
	var rdelta: float = float(now - _aim_last_ms) / 1000.0
	_aim_last_ms = now

	# W/S nudge the arrow a little at a time — it does not snap
	var turn: float = 0.0
	if Input.is_action_pressed("move_up"):
		turn -= 1.0
	if Input.is_action_pressed("move_down"):
		turn += 1.0
	if turn != 0.0:
		aim_dir = aim_dir.rotated(turn * AIM_TURN_SPEED * rdelta)

	# A/D flip which way down the field you're kicking
	if Input.is_action_just_pressed("move_left"):
		aim_dir = Vector2(-abs(aim_dir.x), aim_dir.y).normalized()
	if Input.is_action_just_pressed("move_right"):
		aim_dir = Vector2(abs(aim_dir.x), aim_dir.y).normalized()

	aim_arrow.rotation = aim_dir.angle()
	aim_arrow.scale = Vector2(0.6 + kick_charge * 1.1, 1.0)

	kick_state_changed.emit(true, kick_charge, selected_kick)

	if Input.is_action_just_pressed("kick_grubber"):
		selected_kick = "grubber"
	if Input.is_action_just_pressed("kick_bomb"):
		selected_kick = "bomb"
	if Input.is_action_just_pressed("kick_long"):
		selected_kick = "long"


func _release_kick() -> void:
	var ball: Ball = get_ball()
	var power: float = lerp(0.35, 1.0, kick_charge)
	var dir: Vector2 = aim_dir
	_cancel_aim()
	if ball and ball.carrier == self:
		facing = dir
		ball.kick(global_position, dir, power, selected_kick)


func _cancel_aim() -> void:
	is_aiming = false
	kick_charge = 0.0
	if aim_arrow:
		aim_arrow.visible = false
	Engine.time_scale = 1.0
	kick_state_changed.emit(false, 0.0, selected_kick)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ---------- PASSING ----------

func _unhandled_input(event: InputEvent) -> void:
	if not is_user_controlled or is_aiming:
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

	if target.global_position.x > global_position.x + PASS_TOLERANCE:
		print("FORWARD PASS!")
		is_playing_the_ball = false
		GameState.do_turnover()
		return

	if is_playing_the_ball:
		is_playing_the_ball = false
		played_the_ball.emit()

	ball.pass_to(self, target)


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
