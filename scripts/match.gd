extends Node2D
# Runs the match: kickoff, tackles, play-the-ball, tries, loose balls, clock.

const RETREAT_METRES: float = 12.0
const MARKER_METRES: float = 1.5
# Line defenders. Set at runtime to (number of attackers - 1) so the two
# teams are even once the fullback is included.
var DEFENDER_COUNT: int = 5
const DEFENDER_SCENE := preload("res://scenes/entities/defender.tscn")

# Squad names, applied in scene-tree order to any player left as "Player"
const SQUAD: Array = ["Liam", "Ben", "Christian", "Max", "Olly", "Jack"]

# Attacking shape, relative to the ball carrier.
# x = how far behind the carrier, y = lane across the field.
# Shallow through the middle, deeper and wider out to the edges, with a
# sweeper sitting behind — a proper attacking diamond rather than a flat line.
const ATTACK_SHAPE: Array = [
	Vector2(-18,  86),    # blindside wing, up in support
	Vector2(-30, 170),    # centre
	Vector2(-22, 256),    # first receiver, close to the ball
	Vector2(-30, 340),    # centre
	Vector2(-18, 424),    # openside wing
	Vector2(-72, 272),    # sweeper / fullback, deep in the middle
]

const HALF_LENGTH: float = 180.0    # seconds per half (3 min for testing)

var current_carrier: Node2D = null
var marker_defender: Defender = null
var chasing_loose: bool = false
var line_broken: bool = false
var kickoff_in_progress: bool = false
var scoring: bool = false
var kickoff_chase: bool = false
var kickoff_landing: Vector2 = Vector2.ZERO
var kickoff_receiver: Node2D = null    # locked once, never reassigned
var fullback: Defender = null          # the defending team's last line
var fullback_hunting: bool = false     # true while he is going for a kicked ball
var ai_carrier: Node2D = null        # the AI's ball runner when they attack
var ai_pass_timer: float = 0.0
var switch_cooldown: float = 0.0
var _pending_result = null
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
	_handle_player_switch(delta)
	_keep_fullback_deep()
	_update_fullback_hunt()
	_update_ai_set(delta)

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
		if list[i].player_name == "" or list[i].player_name == "Player":
			list[i].player_name = SQUAD[i % SQUAD.size()]
		# Give every attacker its slot in the attacking shape
		list[i].line_slot = ATTACK_SHAPE[i % ATTACK_SHAPE.size()]


func get_ball() -> Ball:
	for n in get_tree().get_nodes_in_group("ball"):
		if n is Ball:
			return n
	return null


func _spawn_defensive_line(line_x: float) -> void:
	# Match the attacking side: one fewer in the line, plus a fullback
	var att_count: int = get_tree().get_nodes_in_group("attackers").size()
	DEFENDER_COUNT = max(att_count - 1, 3)

	var spacing: float = Field.FIELD_BOTTOM / float(DEFENDER_COUNT + 1)
	for i in range(DEFENDER_COUNT):
		var d: Defender = DEFENDER_SCENE.instantiate()
		d.slot_index = i
		d.slot_count = DEFENDER_COUNT
		d.slot_y = spacing * float(i + 1)
		d.line_x = line_x
		d.global_position = Vector2(line_x, d.slot_y)
		add_child(d)

	# The fullback sits deep and is not part of the line
	fullback = DEFENDER_SCENE.instantiate()
	fullback.is_fullback = true
	fullback.slot_index = DEFENDER_COUNT
	fullback.slot_count = DEFENDER_COUNT
	fullback.slot_y = Field.FIELD_BOTTOM * 0.5
	fullback.line_x = line_x
	fullback.global_position = Vector2(line_x + fullback.fullback_depth, fullback.slot_y)
	fullback.state = Defender.State.FULLBACK
	add_child(fullback)


# Receiving arrow: point man up front, then two pairs fanning back and wide.
# x is metres-ish behind the point, y is the spread from the middle.
const RECEIVE_SHAPE: Array = [
	Vector2(0, 0),        # point of the arrow
	Vector2(-70, -100),   # first pair
	Vector2(-70, 100),
	Vector2(-116, -190),  # wide pair
	Vector2(-116, 190),
	Vector2(-150, 0),     # sweeper behind
]

