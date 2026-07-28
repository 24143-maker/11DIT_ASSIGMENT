extends CharacterBody2D
class_name Teammate

@export var base_speed: float = 105.0
@export var support_offset: Vector2 = Vector2(-40, -60)  

var ball_carrier: Node2D = null

func _physics_process(_delta: float) -> void:
	if ball_carrier == null:
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
