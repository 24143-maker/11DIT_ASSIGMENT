extends CharacterBody2D
class_name Defender
# Defensive line AI.
#   LINE       - hold the defensive line, shift as a unit with the ball
#   CHASE      - commit to the tackle
#   COVER      - the carrier is PAST me: scramble back and cut them off
#   RETREAT    - get back to the line after a tackle
#   MARKER     - stand over the tackled player at the ruck
#   CHASE_BALL - go and get a loose ball

enum State { LINE, CHASE, RETREAT, MARKER, CHASE_BALL, COVER, FULLBACK, ATT_CARRY, ATT_SUPPORT, ATT_RUCK }

@export var base_speed: float = 126.0
@export var cover_speed: float = 150.0        # sprinting back after a break
@export var retreat_speed_mult: float = 1.42   # brisk jog back into position
@export var tackle_radius: float = 24.0
@export var tackle_hold_time: float = 0.50    # seconds of contact to complete a tackle
@export var reaction_delay: float = 0.10
@export var chase_distance: float = 95.0
@export var line_slide: float = 0.45          # how far the line shifts toward the ball
@export var is_fullback: bool = false         # the last line of defence
@export var fullback_depth: float = 190.0     # how far behind the line he sits
@export var fullback_speed: float = 178.0     # quickest player on the field
@export var fullback_tackle_time: float = 0.12  # once he touches you, you're down
@export var fullback_reach: float = 30.0        # slightly longer reach than a line defender
@export var attack_speed: float = 118.0         # pace when this team has the ball
@export var attack_slot: Vector2 = Vector2(-40, 272)   # support shape when attacking
@export var give_up_distance: float = 190.0   # stop covering if beaten by more than this
@export var marker_move_speed: float = 340.0  # how fast the marker gets square in front

var state: State = State.LINE
var slot_index: int = 0
var slot_count: int = 6
var slot_y: float = 100.0
var line_x: float = 500.0
var ball_carrier: Node2D = null
var marker_target: Node2D = null
var marker_pos: Vector2 = Vector2.ZERO
var chase_target: Vector2 = Vector2.ZERO

var contact_timer: float = 0.0
var _grace: float = 0.0
var _react_timer: float = 0.0
var _tackle_pos: Vector2 = Vector2.ZERO   # furthest point the carrier reached in this tackle
var _saved_mask: int = -1                 # collision mask stored while retreating
var _stuck_timer: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _marker_mask: int = -1              # collision mask stored while acting as marker
var _marker_anchor: Vector2 = Vector2.ZERO   # frozen ruck spot the marker holds

const GRACE_TIME: float = 0.20
const MARKER_OFFSET_PX: float = 16.0
const MARKER_DEADZONE: float = 5.0     # stop when this close to the marker spot
const SPACING: float = 78.0                   # gap between defenders in the line
const STUCK_TIME: float = 0.6                 # retreating this long without moving = snap home
const AVOID_RADIUS: float = 30.0              # start steering around players this close
const AVOID_STRENGTH: float = 95.0            # how hard we swerve
const MARKER_ANCHOR_LERP: float = 0.25        # how fast the marker settles on its spot


func _ready() -> void:
	add_to_group("defenders")
	# Layer 4 = defenders. Mask 1 = field walls only.
	collision_layer = 4
	collision_mask = 1


func _physics_process(delta: float) -> void:
	# If we left RETREAT by any route, make sure collision is turned back on
	if state != State.RETREAT and _saved_mask != -1:
		_restore_collision()

	# Same for the marker's collision
	if state != State.MARKER and _marker_mask != -1:
		collision_mask = _marker_mask
		_marker_mask = -1
		_marker_anchor = Vector2.ZERO

	# The marker is PLACED, not driven — physics can't shove it out of position
	if state == State.MARKER:
		_do_marker(delta)
		return

	match state:
		State.LINE:       _do_line(delta)
		State.CHASE:      _do_chase(delta)
		State.COVER:      _do_cover(delta)
		State.RETREAT:    _do_retreat(delta)
		State.CHASE_BALL: _do_chase_ball(delta)
		State.FULLBACK:   _do_fullback(delta)
		State.ATT_CARRY:  _do_att_carry(delta)
		State.ATT_SUPPORT:_do_att_support(delta)
		State.ATT_RUCK:   _do_att_ruck(delta)
	move_and_slide()


# ---------- LINE ----------

