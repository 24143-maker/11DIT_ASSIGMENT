extends CharacterBody2D
class_name Defender

enum State { LINE, CHASE, RETREAT }

@export var base_speed: float = 100.0
@export var tackle_stat: int = 55
@export var reaction_delay: float = 0.2
@export var tackle_radius: float = 20.0
@export var chase_distance: float = 90.0
@export var debug: bool = true          # set false once it all works

var state: State = State.LINE
var slot_y: float = 100.0
var line_x: float = 500.0
var ball_carrier: Node2D = null
var _react_timer: float = 0.0

func _ready() -> void:
	if debug:
		print(name, " ready. carrier = ", ball_carrier)

func _physics_process(delta: float) -> void:
	match state:
		State.LINE:    _do_line(delta)
		State.CHASE:   _do_chase(delta)
		State.RETREAT: _do_retreat(delta)
	move_and_slide()

func _do_line(delta: float) -> void:
	var target := Vector2(line_x, slot_y)
	if ball_carrier:
		target.y = lerp(slot_y, ball_carrier.global_position.y, 0.4)

		var d: float = global_position.distance_to(ball_carrier.global_position)
		if d < chase_distance:
			_react_timer += delta
			if _react_timer >= reaction_delay:
				state = State.CHASE
				_react_timer = 0.0
				if debug:
					print(name, " -> CHASE (dist ", int(d), ")")

	velocity = (target - global_position).limit_length(base_speed)

func _do_chase(_delta: float) -> void:
	if ball_carrier == null:
		state = State.LINE
		return

	var dist: float = global_position.distance_to(ball_carrier.global_position)

	if dist < tackle_radius and GameState.play_active:
		_attempt_tackle()
		return

	var lead: Vector2 = ball_carrier.velocity * 0.25
	velocity = (ball_carrier.global_position + lead - global_position).normalized() * base_speed

func _do_retreat(_delta: float) -> void:
	var target := Vector2(line_x, slot_y)
	velocity = (target - global_position).limit_length(base_speed * 1.5)
	if global_position.distance_to(target) < 10.0:
		state = State.LINE

func _attempt_tackle() -> void:
	if debug:
		print(name, " attempting tackle")

	var carrier_strength: int = 50
	if "strength_stat" in ball_carrier:
		carrier_strength = ball_carrier.strength_stat

	var roll: int = randi_range(0, 40)
	if debug:
		print("    ", tackle_stat, " + ", roll, " vs ", carrier_strength)

	# threshold lowered from the blueprint so tackles land reliably while testing
	if tackle_stat + roll > carrier_strength:
		if debug:
			print("    TACKLE MADE")
		GameState.play_active = false
		GameState.register_tackle()
	else:
		if debug:
			print("    broken tackle")
		state = State.RETREAT
		await get_tree().create_timer(0.5).timeout
		state = State.LINE
