extends Node2D

@onready var player: Player = $Player

const RETREAT_METRES: float = 10.0

var current_carrier: Node2D = null   # who holds the ball right now

func _ready() -> void:
	GameState.tackle_made.connect(_on_tackle_made)
	GameState.turnover.connect(_on_turnover)

	var ball: Ball = _get_ball()
	if ball:
		ball.caught.connect(_on_ball_caught)

	_assign_carrier(player)

	# Give the ball to the player at kickoff
	await get_tree().process_frame
	_give_ball_to(player)


func _get_ball() -> Ball:
	for n in get_tree().get_nodes_in_group("ball"):
		if n is Ball:
			return n
	return null


func _give_ball_to(who: Node2D) -> void:
	var ball: Ball = _get_ball()
	if ball == null:
		return
	ball.carrier = who
	ball.in_flight = false
	ball.global_position = who.global_position
	current_carrier = who

	# Make sure the human controls the carrier and no one else
	_set_control(who)
	_assign_carrier(who)


func _set_control(who: Node2D) -> void:
	# Turn off control on everyone, then turn it on for the carrier
	for a in get_tree().get_nodes_in_group("attackers"):
		if "is_user_controlled" in a:
			a.is_user_controlled = (a == who)


func _assign_carrier(who: Node2D) -> void:
	for mate in get_tree().get_nodes_in_group("attackers"):
		if mate is Teammate:
			mate.ball_carrier = who
	for d in get_tree().get_nodes_in_group("defenders"):
		d.ball_carrier = who


func _on_tackle_made(tackle_number: int) -> void:
	_play_the_ball(tackle_number)


func _play_the_ball(tackle_number: int) -> void:
	print("TACKLE ", tackle_number)

	if current_carrier and "is_user_controlled" in current_carrier:
		current_carrier.is_user_controlled = false
		current_carrier.velocity = Vector2.ZERO

	var carrier_x: float = current_carrier.global_position.x if current_carrier else 448.0
	var new_line_x: float = carrier_x + Field.metres_to_pixels(RETREAT_METRES)
	for d in get_tree().get_nodes_in_group("defenders"):
		d.line_x = new_line_x
		d.state = Defender.State.RETREAT

	await get_tree().create_timer(0.8).timeout

	if current_carrier and "is_user_controlled" in current_carrier:
		current_carrier.is_user_controlled = true
	GameState.play_active = true


func _on_turnover() -> void:
	print("HANDOVER!")
	if current_carrier:
		current_carrier.global_position = Vector2(448, 272)
	_give_ball_to(player)
	GameState.play_active = true

	for d in get_tree().get_nodes_in_group("defenders"):
		d.line_x = 448.0 + Field.metres_to_pixels(RETREAT_METRES)
		d.state = Defender.State.RETREAT


func _on_ball_caught(new_carrier: Node2D) -> void:
	# The catcher becomes the controlled carrier
	current_carrier = new_carrier
	_set_control(new_carrier)
	_assign_carrier(new_carrier)
