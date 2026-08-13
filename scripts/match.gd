extends Node2D
# Runs the match: kickoff, tackles, play-the-ball, tries, loose balls, clock.

const RETREAT_METRES: float = 15.0
const MARKER_METRES: float = 1.5
const DEFENDER_COUNT: int = 6
const DEFENDER_SCENE := preload("res://scenes/entities/defender.tscn")

# Squad names, applied in scene-tree order to any player left as "Player"
const SQUAD: Array = ["Liam", "Ben", "Christian", "Max", "Olly"]

const HALF_LENGTH: float = 180.0    # seconds per half (3 min for testing)

var current_carrier: Footballer = null
var marker_defender: Defender = null
var chasing_loose: bool = false
var line_broken: bool = false
var kickoff_in_progress: bool = false
var scoring: bool = false
var kickoff_chase: bool = false
var kickoff_landing: Vector2 = Vector2.ZERO
var kickoff_receiver: Node2D = null    # locked once, never reassigned
var kick_chaser: Node2D = null          # the one player committed to chasing a kick
var kick_control_delay: float = 0.0     # counts down before control switches to them

var time_remaining: float = HALF_LENGTH
var current_half: int = 1
var clock_running: bool = true

signal event_message(text: String)
signal clock_updated(seconds: float, half: int)


func _ready() -> void:
	randomize()
	_name_the_squad()
	GameState.tackle_made.connect(_on_tackle_made)
	GameState.turnover.connect(_on_turnover)

	var ball: Ball = get_ball()
	if ball:
		ball.caught.connect(_on_ball_caught)
		ball.picked_up.connect(_on_ball_picked_up)
		ball.became_loose.connect(_on_ball_became_loose)
		ball.kicked.connect(_on_ball_kicked)

	_spawn_defensive_line(560.0)

	await get_tree().process_frame
	_kickoff()


func _physics_process(delta: float) -> void:
	if kick_control_delay > 0.0:
		kick_control_delay -= delta
		if kick_control_delay <= 0.0 and kick_chaser and is_instance_valid(kick_chaser):
			_set_control(kick_chaser)
			current_carrier = kick_chaser
			kick_chaser.is_chasing_ball = false   # you drive them from here

	if kickoff_chase:
		_kickoff_chase_step()

	_advance_defensive_line(delta)
	_handle_line_break()

	if chasing_loose:
		_steer_defender_to_loose_ball()

	_check_for_try()

	if clock_running:
		time_remaining -= delta
		clock_updated.emit(max(time_remaining, 0.0), current_half)
		if time_remaining <= 0.0:
			_end_half()


# ---------- SETUP ----------

func _name_the_squad() -> void:
	var list: Array = get_tree().get_nodes_in_group("attackers")
	for i in range(list.size()):
		# Only fill in names that were left at the default
		if list[i].player_name == "" or list[i].player_name == "Player":
			list[i].player_name = SQUAD[i % SQUAD.size()]


func get_ball() -> Ball:
	for n in get_tree().get_nodes_in_group("ball"):
		if n is Ball:
			return n
	return null


func _spawn_defensive_line(line_x: float) -> void:
	var spacing: float = Field.FIELD_BOTTOM / float(DEFENDER_COUNT + 1)
	for i in range(DEFENDER_COUNT):
		var d: Defender = DEFENDER_SCENE.instantiate()
		d.slot_index = i
		d.slot_count = DEFENDER_COUNT
		d.slot_y = spacing * float(i + 1)
		d.line_x = line_x
		d.global_position = Vector2(line_x, d.slot_y)
		add_child(d)


# Receiving arrow: point man up front, then two pairs fanning back and wide.
# x is metres-ish behind the point, y is the spread from the middle.
const RECEIVE_SHAPE: Array = [
	Vector2(0, 0),        # point of the arrow
	Vector2(-72, -104),   # big gap, first pair
	Vector2(-72, 104),
	Vector2(-118, -196),  # smaller gap, wide pair
	Vector2(-118, 196),
]

