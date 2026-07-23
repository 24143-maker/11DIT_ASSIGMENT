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
		
	

	
	
