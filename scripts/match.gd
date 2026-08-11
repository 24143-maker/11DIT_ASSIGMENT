extends Node2D
# Runs the match: kickoff, tackles, play-the-ball, tries, loose balls, clock.

const RETREAT_METRES: float = 15.0
const MARKER_METRES: float = 1.5
const DEFENDER_COUNT: int = 6
const DEFENDER_SCENE := preload("res://scenes/entities/defender.tscn")

const HALF_LENGTH: float = 180.0    # seconds per half (3 min for testing)

var current_carrier: Footballer = null
var marker_defender: Defender = null
var chasing_loose: bool = false

var time_remaining: float = HALF_LENGTH
var current_half: int = 1
var clock_running: bool = true

signal event_message(text: String)
signal clock_updated(seconds: float, half: int)


func _ready() -> void:
	randomize()
	GameState.tackle_made.connect(_on_tackle_made)
	GameState.turnover.connect(_on_turnover)

	var ball: Ball = get_ball()
	if ball:
		ball.caught.connect(_on_ball_caught)
		ball.picked_up.connect(_on_ball_picked_up)
		ball.became_loose.connect(_on_ball_became_loose)

	_spawn_defensive_line(560.0)

	await get_tree().process_frame
	_kickoff()


func _physics_process(delta: float) -> void:
	if chasing_loose:
		_steer_defender_to_loose_ball()

	_check_for_try()

	if clock_running:
		time_remaining -= delta
		clock_updated.emit(max(time_remaining, 0.0), current_half)
		if time_remaining <= 0.0:
			_end_half()


# ---------- SETUP ----------

func get_ball() -> Ball:
	for n in get_tree().get_nodes_in_group("ball"):
		if n is Ball:
			return n
	return null


func _spawn_defensive_line(line_x: float) -> void:
	var spacing: float = Field.FIELD_BOTTOM / float(DEFENDER_COUNT + 1)
	for i in range(DEFENDER_COUNT):
		var d: Defender = DEFENDER_SCENE.instantiate()
		d.slot_y = spacing * float(i + 1)
		d.line_x = line_x
		d.global_position = Vector2(line_x, d.slot_y)
		add_child(d)


func _kickoff() -> void:
	GameState.reset_set()
	var start := Vector2(Field.FIELD_LEFT + 160.0, Field.FIELD_BOTTOM * 0.5)
	_reset_attack_positions(start)

	var first: Footballer = _first_attacker()
	if first:
		_give_ball_to(first)

	_reset_defensive_line(start.x + Field.metres_to_pixels(RETREAT_METRES))
	GameState.phase = GameState.Phase.OPEN_PLAY
	event_message.emit("KICK OFF")


func _first_attacker() -> Footballer:
	for a in get_tree().get_nodes_in_group("attackers"):
		return a
	return null


func _reset_attack_positions(around: Vector2) -> void:
	for a in get_tree().get_nodes_in_group("attackers"):
		a.is_playing_the_ball = false
		a.global_position = Vector2(around.x + a.line_slot.x, a.line_slot.y)
	var first: Footballer = _first_attacker()
	if first:
		first.global_position = around


func _reset_defensive_line(line_x: float) -> void:
	for d in get_tree().get_nodes_in_group("defenders"):
		d.line_x = line_x
		d.state = Defender.State.RETREAT
	marker_defender = null


# ---------- BALL / CONTROL ----------

func _give_ball_to(who: Footballer) -> void:
	var ball: Ball = get_ball()
	if ball == null:
		return
	ball.give_to(who)
	current_carrier = who
	chasing_loose = false
	_set_control(who)
	_assign_carrier(who)


func _set_control(who: Node2D) -> void:
	for a in get_tree().get_nodes_in_group("attackers"):
		a.is_user_controlled = (a == who)


func _assign_carrier(who: Node2D) -> void:
	for a in get_tree().get_nodes_in_group("attackers"):
		a.ball_carrier = who
	for d in get_tree().get_nodes_in_group("defenders"):
		d.ball_carrier = who


# ---------- TACKLE / PLAY THE BALL ----------