func _kickoff() -> void:
	GameState.reset_set()
	GameState.possession = 0
	GameState.turnover_position = Vector2.ZERO
	ai_carrier = null
	for a in get_tree().get_nodes_in_group("attackers"):
		a.def_is_fullback = false
	_restore_defensive_roles(Field.centre().x + 45.0)
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
		d.line_x = Field.centre().x + 45.0
		if d.is_fullback:
			d.state = Defender.State.FULLBACK
			continue          # placed on the centre spot below
		d.slot_y = spacing * float(i2 + 1)
		d.global_position = Vector2(d.line_x, d.slot_y)
		d.state = Defender.State.LINE
		i2 += 1

	# The FULLBACK takes the kick-off, then drops straight back to his post
	var kicker: Defender = fullback if (fullback and is_instance_valid(fullback)) \
						   else _closest_defender_to(Field.centre())
	var ball: Ball = get_ball()
	if kicker == null or ball == null:
		return

	kicker.global_position = Field.centre()
	kicker.state = Defender.State.LINE     # stand still over the ball
	ball.give_to(kicker)

	GameState.phase = GameState.Phase.OPEN_PLAY
	event_message.emit("KICK OFF")

	await get_tree().create_timer(1.0).timeout
	if not kickoff_in_progress:
		return

	# Random landing spot somewhere in the receiving half
	# A kick-off must travel at least 30m from halfway.
	# Halfway is x=448, so the ball has to land at x <= 208.
	kickoff_landing = Vector2(
		randf_range(Field.FIELD_LEFT + 40.0, Field.FIELD_LEFT + 160.0),
		randf_range(80.0, Field.FIELD_BOTTOM - 80.0)
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

	# Kicker returns to his post right away.
	# Snap him back toward his depth so he isn't stranded on halfway.
	if kicker.is_fullback:
		kicker.state = Defender.State.FULLBACK
		kicker.line_x = kickoff_landing.x + 40.0
		# Drop straight back to a deep covering position behind the chase line
		kicker.global_position = Vector2(
			clamp(kickoff_landing.x + 260.0, Field.centre().x, Field.FIELD_RIGHT - 30.0),
			Field.FIELD_BOTTOM * 0.5
		)
	else:
		kicker.state = Defender.State.RETREAT

	# The chasing line advances on the ball straight away
	for d in get_tree().get_nodes_in_group("defenders"):
		if d == kicker or d.is_fullback:
			continue
		d.line_x = kickoff_landing.x + 30.0
		d.state = Defender.State.LINE


func _first_attacker() -> Node2D:
	for a in get_tree().get_nodes_in_group("attackers"):
		return a
	return null


func _reset_attack_positions(around: Vector2) -> void:
	for a in get_tree().get_nodes_in_group("attackers"):
		a.is_playing_the_ball = false
		a.global_position = Vector2(around.x + a.line_slot.x, a.line_slot.y)
	var first = _first_attacker()
	if first:
		first.global_position = around


func _reset_defensive_line(line_x: float) -> void:
	for d in get_tree().get_nodes_in_group("defenders"):
		d.line_x = line_x
		d.marker_target = null
		d.state = Defender.State.FULLBACK if d.is_fullback else Defender.State.RETREAT
	marker_defender = null


# ---------- BALL / CONTROL ----------

func _give_ball_to(who: Node2D) -> void:
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
	fullback_hunting = false
	kick_chaser = null
	kick_control_delay = 0.0
	_stop_attacker_chase()
	line_broken = false
	GameState.phase = GameState.Phase.RUCK
	event_message.emit("TACKLE %d" % tackle_number)

	# If the AI is attacking, they run their own play-the-ball
	if GameState.player_defending():
		_ai_play_the_ball()
		return

	# The player who was tackled is the one who plays the ball — not whoever
	# happens to be "current_carrier" if a pass was in the air.
	if GameState.tackled_player and is_instance_valid(GameState.tackled_player) \
	   and GameState.tackled_player.is_in_group("attackers"):
		current_carrier = GameState.tackled_player
		_set_control(current_carrier)
		_assign_carrier(current_carrier)

	# Guard: the human's ruck logic only ever applies to one of your players
	if current_carrier == null or not current_carrier.is_in_group("attackers"):
		return

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
		d.marker_target = null
		if d.is_fullback:
			d.state = Defender.State.FULLBACK
			continue
		d.slot_y = spacing * float(d.slot_index + 1)
		d.state = Defender.State.RETREAT


func _on_played_the_ball() -> void:
	GameState.phase = GameState.Phase.OPEN_PLAY
	if marker_defender:
		marker_defender.state = Defender.State.LINE
		marker_defender.marker_target = null
		marker_defender = null


func _ai_play_the_ball() -> void:
	var ruck: Vector2 = GameState.tackle_position

	var tackled: Node2D = GameState.tackled_player
	if tackled and is_instance_valid(tackled) and tackled.is_in_group("defenders"):
		ai_carrier = tackled
	if ai_carrier and is_instance_valid(ai_carrier):
		ai_carrier.global_position = ruck
		ai_carrier.state = Defender.State.ATT_RUCK

	for d in get_tree().get_nodes_in_group("defenders"):
		if d == ai_carrier:
			continue
		d.state = Defender.State.ATT_SUPPORT
		d.ball_carrier = ai_carrier

	_set_human_defence(ruck, true)

	await get_tree().create_timer(0.9).timeout

	if ai_carrier and is_instance_valid(ai_carrier):
		ai_carrier.state = Defender.State.ATT_CARRY
		var ball: Ball = get_ball()
		if ball:
			ball.give_to(ai_carrier)

	# Marker rejoins the line
	for a in get_tree().get_nodes_in_group("attackers"):
		if a.def_is_marker:
			a.def_is_marker = false
			a.def_state = Footballer.DState.LINE

	GameState.phase = GameState.Phase.OPEN_PLAY
	_hand_defensive_control()


# Lay out your defence: retreat line, even slots, a marker and a fullback.
# Mirrors what _on_tackle_made does for the AI defence.
func _set_human_defence(ruck: Vector2, with_marker: bool) -> void:
	var line_x: float = clamp(
		ruck.x - Field.metres_to_pixels(RETREAT_METRES),
		Field.FIELD_LEFT + 6.0, Field.FIELD_RIGHT
	)

	var atk: Array = get_tree().get_nodes_in_group("attackers")
	if atk.is_empty():
		return

	# Nominate the fullback: the deepest player (largest x)
	var fb = atk[0]
	for a in atk:
		if a.global_position.x > fb.global_position.x:
			fb = a

	# Marker: nearest to the ruck, never the fullback
	var marker_man = null
	var best: float = INF
	if with_marker:
		for a in atk:
			if a == fb:
				continue
			var dd: float = a.global_position.distance_to(ruck)
			if dd < best:
				best = dd
				marker_man = a

	var line_men: int = max(atk.size() - 1, 1)
	var gap: float = Field.FIELD_BOTTOM / float(line_men + 1)
	var slot: int = 0

	for a in atk:
		a.def_contact = 0.0
		a.def_react = 0.0
		a.def_grace = 0.0
		a.def_line_x = line_x
		a.def_is_fullback = (a == fb)
		a.def_is_marker = (a == marker_man)
		a.is_chasing_ball = false
		a.advance_to_x = -1.0
		a.is_playing_the_ball = false

		if a.def_is_fullback:
			a.def_state = Footballer.DState.FULLBACK
			continue
		if a.def_is_marker:
			a.def_state = Footballer.DState.MARKER
			a.def_marker_pos = ruck - Vector2(MARKER_METRES * Field.METRE, 0)
			continue

		a.def_slot_index = slot
		a.def_slot_count = line_men
		a.def_slot_y = gap * float(slot + 1)
		a.def_state = Footballer.DState.RETREAT
		slot += 1


# ---------- SWITCHING PLAYERS ON DEFENCE ----------

# While defending, tapping W or S moves control up or down the line.
func _handle_player_switch(delta: float) -> void:
	if switch_cooldown > 0.0:
		switch_cooldown -= delta
	if not GameState.player_defending():
		return
	if switch_cooldown > 0.0:
		return

	# J and L step control along the defensive line
	var dir: int = 0
	if Input.is_action_just_pressed("pass_left"):
		dir = -1
	elif Input.is_action_just_pressed("pass_right"):
		dir = 1
	if dir == 0:
		return

	var list: Array = get_tree().get_nodes_in_group("attackers")
	if list.size() < 2:
		return
	# Order down the field so switching feels like moving along the line
	list.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)

	var idx: int = 0
	for i in range(list.size()):
		if list[i].is_user_controlled:
			idx = i
			break

	var next_i: int = wrapi(idx + dir, 0, list.size())
	for a in list:
		a.is_user_controlled = (a == list[next_i])
	switch_cooldown = 0.18