func _do_line(delta: float) -> void:
	contact_timer = 0.0

	line_x = clamp(line_x, Field.FIELD_LEFT, Field.FIELD_RIGHT - 6.0)
	var target := Vector2(line_x, slot_y)

	if ball_carrier and GameState.can_tackle() and _carrier_actually_has_ball():
		# The whole line shifts toward the ball but KEEPS ITS SPACING (no gaps)
		var mid: float = float(slot_count - 1) * 0.5
		var line_centre: float = lerp(Field.FIELD_BOTTOM * 0.5, ball_carrier.global_position.y, line_slide)
		target.y = line_centre + (float(slot_index) - mid) * SPACING
		target.y = clamp(target.y, 30.0, Field.FIELD_BOTTOM - 30.0)

		# Commit to the tackle if I'm one of the two nearest and close enough
		var dist: float = global_position.distance_to(ball_carrier.global_position)
		if dist < chase_distance and _my_rank_to_carrier() < 2:
			_react_timer += delta
			if _react_timer >= reaction_delay:
				state = State.CHASE
				_react_timer = 0.0
				contact_timer = 0.0
				_grace = 0.0
		else:
			_react_timer = 0.0

	velocity = _avoid((target - global_position).limit_length(base_speed), ball_carrier)


# ---------- CHASE / TACKLE ----------

func _do_chase(delta: float) -> void:
	if ball_carrier == null or not GameState.can_tackle() or not _carrier_actually_has_ball():
		_end_chase()
		return

	# Carrier got past me — switch to covering
	if ball_carrier.global_position.x > global_position.x + 6.0:
		state = State.COVER
		contact_timer = 0.0
		return

	var dist: float = global_position.distance_to(ball_carrier.global_position)

	if dist < tackle_radius:
		if contact_timer <= 0.0:
			_tackle_pos = ball_carrier.global_position
		_track_ground_made()
		_grace = GRACE_TIME
		# More tacklers = the tackle completes faster
		var tacklers: int = _count_tacklers()
		contact_timer += delta * (1.0 + 0.7 * float(max(tacklers - 1, 0)))
		velocity = (ball_carrier.global_position - global_position).limit_length(base_speed)
		if contact_timer >= tackle_hold_time:
			_complete_tackle()
		return

	if _grace > 0.0:
		_grace -= delta
	else:
		contact_timer = 0.0

	if dist > chase_distance * 1.8:
		_end_chase()
		return

	var lead: Vector2 = ball_carrier.velocity * 0.20
	var want: Vector2 = (ball_carrier.global_position + lead - global_position).normalized() * base_speed
	velocity = _avoid(want, ball_carrier)


# ---------- COVER (line break) ----------

func _do_cover(delta: float) -> void:
	if ball_carrier == null or not GameState.can_tackle() or not _carrier_actually_has_ball():
		_end_chase()
		return

	# Back in front of the carrier — rejoin the line
	if global_position.x > ball_carrier.global_position.x + 40.0:
		state = State.LINE
		return

	# Hopelessly beaten — stop chasing and reform instead of trailing forever
	if ball_carrier.global_position.x - global_position.x > give_up_distance:
		state = State.LINE
		return

	var dist: float = global_position.distance_to(ball_carrier.global_position)

	if dist < tackle_radius:
		if contact_timer <= 0.0:
			_tackle_pos = ball_carrier.global_position
		_track_ground_made()
		_grace = GRACE_TIME
		var tacklers: int = _count_tacklers()
		contact_timer += delta * (1.0 + 0.7 * float(max(tacklers - 1, 0)))
		velocity = (ball_carrier.global_position - global_position).limit_length(cover_speed)
		if contact_timer >= tackle_hold_time:
			_complete_tackle()
		return

	if _grace > 0.0:
		_grace -= delta
	else:
		contact_timer = 0.0

	# Aim at an intercept point ahead of the carrier, not where they are now
	var intercept: Vector2 = ball_carrier.global_position + ball_carrier.velocity * 0.45
	velocity = _avoid((intercept - global_position).normalized() * cover_speed, ball_carrier)


# ---------- OTHER STATES ----------

func _do_retreat(delta: float) -> void:
	contact_timer = 0.0

	if _saved_mask == -1:
		_saved_mask = collision_mask
		_stuck_timer = 0.0
		_last_pos = global_position

	line_x = clamp(line_x, Field.FIELD_LEFT, Field.FIELD_RIGHT - 6.0)
	var target := Vector2(line_x, slot_y)
	var to_target: Vector2 = target - global_position

	if to_target.length() < 12.0:
		velocity = Vector2.ZERO
		_restore_collision()
		state = State.LINE
		return

	# Backstop: only fires if we are genuinely jammed, not just arriving
	if global_position.distance_to(_last_pos) < 0.5:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_TIME:
			global_position = target
			velocity = Vector2.ZERO
			_restore_collision()
			state = State.LINE
			return
	else:
		_stuck_timer = 0.0
	_last_pos = global_position

	# normalized() keeps full speed all the way in — limit_length() would slow
	# us down as the gap closed, which looked like stalling.
	velocity = to_target.normalized() * (base_speed * retreat_speed_mult)


