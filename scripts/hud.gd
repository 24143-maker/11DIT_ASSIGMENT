extends CanvasLayer
# Builds the whole HUD in code — no child nodes needed in the editor.

var score_label: Label
var clock_label: Label
var tackle_label: Label
var event_label: Label
var kick_bar: ProgressBar
var kick_bg: ColorRect
var kick_label: Label

var _event_timer: float = 0.0


func _ready() -> void:
	score_label = _make_label(Vector2(16, 10), 18)
	clock_label = _make_label(Vector2(280, 10), 18)
	tackle_label = _make_label(Vector2(16, 34), 16)

	event_label = _make_label(Vector2(200, 140), 34)
	event_label.visible = false

	kick_bg = ColorRect.new()
	kick_bg.position = Vector2(220, 320)
	kick_bg.size = Vector2(200, 22)
	kick_bg.color = Color(0, 0, 0, 0.55)
	add_child(kick_bg)

	kick_bar = ProgressBar.new()
	kick_bar.position = Vector2(222, 322)
	kick_bar.size = Vector2(196, 18)
	kick_bar.min_value = 0.0
	kick_bar.max_value = 100.0
	kick_bar.show_percentage = false
	add_child(kick_bar)

	kick_label = _make_label(Vector2(220, 296), 16)

	_set_kick_visible(false)
	_refresh()

	await get_tree().process_frame

	for a in get_tree().get_nodes_in_group("attackers"):
		if a.has_signal("kick_state_changed"):
			a.kick_state_changed.connect(_on_kick_state_changed)

	GameState.tackle_made.connect(func(_n): _refresh())
	GameState.score_changed.connect(_refresh)
	GameState.turnover.connect(_refresh)

	var m := get_parent()
	if m.has_signal("event_message"):
		m.event_message.connect(show_event)
	if m.has_signal("clock_updated"):
		m.clock_updated.connect(_on_clock_updated)


func _process(delta: float) -> void:
	if _event_timer > 0.0:
		_event_timer -= delta
		if _event_timer <= 0.0:
			event_label.visible = false


func _make_label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func _refresh() -> void:
	score_label.text = "HOME %d   AWAY %d" % [GameState.score[0], GameState.score[1]]
	var dots := ""
	for i in range(GameState.TACKLES_PER_SET):
		dots += "O" if i < GameState.tackle_count else "-"
	tackle_label.text = "TACKLE " + dots


func _on_clock_updated(seconds: float, half: int) -> void:
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	clock_label.text = "H%d  %d:%02d" % [half, m, s]


func show_event(text: String) -> void:
	event_label.text = text
	event_label.visible = true
	_event_timer = 1.4
	_refresh()


func _set_kick_visible(v: bool) -> void:
	kick_bar.visible = v
	kick_bg.visible = v
	kick_label.visible = v


func _on_kick_state_changed(charging: bool, charge: float, kick_type: String) -> void:
	_set_kick_visible(charging)
	if charging:
		kick_bar.value = charge * 100.0
		kick_label.text = kick_type.to_upper()