# ---------- AI ATTACKING SET ----------

func _update_ai_set(delta: float) -> void:
	if not GameState.player_defending():
		return
	if ai_carrier == null or not is_instance_valid(ai_carrier):
		return
	if GameState.phase != GameState.Phase.OPEN_PLAY:
		return

	var ball: Ball = get_ball()
	if ball == null or ball.carrier != ai_carrier:
		return

	# Keep everyone pointed at the current runner
	for d in get_tree().get_nodes_in_group("defenders"):
		if d != ai_carrier:
			d.ball_carrier = ai_carrier

	# Only pass when genuinely shut down, and never twice in quick succession
	ai_pass_timer -= delta
	var pressure: int = 0
	for a in get_tree().get_nodes_in_group("attackers"):
		if a.global_position.distance_to(ai_carrier.global_position) < 38.0:
			pressure += 1

	if pressure >= 1 and ai_pass_timer <= 0.0 and randf() < 0.35:
		_ai_try_pass()

	# Last tackle: kick rather than hand it back
	if GameState.tackle_count >= GameState.TACKLES_PER_SET - 1:
		if ai_carrier.global_position.x < Field.FIELD_LEFT + 260.0 and pressure > 0:
			_ai_kick()


func _ai_try_pass() -> void:
	var best: Defender = null
	var best_d: float = 210.0
	for d in get_tree().get_nodes_in_group("defenders"):
		if d == ai_carrier:
			continue
		var off: Vector2 = d.global_position - ai_carrier.global_position
		# AI attacks toward -x, so a legal pass goes to someone with LARGER x
		if off.x < -6.0:
			continue
		var dist: float = off.length()
		# Must be a real pass, and the receiver must have more space than me
		if dist < best_d and dist > 70.0 and _space_around(d) > _space_around(ai_carrier):
			best_d = dist
			best = d
	if best == null:
		return

	var ball: Ball = get_ball()
	if ball == null:
		return
	ball.pass_to(ai_carrier, best)
	ai_carrier.state = Defender.State.ATT_SUPPORT
	ai_carrier = best
	ai_carrier.state = Defender.State.ATT_CARRY
	ai_pass_timer = 1.6
	_hand_defensive_control()