# Steer around other players instead of running into them.
# 'ignore' is the one player we're deliberately running at (the ball carrier).
func _avoid(desired: Vector2, ignore: Node2D = null) -> Vector2:
	var push := Vector2.ZERO
	for grp in ["attackers", "defenders"]:
		for other in get_tree().get_nodes_in_group(grp):
			if other == self or other == ignore:
				continue
			var away: Vector2 = global_position - other.global_position
			var d: float = away.length()
			if d < 0.01 or d > AVOID_RADIUS:
				continue
			# closer = stronger push, and mostly sideways so we go around
			var strength: float = (1.0 - d / AVOID_RADIUS) * AVOID_STRENGTH
			push += away.normalized() * strength
	if push == Vector2.ZERO:
		return desired
	return (desired + push).normalized() * desired.length()


func _restore_collision() -> void:
	if _saved_mask != -1:
		collision_mask = _saved_mask
		_saved_mask = -1
	_stuck_timer = 0.0


func _do_marker(delta: float) -> void:
	contact_timer = 0.0
	velocity = Vector2.ZERO

	if marker_target == null or not is_instance_valid(marker_target):
		return

	# Square in front of the tackled player: same y, fixed distance ahead.
	# Nothing can push us or them any more, so this stays exact.
	marker_pos = Vector2(
		marker_target.global_position.x + MARKER_OFFSET_PX,
		marker_target.global_position.y
	)
	global_position = global_position.move_toward(marker_pos, marker_move_speed * delta)


func _do_chase_ball(_delta: float) -> void:
	contact_timer = 0.0
	# Chasing a kick is a flat-out sprint, not a jog
	var spd: float = fullback_speed if is_fullback else (cover_speed * 1.12)
	var to_target: Vector2 = chase_target - global_position
	if to_target.length() > 6.0:
		velocity = _avoid(to_target.normalized() * spd)
	else:
		velocity = Vector2.ZERO


# Sits deep behind the line, shadowing the ball across the field.
# Steps up and puts down anyone who breaks through.
func _do_fullback(delta: float) -> void:
	if ball_carrier == null:
		contact_timer = 0.0
		velocity = Vector2.ZERO
		return

	var can_hit: bool = GameState.can_tackle() and _carrier_actually_has_ball()

	if can_hit:
		var dist: float = global_position.distance_to(ball_carrier.global_position)

		# Touched him — the fullback does not miss one on one
		if dist < fullback_reach:
			_grace = GRACE_TIME
			if contact_timer <= 0.0:
				_tackle_pos = ball_carrier.global_position
			_track_ground_made()
			contact_timer += delta
			# Latch on: match his movement so he cannot be shrugged off
			velocity = (ball_carrier.global_position - global_position).limit_length(fullback_speed)
			if contact_timer >= fullback_tackle_time:
				_complete_tackle()
			return

		# Brief grace so a half-step out of reach doesn't reset the hold
		if _grace > 0.0:
			_grace -= delta
		else:
			contact_timer = 0.0

		# A break is judged by how many LINE defenders are still goal-side of
		# the carrier. Using the deepest defender alone meant a single
		# straggler behind the carrier hid an obvious break.
		var cover_ahead: int = 0
		for d in get_tree().get_nodes_in_group("defenders"):
			if d.is_fullback:
				continue
			if d.global_position.x > ball_carrier.global_position.x + 10.0:
				cover_ahead += 1

		# Broken through, or simply close enough that I am the only one left
		var broken: bool = cover_ahead <= 1 or dist < 170.0

		if broken:
			var lead: float = clamp(dist / fullback_speed, 0.15, 0.6)
			var intercept: Vector2 = ball_carrier.global_position + ball_carrier.velocity * lead
			velocity = _avoid((intercept - global_position).normalized() * fullback_speed, ball_carrier)
			return

	contact_timer = 0.0

	# Otherwise hold station BEHIND the line, shadowing the ball.
	# Never allow a target in front of the rearmost line defender.
	var line_now: float = _rearmost_line_x()
	var deep_x: float = max(line_now + fullback_depth, line_now + 40.0)
	deep_x = clamp(deep_x, Field.FIELD_LEFT, Field.FIELD_RIGHT - 10.0)

	var target := Vector2(deep_x, lerp(Field.FIELD_BOTTOM * 0.5, ball_carrier.global_position.y, 0.7))
	target.y = clamp(target.y, 30.0, Field.FIELD_BOTTOM - 30.0)

	# If we've somehow ended up ahead of the line, get back fast
	if global_position.x < line_now + 20.0:
		velocity = Vector2(fullback_speed, (target.y - global_position.y) * 0.6)
		return

	# Never back away from a carrier who is close — hold the line of defence
	# and only track sideways.
	if ball_carrier.global_position.distance_to(global_position) < 200.0:
		if target.x > global_position.x:
			target.x = global_position.x

	velocity = _avoid((target - global_position).limit_length(base_speed), ball_carrier)


