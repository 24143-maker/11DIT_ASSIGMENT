extends Node2D

@onready var player: Player = $Player

const RETREAT_METRES: float = 10.0

func _ready() -> void:
	# Listen for game events from GameState
	GameState.tackle_made.connect(_on_tackle_made)
	GameState.turnover.connect(_on_turnover)

	# Listen for catches from the ball
	var ball := get_tree().get_first_node_in_group("ball") as Ball
	if ball:
		ball.caught.connect(_on_ball_caught)

	_assign_carrier()


func _assign_carrier() -> void:
	# Tell every teammate and defender who is currently carrying the ball
	for mate in get_tree().get_nodes_in_group("attackers"):
		if mate is Teammate:
			mate.ball_carrier = player
	for d in get_tree().get_nodes_in_group("defenders"):
		d.ball_carrier = player


func _on_tackle_made(tackle_number: int) -> void:
	_play_the_ball(tackle_number)


func _play_the_ball(tackle_number: int) -> void:
	print("TACKLE ", tackle_number)

	# 1. Freeze the current carrier
	player.is_user_controlled = false
	player.velocity = Vector2.ZERO

	# 2. Defence retreats 10 metres from where the tackle happened
	var new_line_x: float = player.global_position.x + Field.metres_to_pixels(RETREAT_METRES)
	for d in get_tree().get_nodes_in_group("defenders"):
		d.line_x = new_line_x
		d.state = Defender.State.RETREAT

	# 3. Wait for the play-the-ball
	await get_tree().create_timer(0.8).timeout

	# 4. Hand control back and re-open play
	player.is_user_controlled = true
	GameState.play_active = true


func _on_turnover() -> void:
	print("HANDOVER!")
	# For now just reset to halfway. You'll expand this in Step 15.
	player.global_position = Vector2(448, 272)
	player.is_user_controlled = true
	GameState.play_active = true

	for d in get_tree().get_nodes_in_group("defenders"):
		d.line_x = player.global_position.x + Field.metres_to_pixels(RETREAT_METRES)
		d.state = Defender.State.RETREAT


func _on_ball_caught(new_carrier: Node2D) -> void:
	# Old carrier stops being controlled
	player.is_user_controlled = false

	# The catcher becomes the new player-controlled carrier
	player = new_carrier
	if "is_user_controlled" in player:
		player.is_user_controlled = true

	# Everyone re-marks / re-supports the new carrier
	_assign_carrier()