func _kickoff() -> void:
	GameState.reset_set()
	kickoff_in_progress = true
	kickoff_chase = false
	kickoff_receiver = null
	kick_chaser = null
	kick_control_delay = 0.0
	current_carrier = null
	line_broken = false
	chasing_loose = false
	Engine.time_scale = 1.0

	# Receiving team forms an arrow in their own half
	var point_x: float = Field.FIELD_LEFT + 190.0
	var mid_y: float = Field.FIELD_BOTTOM * 0.5
	var attackers: Array = get_tree().get_nodes_in_group("attackers")

	for i in range(attackers.size()):
		var a = attackers[i]
		var slot: Vector2 = RECEIVE_SHAPE[i % RECEIVE_SHAPE.size()]
		a.global_position = Vector2(
			point_x + slot.x,
			clamp(mid_y + slot.y, 40.0, Field.FIELD_BOTTOM - 40.0)
		)
		a.is_playing_the_ball = false
		a.is_user_controlled = false
		a.is_chasing_ball = false
		a.ball_carrier = null
		a.velocity = Vector2.ZERO

	# Kick-off is fully automatic — the AI gathers it, then you take over.
	for a in attackers:
		a.is_user_controlled = false
	current_carrier = null

	# Kicking team lines up on their side of halfway
	var spacing: float = Field.FIELD_BOTTOM / float(DEFENDER_COUNT + 1)
	var i2: int = 0
	for d in get_tree().get_nodes_in_group("defenders"):
		d.marker_target = null
		d.ball_carrier = null
		d.slot_y = spacing * float(i2 + 1)
		d.line_x = Field.centre().x + 45.0
		d.global_position = Vector2(d.line_x, d.slot_y)
		d.state = Defender.State.LINE
		i2 += 1

	var kicker: Defender = _closest_defender_to(Field.centre())
	var ball: Ball = get_ball()
	if kicker == null or ball == null:
		return

	kicker.global_position = Field.centre()
	ball.give_to(kicker)

	GameState.phase = GameState.Phase.OPEN_PLAY
	event_message.emit("KICK OFF")

	await get_tree().create_timer(1.0).timeout
	if not kickoff_in_progress:
		return

	# Random landing spot somewhere in the receiving half
	kickoff_landing = Vector2(
		randf_range(Field.FIELD_LEFT + 90.0, Field.FIELD_LEFT + 300.0),
		randf_range(70.0, Field.FIELD_BOTTOM - 70.0)
	)
	var to_target: Vector2 = kickoff_landing - kicker.global_position
	var dir: Vector2 = to_target.normalized()
	# Scale power to the distance so it lands roughly where we aimed
	var power: float = clamp(to_target.length() / 420.0, 0.55, 1.0)
	ball.kick(kicker.global_position, dir, power, "long")

	# LOCK the receiver now, based on where the ball is actually going.
	# Never reassign — swapping mid-flight is what caused the jitter.
	kickoff_receiver = _closest_in_group_to("attackers", kickoff_landing)
	if kickoff_receiver:
		for a in get_tree().get_nodes_in_group("attackers"):
			a.is_chasing_ball = false
			a.is_user_controlled = false
			if a != kickoff_receiver:
				a.advance_to_x = kickoff_landing.x - 60.0
		kickoff_receiver.is_chasing_ball = true
		kickoff_receiver.chase_ball_pos = kickoff_landing

	kickoff_chase = true
	kicker.state = Defender.State.RETREAT


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
		d.marker_target = null
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
	# While a kick-off is in flight, only the locked receiver may ever be given
	# control. This stops any other system reassigning it mid-flight.
	if kickoff_in_progress and kickoff_receiver != null and who != kickoff_receiver:
		return
	for a in get_tree().get_nodes_in_group("attackers"):
		a.is_user_controlled = (a == who)


func _assign_carrier(who: Node2D) -> void:
	for a in get_tree().get_nodes_in_group("attackers"):
		a.ball_carrier = who
	for d in get_tree().get_nodes_in_group("defenders"):
		d.ball_carrier = who


# ---------- TACKLE / PLAY THE BALL ----------