# How far the nearest human defender is from this player
func _space_around(who: Node2D) -> float:
	var best: float = 9999.0
	for a in get_tree().get_nodes_in_group("attackers"):
		var d: float = a.global_position.distance_to(who.global_position)
		if d < best:
			best = d
	return best


func _ai_kick() -> void:
	var ball: Ball = get_ball()
	if ball == null or ball.carrier != ai_carrier:
		return
	var dir := Vector2(-1.0, randf_range(-0.18, 0.18)).normalized()
	var kind: String = "grubber" if randf() < 0.4 else "long"
	ball.kick(ai_carrier.global_position, dir, 0.9, kind)
	event_message.emit("THEY KICK")
	ai_carrier = null


# The fullback must always be doing his job unless he is chasing a ball
# or the AI team is attacking. Other systems used to strand him in the line.
func _keep_fullback_deep() -> void:
	if fullback == null or not is_instance_valid(fullback):
		return
	if GameState.player_defending():
		return                      # he's an attacker right now
	if fullback_hunting:
		return                      # going for a kicked ball
	if kickoff_in_progress:
		return                      # taking / just took the kick-off
	if fullback.state == Defender.State.CHASE_BALL:
		return

	if fullback.state != Defender.State.FULLBACK:
		fullback.state = Defender.State.FULLBACK
	if fullback.ball_carrier == null and current_carrier != null:
		fullback.ball_carrier = current_carrier


# ---------- FULLBACK BALL HUNT ----------

