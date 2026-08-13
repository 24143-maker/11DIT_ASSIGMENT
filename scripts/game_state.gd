extends Node
# AUTOLOAD as "GameState"
# Holds all match-wide state: score, tackle count, and what phase of play we're in.

signal tackle_made(tackle_number: int)
signal turnover()
signal try_scored(team: int)
signal score_changed()

enum Phase { OPEN_PLAY, RUCK, DEAD }

const TACKLES_PER_SET: int = 6

const GAME_TITLE: String = "RUGBY RIVALRY"
const HOME_NAME: String = "Hauraki Plains College"
const HOME_SHORT: String = "HPC"
const AWAY_NAME: String = "Pukekohe High School"
const AWAY_SHORT: String = "PHS"

var tackle_count: int = 0
var possession: int = 0          # 0 = player's team
var score: Array[int] = [0, 0]
var phase: Phase = Phase.OPEN_PLAY
var tackle_position: Vector2 = Vector2.ZERO   # where the ball is played from
var tackled_player: Node2D = null             # who actually got tackled

# Convenience: can defenders tackle right now?
func can_tackle() -> bool:
	return phase == Phase.OPEN_PLAY


func register_tackle() -> void:
	tackle_count += 1
	if tackle_count >= TACKLES_PER_SET:
		# Tackled on the last tackle -> hand the ball over
		do_turnover()
	else:
		tackle_made.emit(tackle_count)


func do_turnover() -> void:
	tackle_count = 0
	possession = 1 - possession
	phase = Phase.OPEN_PLAY
	turnover.emit()


func award_try(team: int) -> void:
	score[team] += 4
	tackle_count = 0
	phase = Phase.DEAD
	try_scored.emit(team)
	score_changed.emit()


func reset_set() -> void:
	tackle_count = 0
	phase = Phase.OPEN_PLAY
