extends CharacterBody2D
class_name Defender
# One defender in the defensive line.
# A tackle completes after holding CONTACT with the carrier for tackle_hold_time.

enum State { LINE, CHASE, RETREAT, MARKER, CHASE_BALL }

@export var base_speed: float = 108.0
@export var tackle_radius: float = 26.0       # generous so contact is stable
@export var reaction_delay: float = 0.15
@export var chase_distance: float = 110.0
@export var retreat_speed_mult: float = 3.0   # snap back to the line fast
@export var tackle_hold_time: float = 1.5     # seconds of contact to complete a tackle
@export var line_slide: float = 0.35          # 0 = stay spread, 1 = all shift to the ball

var state: State = State.LINE
var slot_y: float = 100.0
var line_x: float = 500.0
var ball_carrier: Node2D = null
var marker_pos: Vector2 = Vector2.ZERO
var chase_target: Vector2 = Vector2.ZERO

var contact_timer: float = 0.0
var _grace: float = 0.0            # brief separations don't reset the hold
var _react_timer: float = 0.0

const GRACE_TIME: float = 0.25


func _ready() -> void:
	add_to_group("defenders")


func _physics_process(delta: float) -> void:
	match state:
		State.LINE:       _do_line(delta)
		State.CHASE:      _do_chase(delta)
		State.RETREAT:    _do_retreat(delta)
		State.MARKER:     _do_marker(delta)
		State.CHASE_BALL: _do_chase_ball(delta)
	move_and_slide()


func _do_line(delta: float) -> void:
	contact_timer = 0.0
	var target := Vector2(line_x, slot_y)

	if ball_carrier and GameState.can_tackle():
		target.y = lerp(slot_y, ball_carrier.global_position.y, line_slide)

		var dist: float = global_position.distance_to(ball_carrier.global_position)
		if _am_i_closest_to_carrier() and dist < chase_distance:
			_react_timer += delta
			if _react_timer >= reaction_delay:
				state = State.CHASE
				_react_timer = 0.0
				contact_timer = 0.0
				_grace = 0.0
		else:
			_react_timer = 0.0

	velocity = (target - global_position).limit_length(base_speed)


func _do_chase(delta: float) -> void:
	if ball_carrier == null or not GameState.can_tackle():
		_end_chase()
		return

	var dist: float = global_position.distance_to(ball_carrier.global_position)

	if dist < tackle_radius:
		# In contact — hold on and build the tackle timer
		_grace = GRACE_TIME
		contact_timer += delta
		velocity = (ball_carrier.global_position - global_position).limit_length(base_speed)

		if contact_timer >= tackle_hold_time:
			_complete_tackle()
		return

	# Out of contact — small grace period before the hold resets
	if _grace > 0.0:
		_grace -= delta
	else:
		contact_timer = 0.0

	if dist > chase_distance * 1.8:
		_end_chase()
		return

	var lead: Vector2 = ball_carrier.velocity * 0.22
	velocity = (ball_carrier.global_position + lead - global_position).normalized() * base_speed


func _do_retreat(_delta: float) -> void:
	contact_timer = 0.0
	var target := Vector2(line_x, slot_y)
	velocity = (target - global_position).limit_length(base_speed * retreat_speed_mult)
	if global_position.distance_to(target) < 12.0:
		state = State.LINE


func _do_marker(_delta: float) -> void:
	contact_timer = 0.0
	velocity = (marker_pos - global_position).limit_length(base_speed * 1.5)


func _do_chase_ball(_delta: float) -> void:
	contact_timer = 0.0
	velocity = (chase_target - global_position).limit_length(base_speed)


func _end_chase() -> void:
	contact_timer = 0.0
	_grace = 0.0
	state = State.LINE


func _am_i_closest_to_carrier() -> bool:
	if ball_carrier == null:
		return false
	var my_dist: float = global_position.distance_to(ball_carrier.global_position)
	for d in get_tree().get_nodes_in_group("defenders"):
		if d == self:
			continue
		if d.state == State.MARKER:
			continue
		if d.global_position.distance_to(ball_carrier.global_position) < my_dist:
			return false
	return true


func _complete_tackle() -> void:
	contact_timer = 0.0
	_grace = 0.0
	if not GameState.can_tackle():
		return
	GameState.phase = GameState.Phase.RUCK   # lock immediately so no double tackles
	GameState.register_tackle()