func _update_fullback_hunt() -> void:
	if not fullback_hunting:
		return
	if fullback == null or not is_instance_valid(fullback):
		fullback_hunting = false
		return

	var ball: Ball = get_ball()
	# Stop hunting once someone has it
	if ball == null or ball.carrier != null:
		fullback_hunting = false
		if fullback.state == Defender.State.CHASE_BALL:
			fullback.state = Defender.State.FULLBACK
		return

	# Track the live ball, not a stale prediction
	fullback.state = Defender.State.CHASE_BALL
	fullback.chase_target = ball.global_position

	# Any line defender already chasing keeps his target fresh too
	for d in get_tree().get_nodes_in_group("defenders"):
		if d != fullback and d.state == Defender.State.CHASE_BALL:
			d.chase_target = ball.global_position


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

	var ball: Ball = get_ball()
	var landing: Vector2 = Vector2.ZERO
	if ball:
		landing = ball.global_position + ball.velocity_2d * 0.9

		# THE FULLBACK goes for the ball immediately
		if fullback and is_instance_valid(fullback):
			fullback.state = Defender.State.CHASE_BALL
			fullback.chase_target = ball.global_position
			fullback_hunting = true

		# The two nearest line defenders turn and CHASE the ball down.
		# The rest scramble back to cover.
		var line_d: Array = []
		for d in get_tree().get_nodes_in_group("defenders"):
			if d != fullback:
				line_d.append(d)
		line_d.sort_custom(func(a, b):
			return a.global_position.distance_to(landing) < b.global_position.distance_to(landing)
		)
		for i in range(line_d.size()):
			var d: Defender = line_d[i]
			if i < 2:
				d.state = Defender.State.CHASE_BALL
				d.chase_target = landing
			else:
				d.line_x = max(d.line_x, landing.x - 40.0)
				d.state = Defender.State.RETREAT

	if ball:
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
	fullback_hunting = false
	kick_chaser = null
	kick_control_delay = 0.0
	_stop_attacker_chase()
	for d in get_tree().get_nodes_in_group("defenders"):
		if d.state == Defender.State.CHASE_BALL:
			d.state = Defender.State.FULLBACK if d.is_fullback else Defender.State.LINE

	var picked_by_human_team: bool = who.is_in_group("attackers")
	var human_has_ball: bool = not GameState.player_defending()

	# Possession only changes if the OTHER team got it
	if picked_by_human_team == human_has_ball:
		if picked_by_human_team:
			current_carrier = who
			_set_control(who)
			_assign_carrier(who)
		else:
			# AI regathered their own ball — carry on their set
			ai_carrier = who
			ai_carrier.state = Defender.State.ATT_CARRY
			_hand_defensive_control()
		return

	# Genuine turnover
	if kickoff_in_progress:
		return
	GameState.do_turnover(who.global_position)


func _on_ball_caught(who: Node2D) -> void:
	chasing_loose = false
	fullback_hunting = false
	kick_chaser = null
	kick_control_delay = 0.0
	_stop_attacker_chase()
	if kickoff_in_progress:
		kickoff_in_progress = false
		kickoff_chase = false
		GameState.reset_set()

	# The AI caught one of their own passes — continue their set
	if who.is_in_group("defenders"):
		if GameState.player_defending():
			ai_carrier = who
			ai_carrier.state = Defender.State.ATT_CARRY
			for d in get_tree().get_nodes_in_group("defenders"):
				if d != ai_carrier:
					d.ball_carrier = ai_carrier
			_hand_defensive_control()
		else:
			GameState.do_turnover(who.global_position)
		return

	# One of your players caught it
	if GameState.player_defending():
		GameState.do_turnover(who.global_position)
		return

	current_carrier = who
	_set_control(who)
	_assign_carrier(who)


# ---------- TRY ----------

func _check_for_try() -> void:
	if scoring:
		return

	# AI try: they attack toward the LEFT try line
	if GameState.player_defending():
		if ai_carrier and is_instance_valid(ai_carrier):
			var b: Ball = get_ball()
			if b and b.carrier == ai_carrier and ai_carrier.global_position.x <= Field.FIELD_LEFT:
				scoring = true
				GameState.score[1] += 4
				GameState.score_changed.emit()
				event_message.emit("THEY SCORE")
				clock_running = false
				await get_tree().create_timer(2.0).timeout
				clock_running = true
				scoring = false
				GameState.possession = 0
				_kickoff()
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
	fullback_hunting = false
	kick_chaser = null
	kick_control_delay = 0.0
	chasing_loose = false
	line_broken = false
	kickoff_in_progress = false
	_stop_attacker_chase()
	GameState.phase = GameState.Phase.OPEN_PLAY

	var spot: Vector2 = GameState.turnover_position
	if spot == Vector2.ZERO:
		spot = current_carrier.global_position if current_carrier else Field.centre()
	spot.x = clamp(spot.x, Field.FIELD_LEFT + 30.0, Field.FIELD_RIGHT - 30.0)
	spot.y = clamp(spot.y, 60.0, Field.FIELD_BOTTOM - 60.0)

	# The opposition's set is narrated, not played out
	_run_opposition_set(spot)


# Freeze play, tell the story of their set, then hand the ball back
func _run_opposition_set(spot: Vector2) -> void:
	GameState.phase = GameState.Phase.DEAD
	clock_running = false

	var result = OppositionSet.simulate(spot.x, GameState.AWAY_SHORT)

	var hud := _find_hud()
	if hud == null:
		# No HUD to narrate with — just apply the outcome
		_finish_opposition_set(result)
		return

	if not hud.story_finished.is_connected(_on_story_done):
		hud.story_finished.connect(_on_story_done)
	_pending_result = result
	hud.play_story(result.lines)