func _on_tackle_made(tackle_number: int) -> void:
	Engine.time_scale = 1.0
	kick_chaser = null
	kick_control_delay = 0.0
	_stop_attacker_chase()
	line_broken = false
	GameState.phase = GameState.Phase.RUCK
	event_message.emit("TACKLE %d" % tackle_number)

	# The player who was tackled is the one who plays the ball — not whoever
	# happens to be "current_carrier" if a pass was in the air.
	if GameState.tackled_player and is_instance_valid(GameState.tackled_player):
		current_carrier = GameState.tackled_player
		_set_control(current_carrier)
		_assign_carrier(current_carrier)

	if current_carrier == null:
		return

	# Make sure the ball is definitely in their hands
	var ball: Ball = get_ball()
	if ball:
		ball.give_to(current_carrier)

	# Play the ball from where the tackle was MADE, not where they were dragged to
	if GameState.tackle_position != Vector2.ZERO:
		current_carrier.global_position = GameState.tackle_position

	current_carrier.is_user_controlled = true
	current_carrier.is_playing_the_ball = true
	current_carrier.velocity = Vector2.ZERO
	if not current_carrier.played_the_ball.is_connected(_on_played_the_ball):
		current_carrier.played_the_ball.connect(_on_played_the_ball)

	var ruck: Vector2 = current_carrier.global_position

	# Nearest defender becomes the marker, standing over the ruck
	marker_defender = _pick_marker(ruck)
	if marker_defender:
		marker_defender.state = Defender.State.MARKER
		marker_defender.marker_target = current_carrier   # follows the tackled player
		marker_defender.marker_pos = ruck + Vector2(Field.metres_to_pixels(MARKER_METRES), 0)

	# Everyone else retreats and holds, spread across their own slots
	var new_line_x: float = min(
		ruck.x + Field.metres_to_pixels(RETREAT_METRES),
		Field.FIELD_RIGHT - 6.0
	)
	var spacing: float = Field.FIELD_BOTTOM / float(DEFENDER_COUNT + 1)
	for d in get_tree().get_nodes_in_group("defenders"):
		if d == marker_defender:
			continue
		d.line_x = new_line_x
		d.slot_y = spacing * float(d.slot_index + 1)
		d.marker_target = null
		d.state = Defender.State.RETREAT


func _on_played_the_ball() -> void:
	GameState.phase = GameState.Phase.OPEN_PLAY
	if marker_defender:
		marker_defender.state = Defender.State.LINE
		marker_defender.marker_target = null
		marker_defender = null


# ---------- KICK-OFF CHASE ----------

func _kickoff_chase_step() -> void:
	var ball: Ball = get_ball()
	if ball == null or ball.carrier != null:
		_stop_attacker_chase()
		kickoff_chase = false
		return
	# Keep chasing whether the ball is still flying or already rolling
	if not ball.in_flight and not ball.is_loose:
		_stop_attacker_chase()
		kickoff_chase = false
		return

	# Only the locked receiver chases, and we just refresh their target.
	# No re-sorting, so control and roles cannot flicker.
	if kickoff_receiver and is_instance_valid(kickoff_receiver):
		kickoff_receiver.is_chasing_ball = true
		kickoff_receiver.chase_ball_pos = ball.global_position


# The nearest N attackers go for the ball. They move themselves in their own
# _physics_process — we only hand them a target, so nothing fights for control.
func _attackers_chase(ball: Ball, how_many: int, give_control: bool = true) -> void:
	var list: Array = get_tree().get_nodes_in_group("attackers")
	if list.is_empty():
		return

	list.sort_custom(func(a, b):
		return a.global_position.distance_to(ball.global_position) \
			 < b.global_position.distance_to(ball.global_position)
	)

	for i in range(list.size()):
		var a = list[i]
		if i < how_many:
			# Chasers sprint at the ball
			a.is_chasing_ball = true
			a.chase_ball_pos = ball.global_position
		else:
			# Everyone else comes up in a line at running pace
			a.is_chasing_ball = false
			a.advance_to_x = ball.global_position.x - 40.0

	# Hand the human the closest chaser (not during a kick-off)
	if give_control:
		var nearest = list[0]
		if not nearest.is_user_controlled:
			_set_control(nearest)
			current_carrier = nearest
		nearest.is_chasing_ball = false   # you drive this one yourself


