extends CharacterBody2D
class_name Player

@export var base_speed: float = 110.0
@export var sprint_multiplier: float = 1.4
@export var is_user_controlled: bool = true 

var facing: Vector2 = Vector2.RIGHT 

func _physics_process(_delta: float) -> void:
	if not is_user_controlled:
		return

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
	
	
const PASS_TOLERANCE: float = 4.0

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
		return  # no one there — do nothing, play a small "nope" sound

	# THE FORWARD PASS RULE
	if target.global_position.x > global_position.x + PASS_TOLERANCE:
		print("FORWARD PASS!")
		GameState.do_turnover()
		return

	var ball := get_tree().get_first_node_in_group("ball") as Ball
	ball.pass_to(global_position, target.global_position, self)
	# (In the full version, control transfers to `target` when they catch it)


func _find_receiver(direction: int) -> Node2D:
	var best: Node2D = null
	var best_dist: float = 200.0   # max pass range

	for mate in get_tree().get_nodes_in_group("attackers"):
		if mate == self:
			continue

		var offset: Vector2 = mate.global_position - global_position

		# Must be on the correct side
		if sign(offset.y) != direction:
			continue
		# Must not be in front (rugby league rule!)
		if offset.x > PASS_TOLERANCE:
			continue

		var d: float = offset.length()
		if d < best_dist:
			best_dist = d
			best = mate

	return best
	

	
	