func _on_story_done() -> void:
	_finish_opposition_set(_pending_result)
	_pending_result = null


func _finish_opposition_set(result) -> void:
	clock_running = true
	GameState.possession = 0
	GameState.reset_set()
	GameState.turnover_position = Vector2.ZERO
	GameState.phase = GameState.Phase.OPEN_PLAY

	if result == null:
		_start_player_set(Field.centre())
		return

	if result.they_scored:
		GameState.score[1] += 4
		GameState.score_changed.emit()
		event_message.emit("THEY SCORE")
		_kickoff()
		return

	var spot := Vector2(
		clamp(result.restart_x, Field.FIELD_LEFT + 40.0, Field.FIELD_RIGHT - 40.0),
		Field.FIELD_BOTTOM * 0.5
	)
	event_message.emit("OUR BALL")
	_start_player_set(spot)


func _find_hud() -> Node:
	for c in get_children():
		if c is CanvasLayer and c.has_method("play_story"):
			return c
	return null


func _start_player_set(spot: Vector2) -> void:
	ai_carrier = null
	for a in get_tree().get_nodes_in_group("attackers"):
		a.def_is_fullback = false
	_restore_defensive_roles(spot.x + Field.metres_to_pixels(RETREAT_METRES))
	_reset_attack_positions(spot)
	var first = _first_attacker()
	if first:
		first.global_position = spot
		_give_ball_to(first)
	_reset_defensive_line(spot.x + Field.metres_to_pixels(RETREAT_METRES))


# Put every AI player back into their defending job, fullback included
func _restore_defensive_roles(line_x: float) -> void:
	var spacing: float = Field.FIELD_BOTTOM / float(DEFENDER_COUNT + 1)
	var i: int = 0
	for d in get_tree().get_nodes_in_group("defenders"):
		d.marker_target = null
		d.line_x = line_x
		if d.is_fullback:
			d.state = Defender.State.FULLBACK
			d.global_position = Vector2(
				clamp(line_x + d.fullback_depth, Field.FIELD_LEFT, Field.FIELD_RIGHT - 20.0),
				Field.FIELD_BOTTOM * 0.5
			)
			continue
		d.slot_index = i
		d.slot_count = DEFENDER_COUNT
		d.slot_y = spacing * float(i + 1)
		d.state = Defender.State.RETREAT
		i += 1
	marker_defender = null


# The AI team attacks from `spot`; the human defends.
func _start_ai_set(spot: Vector2) -> void:
	var defs: Array = get_tree().get_nodes_in_group("defenders")
	if defs.is_empty():
		return

	# Nearest AI player to the spot becomes the ball runner
	defs.sort_custom(func(a, b):
		return a.global_position.distance_to(spot) < b.global_position.distance_to(spot)
	)
	ai_carrier = defs[0]
	ai_carrier.global_position = spot
	ai_carrier.state = Defender.State.ATT_CARRY

	# Everyone else forms a support shape behind the ball
	var lanes: Array = [110.0, 200.0, 290.0, 380.0, 460.0]
	for i in range(1, defs.size()):
		var d: Defender = defs[i]
		d.state = Defender.State.ATT_SUPPORT
		d.attack_slot = Vector2(-40.0 - float(i) * 8.0, lanes[(i - 1) % lanes.size()])
		d.global_position = Vector2(spot.x + 40.0 + float(i) * 10.0, d.attack_slot.y)
		d.ball_carrier = ai_carrier

	var ball: Ball = get_ball()
	if ball:
		ball.give_to(ai_carrier)

	# Your team drops into a defensive line 10m in front of the ball
	_set_human_defence(spot, false)
	_hand_defensive_control()


# Give the human whichever of their players is nearest the AI ball carrier
func _hand_defensive_control() -> void:
	if ai_carrier == null or not is_instance_valid(ai_carrier):
		return
	var nearest: Node2D = _closest_in_group_to("attackers", ai_carrier.global_position)
	if nearest:
		for a in get_tree().get_nodes_in_group("attackers"):
			a.is_user_controlled = (a == nearest)


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
		if d.is_fullback:
			d.state = Defender.State.FULLBACK
			continue
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

const LINE_ADVANCE_SPEED: float = 165.0  # px/sec the line comes up
const LINE_STANDOFF: float = 20.0        # how close in front of the carrier it stops

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
		if d.is_fullback:
			continue                      # the fullback never marks the ruck
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
