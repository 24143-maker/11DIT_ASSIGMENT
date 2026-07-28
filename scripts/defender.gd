extends CharacterBody2D
class_name Defender

enum State { LINE, CHASE, RETREAT }

@export var base_speed: float = 100.0
@export var tackle_stat: int = 55
@export var reaction_delay: float = 0.2 

var state: State = State.LINE
var slot_y: float = 100.0
var line_x: float = 500.0
var ball_carrier: Node2D = null
var _react_timer: float = 0.0

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
		
		
	if global_position.distance_to(ball_carrier.global_position) < 90.0:
		_react_timer += delta 
		if _react_timer >= reaction_delay:
			state = State.CHASE
			_react_timer = 0.0
			
	velocity = (target - global_position).limit_length(base_speed)

func _do_chase(_delta: float) -> void:
	if ball_carrier == null:
		state = State.LINE
		return
	
	var lead: Vector2 = ball_carrier.velocity * 0.25
	var target: Vector2 = ball_carrier.global_position + lead 
	velocity = (target - global_position).normalized() * base_speed
	
func _do_retreat(_delta: float) -> void:
	var target := Vector2(line_x, slot_y)
	velocity = (target - global_position).limit_length(base_speed * 1.5)
	if global_position.distance_to(target) < 10.0:
		state = State.LINE
	