# ---------------- ATTACKING (this team has the ball) ----------------

# Run at the biggest gap in the defending line, drifting to avoid contact
func _do_att_carry(_delta: float) -> void:
	contact_timer = 0.0
	var gap_y: float = _biggest_gap_y()
	var aim := Vector2(Field.FIELD_LEFT - 40.0, gap_y)   # AI attacks right to left
	var dir: Vector2 = (aim - global_position).normalized()
	velocity = _avoid(dir * attack_speed)


# Hold a support shape behind the carrier so a pass is always on
func _do_att_support(_delta: float) -> void:
	contact_timer = 0.0
	if ball_carrier == null:
		velocity = Vector2.ZERO
		return
	# AI attacks toward -x, so "behind" is a LARGER x
	var target := Vector2(ball_carrier.global_position.x - attack_slot.x, attack_slot.y)
	target.x = clamp(target.x, Field.FIELD_LEFT, Field.FIELD_RIGHT + 40.0)
	target.y = clamp(target.y, 30.0, Field.FIELD_BOTTOM - 30.0)
	velocity = _avoid((target - global_position).limit_length(attack_speed))


func _do_att_ruck(_delta: float) -> void:
	contact_timer = 0.0
	velocity = Vector2.ZERO


# Find the widest gap in the human team's defensive line
func _biggest_gap_y() -> float:
	var ys: Array = []
	for a in get_tree().get_nodes_in_group("attackers"):
		ys.append(a.global_position.y)
	if ys.is_empty():
		return Field.FIELD_BOTTOM * 0.5
	ys.sort()

	var best_gap: float = ys[0] - 0.0
	var best_y: float = ys[0] * 0.5
	for i in range(ys.size() - 1):
		var g: float = ys[i + 1] - ys[i]
		if g > best_gap:
			best_gap = g
			best_y = (ys[i] + ys[i + 1]) * 0.5
	var tail: float = Field.FIELD_BOTTOM - ys[ys.size() - 1]
	if tail > best_gap:
		best_y = (ys[ys.size() - 1] + Field.FIELD_BOTTOM) * 0.5
	return clamp(best_y, 40.0, Field.FIELD_BOTTOM - 40.0)


# The x of the deepest line defender — the real edge of the defence
func _rearmost_line_x() -> float:
	var best: float = -1.0
	for d in get_tree().get_nodes_in_group("defenders"):
		if d.is_fullback:
			continue
		if d.global_position.x > best:
			best = d.global_position.x
	if best < 0.0:
		best = line_x
	return best


func _end_chase() -> void:
	contact_timer = 0.0
	_grace = 0.0
	state = State.LINE


# ---------- HELPERS ----------

# You can't tackle a player who has already passed or kicked the ball away
func _carrier_actually_has_ball() -> bool:
	for n in get_tree().get_nodes_in_group("ball"):
		if n is Ball:
			return n.carrier == ball_carrier
	return false


# 0 = I'm the closest defender to the carrier, 1 = second closest, etc.
func _my_rank_to_carrier() -> int:
	if ball_carrier == null:
		return 99
	var my_dist: float = global_position.distance_to(ball_carrier.global_position)
	var rank: int = 0
	for d in get_tree().get_nodes_in_group("defenders"):
		if d == self or d.state == State.MARKER or d.is_fullback:
			continue
		if d.global_position.distance_to(ball_carrier.global_position) < my_dist:
			rank += 1
	return rank


func _count_tacklers() -> int:
	if ball_carrier == null:
		return 0
	var n: int = 0
	for d in get_tree().get_nodes_in_group("defenders"):
		if d.state != State.CHASE and d.state != State.COVER:
			continue
		if d.global_position.distance_to(ball_carrier.global_position) < d.tackle_radius:
			n += 1
	return n


# The attacker keeps any ground they fight forward for — they never lose metres
func _track_ground_made() -> void:
	if ball_carrier == null:
		return
	if ball_carrier.global_position.x > _tackle_pos.x:
		_tackle_pos = ball_carrier.global_position


func _complete_tackle() -> void:
	contact_timer = 0.0
	_grace = 0.0
	if not GameState.can_tackle():
		return
	# Final check: they may have offloaded in the last split second
	if not _carrier_actually_has_ball():
		_end_chase()
		return
	GameState.tackled_player = ball_carrier
	if _tackle_pos == Vector2.ZERO and ball_carrier:
		_tackle_pos = ball_carrier.global_position
	GameState.tackle_position = _tackle_pos
	GameState.phase = GameState.Phase.RUCK
	GameState.register_tackle()
