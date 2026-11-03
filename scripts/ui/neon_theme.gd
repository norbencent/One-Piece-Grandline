class_name NeonTheme
extends RefCounted
## Builds the shared futuristic UI theme in code (dark navy, translucent black panels,
## neon blue + gold highlights, red accents). Applied to the root window by SceneManager.

const NAVY := Color("0a1020")
const PANEL_BG := Color(0.02, 0.03, 0.07, 0.84)
const NEON := Color("29d8ff")
const GOLD := Color("ffc847")
const RED := Color("ff3b5c")
const GOOD := Color("4dff9a")
const TEXT := Color("e6f4ff")
const TEXT_DIM := Color("8aa4c8")
const BASE_FONT_SIZE := 12


static func box(bg: Color, border: Color, border_w := 1, radius := 2, margin := 6.0,
		glow := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = false
	if glow > 0:
		sb.shadow_color = Color(border, 0.35)
		sb.shadow_size = glow
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = BASE_FONT_SIZE

	# Buttons — large padding keeps touch targets comfortable at 640x360.
	var btn_bg := Color(0.04, 0.08, 0.16, 0.92)
	t.set_stylebox("normal", "Button", box(btn_bg, NEON.darkened(0.45), 1, 2, 8))
	t.set_stylebox("hover", "Button", box(btn_bg.lightened(0.06), NEON, 1, 2, 8, 3))
	t.set_stylebox("pressed", "Button", box(Color(0.1, 0.07, 0.02, 0.95), GOLD, 1, 2, 8, 4))
	t.set_stylebox("disabled", "Button", box(Color(0.03, 0.04, 0.07, 0.7), Color(0.25, 0.3, 0.4), 1, 2, 8))
	var focus := box(Color(0, 0, 0, 0), GOLD, 1, 2, 8)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", NEON.lightened(0.35))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM.darkened(0.3))

	# Panels
	t.set_stylebox("panel", "PanelContainer", box(PANEL_BG, NEON.darkened(0.25), 1, 3, 10, 4))
	t.set_stylebox("panel", "Panel", box(PANEL_BG, NEON.darkened(0.25), 1, 3, 10, 4))

	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)

	# Progress bars (HP / EXP / energy reuse this with modulate or overrides)
	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.6), NEON.darkened(0.5), 1, 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(NEON, NEON.lightened(0.3), 0, 1, 0))
	t.set_color("font_color", "ProgressBar", TEXT)

	# Scrollbars — thicker grabbers for fingers.
	var grab := box(NEON.darkened(0.3), NEON, 0, 2, 3)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", box(NEON, NEON, 0, 2, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(GOLD, GOLD, 0, 2, 3))
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.4), Color(0, 0, 0, 0), 0, 2, 3))
	return t


## Title-style label settings with neon outline (used for headers / splash).
static func title_settings(size: int, color: Color, outline: Color) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = maxi(2, size / 10)
	ls.outline_color = outline
	ls.shadow_size = 0
	ls.shadow_color = Color(outline, 0.5)
	ls.shadow_offset = Vector2(0, 2)
	return ls