func _stop_attacker_chase() -> void:
	kickoff_receiver = null
	for a in get_tree().get_nodes_in_group("attackers"):
		a.is_chasing_ball = false
		a.advance_to_x = -1.0


# ---------- KICK ----------

func _on_ball_kicked(from_pos: Vector2) -> void:
	if kickoff_in_progress:
		# Kick-off: the receiving team collects it, defenders just get set
		for d in get_tree().get_nodes_in_group("defenders"):
			d.ball_carrier = null
			d.line_x = Field.centre().x
			d.state = Defender.State.RETREAT
		return

	event_message.emit("KICK")
	chasing_loose = true

	# Work out where the kick is heading and commit the best-placed attacker
	var ball: Ball = get_ball()
	if ball:
		var landing: Vector2 = ball.global_position + ball.velocity_2d * 0.9
		kick_chaser = _closest_in_group_to("attackers", landing)
		if kick_chaser:
			# Nobody is driven while the ball is in the air
			for a in get_tree().get_nodes_in_group("attackers"):
				a.is_user_controlled = false
			kick_chaser.is_chasing_ball = true
			kick_chaser.chase_ball_pos = landing
			kick_control_delay = 0.5     # control passes to them shortly

	# Nobody is carrying now, so no one can be tackled.
	# Defenders break off the chase and turn to compete for the ball.
	for d in get_tree().get_nodes_in_group("defenders"):
		d.ball_carrier = null
		if d.state == Defender.State.CHASE or d.state == Defender.State.COVER:
			d.state = Defender.State.LINE
		d.marker_target = null


# ---------- LOOSE BALL ----------

func _on_ball_became_loose(_pos: Vector2) -> void:
	# During a kick-off the receiver is already locked in — leave it alone
	if kickoff_in_progress:
		return
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
	if kickoff_in_progress:
		return
	var ball: Ball = get_ball()
	if ball == null or ball.carrier != null:
		_stop_attacker_chase()
		chasing_loose = false
		return
	if not ball.is_loose and not ball.in_flight:
		_stop_attacker_chase()
		chasing_loose = false
		return

	# Your closest players race for it as well.
	# If a kick chaser is committed, leave control alone until the delay expires.
	var hand_over: bool = (kick_chaser == null and kick_control_delay <= 0.0)
	_attackers_chase(ball, 2, hand_over)

	# The two nearest defenders compete for the ball; the rest hold the line
	var ranked: Array = get_tree().get_nodes_in_group("defenders")
	ranked.sort_custom(func(a, b):
		return a.global_position.distance_to(ball.global_position) < b.global_position.distance_to(ball.global_position)
	)
	for i in range(ranked.size()):
		var d: Defender = ranked[i]
		if i < 2:
			d.state = Defender.State.CHASE_BALL
			d.chase_target = ball.global_position
		elif d.state == Defender.State.CHASE_BALL:
			d.state = Defender.State.LINE


func _on_ball_picked_up(who: Node2D) -> void:
	chasing_loose = false
	kick_chaser = null
	kick_control_delay = 0.0
	_stop_attacker_chase()
	for d in get_tree().get_nodes_in_group("defenders"):
		if d.state == Defender.State.CHASE_BALL:
			d.state = Defender.State.LINE

	if who.is_in_group("attackers"):
		if kickoff_in_progress:
			kickoff_in_progress = false
			kickoff_chase = false
			event_message.emit("CAUGHT")
			GameState.reset_set()
			event_message.emit("CAUGHT IT")
		current_carrier = who
		_set_control(who)
		_assign_carrier(who)
	else:
		if kickoff_in_progress:
			return    # ignore a stray defender touch during the kick-off
		event_message.emit("TURNOVER")
		GameState.do_turnover()


func _on_ball_caught(who: Node2D) -> void:
	chasing_loose = false
	kick_chaser = null
	kick_control_delay = 0.0
	_stop_attacker_chase()
	if kickoff_in_progress:
		kickoff_in_progress = false
		kickoff_chase = false
		GameState.reset_set()
	current_carrier = who
	_set_control(who)
	_assign_carrier(who)


