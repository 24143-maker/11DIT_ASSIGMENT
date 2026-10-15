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
var event_band: ColorRect
var event_edge_top: ColorRect
var event_edge_bot: ColorRect
var event_sub: Label
var _event_tween: Tween
var name_label: Label

var kick_bar: ProgressBar
var kick_bg: ColorRect
var kick_label: Label
var stam_bg: ColorRect
var stam_bar: ColorRect


# Narrated opposition set
var story_bg: ColorRect
var story_panel: ColorRect
var story_text: Label
var story_hint: Label
var story_active: bool = false
signal story_advance()


func _ready() -> void:
	_build_scoreboard()

	_build_event_banner()

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

	_build_story_panel()
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


func _build_story_panel() -> void:
	# A slim banner along the bottom, so the field stays visible
	story_panel = ColorRect.new()
	story_panel.position = Vector2(20, 246)
	story_panel.size = Vector2(600, 100)
	story_panel.color = Color(0.06, 0.06, 0.08, 0.9)
	add_child(story_panel)

	story_bg = ColorRect.new()
	story_bg.position = Vector2(20, 246)
	story_bg.size = Vector2(600, 3)
	story_bg.color = Color(0.85, 0.2, 0.18, 0.95)
	add_child(story_bg)

	story_text = Label.new()
	story_text.position = Vector2(36, 258)
	story_text.size = Vector2(568, 62)
	story_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	story_text.add_theme_font_size_override("font_size", 24)
	story_text.add_theme_color_override("font_color", Color.WHITE)
	add_child(story_text)

	story_hint = Label.new()
	story_hint.position = Vector2(36, 322)
	story_hint.size = Vector2(568, 18)
	story_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story_hint.add_theme_font_size_override("font_size", 13)
	story_hint.add_theme_color_override("font_color", Color(0.72, 0.75, 0.78))
	add_child(story_hint)

	_show_story(false)


func _show_story(v: bool) -> void:
	story_bg.visible = v
	story_panel.visible = v
	story_text.visible = v
	story_hint.visible = v


func show_beat(text: String, n: int, total: int) -> void:
	story_active = true
	_show_story(true)
	story_text.text = text
	story_hint.text = "SPACE TO CONTINUE   (%d / %d)" % [n, total]


func hide_beat() -> void:
	story_active = false
	_show_story(false)


func _unhandled_input(event: InputEvent) -> void:
	if not story_active:
		return
	var go: bool = false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			go = true
	elif event is InputEventMouseButton and event.pressed:
		go = true
	if go:
		story_advance.emit()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_update_stamina()


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


# ---------- EVENT BANNER ----------
# A broadcast-style band across the middle: dark strip, coloured accent edges
# that change with the kind of event, big outlined text, and a wipe-in.

const BANNER_Y: float = 130.0
const BANNER_H: float = 64.0

func _build_event_banner() -> void:
	event_band = ColorRect.new()
	event_band.position = Vector2(0, BANNER_Y)
	event_band.size = Vector2(640, BANNER_H)
	event_band.color = Color(0.04, 0.04, 0.06, 0.86)
	event_band.pivot_offset = Vector2(320, BANNER_H * 0.5)
	add_child(event_band)

	event_edge_top = ColorRect.new()
	event_edge_top.position = Vector2(0, BANNER_Y)
	event_edge_top.size = Vector2(640, 3)
	event_edge_top.pivot_offset = Vector2(320, 1.5)
	add_child(event_edge_top)

	event_edge_bot = ColorRect.new()
	event_edge_bot.position = Vector2(0, BANNER_Y + BANNER_H - 3.0)
	event_edge_bot.size = Vector2(640, 3)
	event_edge_bot.pivot_offset = Vector2(320, 1.5)
	add_child(event_edge_bot)

	event_label = Label.new()
	event_label.position = Vector2(0, BANNER_Y + 8.0)
	event_label.size = Vector2(640, 34)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	event_label.pivot_offset = Vector2(320, 17)
	event_label.add_theme_font_size_override("font_size", 30)
	event_label.add_theme_color_override("font_color", Color.WHITE)
	event_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	event_label.add_theme_constant_override("outline_size", 7)
	add_child(event_label)

	event_sub = Label.new()
	event_sub.position = Vector2(0, BANNER_Y + 42.0)
	event_sub.size = Vector2(640, 16)
	event_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	event_sub.add_theme_font_size_override("font_size", 11)
	event_sub.add_theme_color_override("font_color", Color(0.72, 0.75, 0.80))
	add_child(event_sub)

	_show_event_banner(false)


