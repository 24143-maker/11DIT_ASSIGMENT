extends Node2D
class_name Field

const METRE: float = 8.0         
const FIELD_LEFT: float = 48.0    
const FIELD_RIGHT: float = 848.0  
const FIELD_TOP: float = 0.0
const FIELD_BOTTOM: float = 544.0
const INGOAL_DEPTH: float = 48.0  

static func metres_to_pixels(m: float) -> float:
	return m * METRE

static func metres_out(pos: Vector2) -> float:
	return (FIELD_RIGHT - pos.x) / METRE