# ---------- TRY ----------

func _check_for_try() -> void:
	if scoring:
		return
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
	if scoring:
		return
	scoring = true
	GameState.award_try(0)   # 4 points
	event_message.emit("TRY!")
	clock_running = false
	await get_tree().create_timer(2.0).timeout
	clock_running = true
	scoring = false
	_kickoff()


# ---------- TURNOVER / HALVES ----------

func _on_turnover() -> void:
	Engine.time_scale = 1.0
	kick_chaser = null
	kick_control_delay = 0.0
	_stop_attacker_chase()
	line_broken = false
	kickoff_in_progress = false
	kickoff_chase = false
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


# ---------- LINE BREAK ----------

const COVER_CHASERS: int = 3       # how many defenders scramble back on a break
const REGROUP_AHEAD: float = 170.0 # how far goal-side the rest reform

func _handle_line_break() -> void:
	if GameState.phase != GameState.Phase.OPEN_PLAY:
		line_broken = false
		return
	if current_carrier == null:
		line_broken = false
		return
	var ball: Ball = get_ball()
	if ball == null or ball.carrier != current_carrier:
		return

	var carrier_x: float = current_carrier.global_position.x
	var defenders: Array = get_tree().get_nodes_in_group("defenders")

	var in_front: int = 0
	for d in defenders:
		if d.global_position.x > carrier_x:
			in_front += 1

	# HYSTERESIS: hard to enter, hard to leave. Stops the line flickering.
	if not line_broken:
		if in_front > 1:
			return
		line_broken = true          # a break has just happened
	else:
		if in_front >= 3:
			line_broken = false     # line reformed in front of the runner
			return

	# Assign roles ONCE per state change, not every frame
	defenders.sort_custom(func(a, b):
		return a.global_position.distance_to(current_carrier.global_position) \
			 < b.global_position.distance_to(current_carrier.global_position)
	)

	for i in range(defenders.size()):
		var d: Defender = defenders[i]
		if d.state == Defender.State.MARKER or d.state == Defender.State.CHASE_BALL:
			continue
		if d.state == Defender.State.RETREAT:
			continue
		if i < COVER_CHASERS:
			if d.state != Defender.State.COVER:
				d.state = Defender.State.COVER
		else:
			if d.state == Defender.State.COVER:
				d.state = Defender.State.LINE
			var regroup_x: float = min(carrier_x + REGROUP_AHEAD, Field.FIELD_RIGHT - 6.0)
			if regroup_x > d.line_x:
				d.line_x = regroup_x


# ---------- LINE PRESSURE ----------

const LINE_ADVANCE_SPEED: float = 55.0   # px/sec the line creeps up
const LINE_STANDOFF: float = 26.0        # how close in front of the carrier it stops

func _advance_defensive_line(delta: float) -> void:
	if GameState.phase != GameState.Phase.OPEN_PLAY:
		return
	if current_carrier == null:
		return
	if line_broken:
		return    # during a break, the regroup logic controls line_x

	# Never let the line push past the try line — they defend ON it instead
	var target_x: float = min(
		current_carrier.global_position.x + LINE_STANDOFF,
		Field.FIELD_RIGHT - 6.0
	)
	for d in get_tree().get_nodes_in_group("defenders"):
		if d.state != Defender.State.LINE:
			continue   # retreating players must keep the line_x they were given
		d.line_x = move_toward(d.line_x, target_x, LINE_ADVANCE_SPEED * delta)


# ---------- HELPERS ----------

# Prefer a defender already IN FRONT of the ruck, so it never has to
# travel through the tackled player to take up its spot.
func _pick_marker(ruck: Vector2) -> Defender:
	var best: Defender = null
	var best_dist: float = INF
	for d in get_tree().get_nodes_in_group("defenders"):
		if d.global_position.x < ruck.x:
			continue                      # this one is behind the ruck, skip it
		var dist: float = d.global_position.distance_to(ruck)
		if dist < best_dist:
			best_dist = dist
			best = d
	# Nobody in front? Fall back to the nearest defender of any kind.
	if best == null:
		best = _closest_defender_to(ruck)
	return best


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
