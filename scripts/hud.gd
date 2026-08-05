extends CanvasLayer

var kick_bar: ProgressBar
var kick_bg: ColorRect
var kick_label: Label

func _ready() -> void:
	# Build the kick label
	kick_label = Label.new()
	kick_label.position = Vector2(270, 300)
	kick_label.add_theme_font_size_override("font_size", 20)
	kick_label.add_theme_color_override("font_color", Color.WHITE)
	kick_label.text = ""
	add_child(kick_label)

	# Build a dark background behind the bar so it's easy to see
	kick_bg = ColorRect.new()
	kick_bg.position = Vector2(270, 328)
	kick_bg.size = Vector2(200, 24)
	kick_bg.color = Color(0, 0, 0, 0.6)
	add_child(kick_bg)

	# Build the progress bar
	kick_bar = ProgressBar.new()
	kick_bar.position = Vector2(272, 330)
	kick_bar.size = Vector2(196, 20)
	kick_bar.min_value = 0.0
	kick_bar.max_value = 100.0
	kick_bar.value = 0.0
	kick_bar.show_percentage = false
	add_child(kick_bar)

	_set_visible(false)

	# Connect to every attacker's kick signal
	await get_tree().process_frame
	var count := 0
	for a in get_tree().get_nodes_in_group("attackers"):
		if a.has_signal("kick_state_changed"):
			a.kick_state_changed.connect(_on_kick_state_changed)
			count += 1
	print("HUD connected to ", count, " attackers")


func _set_visible(v: bool) -> void:
	kick_bar.visible = v
	kick_bg.visible = v
	kick_label.visible = v


func _on_kick_state_changed(charging: bool, charge: float, kick_type: String) -> void:
	_set_visible(charging)
	if charging:
		kick_bar.value = charge * 100.0
		kick_label.text = kick_type.to_upper()