func _on_tackle_made(tackle_number: int) -> void:
	GameState.phase = GameState.Phase.RUCK
	event_message.emit("TACKLE %d" % tackle_number)

	if current_carrier == null:
		return

	current_carrier.is_user_controlled = true
	current_carrier.is_playing_the_ball = true
	current_carrier.velocity = Vector2.ZERO
	if not current_carrier.played_the_ball.is_connected(_on_played_the_ball):
		current_carrier.played_the_ball.connect(_on_played_the_ball)

	var ruck: Vector2 = current_carrier.global_position

	# Nearest defender becomes the marker, standing over the ruck
	marker_defender = _closest_defender_to(ruck)
	if marker_defender:
		marker_defender.state = Defender.State.MARKER
		marker_defender.marker_pos = ruck + Vector2(Field.metres_to_pixels(MARKER_METRES), 0)

	# Everyone else retreats and holds
	var new_line_x: float = ruck.x + Field.metres_to_pixels(RETREAT_METRES)
	for d in get_tree().get_nodes_in_group("defenders"):
		if d == marker_defender:
			continue
		d.line_x = new_line_x
		d.state = Defender.State.RETREAT


func _on_played_the_ball() -> void:
	GameState.phase = GameState.Phase.OPEN_PLAY
	if marker_defender:
		marker_defender.state = Defender.State.LINE
		marker_defender = null


# ---------- LOOSE BALL ----------

func _on_ball_became_loose(_pos: Vector2) -> void:
	chasing_loose = true
	GameState.phase = GameState.Phase.OPEN_PLAY
	for a in get_tree().get_nodes_in_group("attackers"):
		a.is_playing_the_ball = false

	# Hand control to the attacker nearest the ball — the human runs onto it
	var ball: Ball = get_ball()
	if ball:
		var nearest: Node2D = _closest_in_group_to("attackers", ball.global_position)
		if nearest:
			_set_control(nearest)
			current_carrier = nearest
			_assign_carrier(nearest)


func _steer_defender_to_loose_ball() -> void:
	var ball: Ball = get_ball()
	if ball == null or not ball.is_loose:
		chasing_loose = false
		return
	var d: Defender = _closest_defender_to(ball.global_position)
	if d:
		d.state = Defender.State.CHASE_BALL
		d.chase_target = ball.global_position


func _on_ball_picked_up(who: Node2D) -> void:
	chasing_loose = false
	for d in get_tree().get_nodes_in_group("defenders"):
		if d.state == Defender.State.CHASE_BALL:
			d.state = Defender.State.LINE

	if who.is_in_group("attackers"):
		current_carrier = who
		_set_control(who)
		_assign_carrier(who)
	else:
		event_message.emit("TURNOVER")
		GameState.do_turnover()


func _on_ball_caught(who: Node2D) -> void:
	chasing_loose = false
	current_carrier = who
	_set_control(who)
	_assign_carrier(who)


# ---------- TRY ----------

func _check_for_try() -> void:
	if GameState.phase == GameState.Phase.DEAD:
		return
	if current_carrier == null:
		return
	var ball: Ball = get_ball()
	if ball == null or ball.carrier != current_carrier:
		return

	if current_carrier.global_position.x >= Field.FIELD_RIGHT:
		_score_try()


func _score_try() -> void:
	GameState.award_try(0)
	event_message.emit("TRY!")
	clock_running = false
	await get_tree().create_timer(2.0).timeout
	clock_running = true
	_kickoff()


# ---------- TURNOVER / HALVES ----------

func _on_turnover() -> void:
	event_message.emit("HANDOVER")
	chasing_loose = false
	GameState.phase = GameState.Phase.OPEN_PLAY

	var restart := Vector2(Field.centre().x, Field.FIELD_BOTTOM * 0.5)
	_reset_attack_positions(restart)
	var first: Footballer = _first_attacker()
	if first:
		_give_ball_to(first)
	_reset_defensive_line(restart.x + Field.metres_to_pixels(RETREAT_METRES))


func _end_half() -> void:
	clock_running = false
	if current_half == 1:
		current_half = 2
		time_remaining = HALF_LENGTH
		event_message.emit("HALF TIME")
		await get_tree().create_timer(2.0).timeout
		clock_running = true
		_kickoff()
	else:
		event_message.emit("FULL TIME")
		GameState.phase = GameState.Phase.DEAD


# ---------- HELPERS ----------

func _closest_defender_to(pos: Vector2) -> Defender:
	var best: Defender = null
	var best_dist: float = INF
	for d in get_tree().get_nodes_in_group("defenders"):
		var dist: float = d.global_position.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = d
	return best


func _closest_in_group_to(grp: String, pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for n in get_tree().get_nodes_in_group(grp):
		var dist: float = n.global_position.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = n
	return best
