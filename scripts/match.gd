extends Node2D

@onready var player: Player = $Player

func _ready() -> void:
	for mate in get_tree().get_nodes_in_group("attackers"):
		if mate is Teammate:
			mate.ball_carrier = player
