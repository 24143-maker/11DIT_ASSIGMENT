extends Node

signal tackle_made(tackle_number: int)
signal turnover()
signal try_scored(team: int)

var tackle_count: int = 0
var possession: int = 0       
var score: Array[int] = [0, 0]
var play_active: bool = true

func register_tackle() -> void:
	tackle_count += 1
	print("TACKLE ", tackle_count)
	tackle_made.emit(tackle_count)
	if tackle_count > 6:
		do_turnover()

func do_turnover() -> void:
	tackle_count = 0
	possession = 1 - possession
	turnover.emit()

func reset_set() -> void:
	tackle_count = 0
