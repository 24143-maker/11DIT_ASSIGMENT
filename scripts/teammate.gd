extends CharacterBody2D
class_name Teammate

@export var base_speed: float = 105.0
@export var support_offset: Vector2 = Vector2(-40, -60)
@export var is_user_controlled: bool = false

var ball_carrier: Node2D = null
var facing: Vector2 = Vector2.RIGHT

const PASS_TOLERANCE: float = 4.0

func _ready() -> void:
	add_to_group("attackers")

func _physics_process(_delta: float) -> void:
	if is_user_controlled:
		_do_user_control()
	else:
		_do_support()

# When this teammate has caught the ball, the human controls them
func _do_user_control() -> void:
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	var speed: float = base_speed
	if Input.is_action_pressed("sprint"):
		speed *= 1.4
	velocity = input_dir * speed
	move_and_slide()
	if input_dir.length() > 0.1:
		facing = input_dir.normalized()

# When not carrying, run in a support shape behind the carrier
func _do_support() -> void:
	if ball_carrier == null:
		velocity = Vector2.ZERO
		return

	var target: Vector2 = ball_carrier.global_position + support_offset
	target.x = clamp(target.x, Field.FIELD_LEFT, Field.FIELD_RIGHT)
	target.y = clamp(target.y, 16.0, Field.FIELD_BOTTOM - 16.0)

	var to_target: Vector2 = target - global_position
	if to_target.length() > 6.0:
		velocity = to_target.normalized() * base_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()


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

	var ball: Ball = null
	for n in get_tree().get_nodes_in_group("ball"):
		if n is Ball:
			ball = n
			break
	if ball == null:
		return
	if ball.carrier != self:
		return

	print("passing to ", target.name)
	ball.pass_to(global_position, target.global_position, self, target)


func _find_receiver(direction: int) -> Node2D:
	var best: Node2D = null
	var best_dist: float = 200.0
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
