extends CanvasLayer
# Builds the whole HUD in code. Only needs the two scoreboard PNGs.

const BOARD_TEX := "res://art/ui/scoreboard_bar.png"
const CLOCK_TEX := "res://art/ui/clock_panel.png"

# Where the scoreboard sits on screen
const BOARD_POS := Vector2(10, 8)
const BOARD_W := 168.0
const TACKLE_W := 34.0
const CLOCK_GAP := 3.0

# Team colours, used to tint the tackle cell for whoever is attacking
const HPC_COLOUR := Color(0.09, 0.09, 0.10)
const PHS_COLOUR := Color(0.49, 0.11, 0.20)

var board: TextureRect
var clock_panel: TextureRect

var home_score: Label
var away_score: Label
var half_label: Label
var clock_label: Label
var tackle_label: Label
var tackle_cell: ColorRect
var tackle_edge: ColorRect
var event_label: Label
var name_label: Label

var kick_bar: ProgressBar
var kick_bg: ColorRect
var kick_label: Label
var stam_bg: ColorRect
var stam_bar: ColorRect

var _event_timer: float = 0.0


func _ready() -> void:
	_build_scoreboard()

	event_label = _make_label(Vector2(200, 140), 34)
	event_label.visible = false

	name_label = _make_label(Vector2(16, 310), 16)

	stam_bg = ColorRect.new()
	stam_bg.position = Vector2(16, 330)
	stam_bg.size = Vector2(120, 12)
	stam_bg.color = Color(0, 0, 0, 0.55)
	add_child(stam_bg)

	stam_bar = ColorRect.new()
	stam_bar.position = Vector2(18, 332)
	stam_bar.size = Vector2(116, 8)
	stam_bar.color = Color(0.35, 0.85, 0.4, 0.95)
	add_child(stam_bar)

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


func _build_scoreboard() -> void:
	board = TextureRect.new()
	if ResourceLoader.exists(BOARD_TEX):
		board.texture = load(BOARD_TEX)
	board.position = BOARD_POS
	board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(board)

	clock_panel = TextureRect.new()
	if ResourceLoader.exists(CLOCK_TEX):
		clock_panel.texture = load(CLOCK_TEX)
	clock_panel.position = Vector2(BOARD_POS.x + BOARD_W + TACKLE_W + CLOCK_GAP * 2.0, BOARD_POS.y)
	clock_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(clock_panel)

	# Score numbers sit in the two dark boxes on the bar
	# Score boxes on the bar: x 60-83 and 84-107, y 1-26
	home_score = _make_board_label(Vector2(BOARD_POS.x + 60, BOARD_POS.y + 1), 14, 24, 26)
	away_score = _make_board_label(Vector2(BOARD_POS.x + 84, BOARD_POS.y + 1), 14, 24, 26)

	# Tackle cell — tinted with whichever team is attacking
	var tx: float = BOARD_POS.x + BOARD_W + CLOCK_GAP
	tackle_edge = ColorRect.new()
	tackle_edge.position = Vector2(tx, BOARD_POS.y)
	tackle_edge.size = Vector2(TACKLE_W, 28)
	tackle_edge.color = Color(0.31, 0.31, 0.34)
	add_child(tackle_edge)

	tackle_cell = ColorRect.new()
	tackle_cell.position = Vector2(tx, BOARD_POS.y + 1)
	tackle_cell.size = Vector2(TACKLE_W, 26)
	tackle_cell.color = HPC_COLOUR
	add_child(tackle_cell)

	tackle_label = _make_board_label(Vector2(tx, BOARD_POS.y + 1), 13, TACKLE_W, 26)

	# Half + time inside the clock panel
	# Clock panel is 68 wide. Header strip y 1-10, time area y 12-27.
	# Font sizes are kept under the box height so the two never collide.
	var cx: float = BOARD_POS.x + BOARD_W + TACKLE_W + CLOCK_GAP * 2.0
	half_label = _make_board_label(Vector2(cx + 1, BOARD_POS.y - 5), 7, 66, 10)
	half_label.clip_text = true
	clock_label = _make_board_label(Vector2(cx + 1, BOARD_POS.y + 8.5), 12, 66, 16)
	clock_label.clip_text = true


func _make_board_label(pos: Vector2, size: int, width: float, height: float = 26.0) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, height)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	add_child(l)
	return l


func _make_label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func _process(delta: float) -> void:
	_update_stamina()
	if _event_timer > 0.0:
		_event_timer -= delta
		if _event_timer <= 0.0:
			event_label.visible = false


func _refresh() -> void:
	home_score.text = str(GameState.score[0])
	away_score.text = str(GameState.score[1])
	# 1ST, 2ND, 3RD ... for the current tackle in the set
	var n: int = clamp(GameState.tackle_count + 1, 1, GameState.TACKLES_PER_SET)
	tackle_label.text = _ordinal(n)

	# The cell takes the attacking team's colour
	if tackle_cell:
		tackle_cell.color = HPC_COLOUR if GameState.possession == 0 else PHS_COLOUR
		tackle_label.add_theme_color_override(
			"font_color",
			Color(0.93, 0.94, 0.96) if GameState.possession == 0 else Color(0.99, 0.74, 0.23)
		)


func _ordinal(n: int) -> String:
	match n:
		1: return "1ST"
		2: return "2ND"
		3: return "3RD"
		_: return str(n) + "TH"


func _on_clock_updated(seconds: float, half: int) -> void:
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	clock_label.text = "%d:%02d" % [m, s]
	half_label.text = "1ST HALF" if half == 1 else "2ND HALF"


func show_event(text: String) -> void:
	event_label.text = text
	event_label.visible = true
	_event_timer = 1.4
	_refresh()


func _update_stamina() -> void:
	if stam_bar == null:
		return
	for a in get_tree().get_nodes_in_group("attackers"):
		if a.is_user_controlled:
			if name_label:
				name_label.text = a.player_name
				name_label.visible = true
			var pct: float = clamp(a.stamina / a.stamina_max, 0.0, 1.0)
			stam_bar.size.x = 116.0 * pct
			stam_bg.visible = true
			stam_bar.visible = true
			if pct > 0.5:
				stam_bar.color = Color(0.35, 0.85, 0.4, 0.95)
			elif pct > 0.2:
				stam_bar.color = Color(0.95, 0.75, 0.25, 0.95)
			else:
				stam_bar.color = Color(0.9, 0.3, 0.25, 0.95)
			return
	if name_label:
		name_label.visible = false
	stam_bg.visible = false
	stam_bar.visible = false


func _set_kick_visible(v: bool) -> void:
	kick_bar.visible = v
	kick_bg.visible = v
	kick_label.visible = v


func _on_kick_state_changed(charging: bool, charge: float, kick_type: String) -> void:
	_set_kick_visible(charging)
	if charging:
		kick_bar.value = charge * 100.0
		kick_label.text = kick_type.to_upper()