func _show_event_banner(v: bool) -> void:
	event_band.visible = v
	event_edge_top.visible = v
	event_edge_bot.visible = v
	event_label.visible = v
	event_sub.visible = v


# Accent colour and a short context line, chosen from the event wording
func _event_style(text: String) -> Array:
	var t: String = text.to_upper()
	if t.find("TRY") >= 0 or t.find("SCORE") >= 0:
		var who: String = GameState.AWAY_NAME if t.find("THEY") >= 0 else GameState.HOME_NAME
		return [Color(0.20, 0.80, 0.36), who.to_upper()]
	if t.find("HANDOVER") >= 0 or t.find("TURNOVER") >= 0 or t.find("KNOCK") >= 0:
		return [Color(0.90, 0.26, 0.22), "POSSESSION CHANGES"]
	if t.find("KICK OFF") >= 0:
		return [Color(0.26, 0.60, 0.94), "%s  v  %s" % [GameState.HOME_SHORT, GameState.AWAY_SHORT]]
	if t.find("KICK") >= 0:
		return [Color(0.26, 0.60, 0.94), ""]
	if t.find("HALF") >= 0 or t.find("FULL TIME") >= 0:
		return [Color(0.96, 0.76, 0.22),
				"%s %d   -   %s %d" % [GameState.HOME_SHORT, GameState.score[0],
									   GameState.AWAY_SHORT, GameState.score[1]]]
	if t.find("TACKLE") >= 0:
		var n: int = clamp(GameState.tackle_count, 0, GameState.TACKLES_PER_SET)
		var dots: String = ""
		for i in range(GameState.TACKLES_PER_SET):
			dots += "O" if i < n else "-"
		var accent := Color(0.78, 0.80, 0.84)
		if n >= GameState.TACKLES_PER_SET - 1:
			accent = Color(0.96, 0.55, 0.18)      # last tackle runs hot
		return [accent, dots]
	return [Color(0.78, 0.80, 0.84), ""]


func show_event(text: String) -> void:
	var style: Array = _event_style(text)
	var accent: Color = style[0]
	var sub: String = String(style[1])

	event_label.text = text.to_upper()
	event_sub.text = sub
	event_sub.visible = sub != ""
	event_edge_top.color = accent
	event_edge_bot.color = accent
	event_label.add_theme_color_override("font_color", accent.lightened(0.55))

	_show_event_banner(true)
	event_sub.visible = sub != ""

	if _event_tween and _event_tween.is_valid():
		_event_tween.kill()

	# start state
	event_band.scale = Vector2(0.0, 1.0)
	event_edge_top.scale = Vector2(0.0, 1.0)
	event_edge_bot.scale = Vector2(0.0, 1.0)
	event_label.scale = Vector2(1.25, 1.25)
	event_label.modulate.a = 0.0
	event_sub.modulate.a = 0.0

	_event_tween = create_tween()
	_event_tween.set_parallel(true)
	# band wipes open from the centre
	_event_tween.tween_property(event_band, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_event_tween.tween_property(event_edge_top, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_event_tween.tween_property(event_edge_bot, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# text settles in
	_event_tween.tween_property(event_label, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.06)
	_event_tween.tween_property(event_label, "modulate:a", 1.0, 0.16).set_delay(0.06)
	_event_tween.tween_property(event_sub, "modulate:a", 1.0, 0.18).set_delay(0.16)

	# hold, then fade the whole thing out
	_event_tween.set_parallel(false)
	_event_tween.tween_interval(1.15)
	_event_tween.set_parallel(true)
	_event_tween.tween_property(event_label, "modulate:a", 0.0, 0.28)
	_event_tween.tween_property(event_sub, "modulate:a", 0.0, 0.28)
	_event_tween.tween_property(event_band, "scale", Vector2(1.0, 0.0), 0.28) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_event_tween.tween_property(event_edge_top, "scale", Vector2(0.0, 1.0), 0.28)
	_event_tween.tween_property(event_edge_bot, "scale", Vector2(0.0, 1.0), 0.28)
	_event_tween.set_parallel(false)
	_event_tween.tween_callback(func(): _show_event_banner(false))

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
