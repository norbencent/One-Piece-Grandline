extends Node
## Registers gameplay input actions at startup (autoload: InputConfig).
## On Android the on-screen joystick/buttons (Phase 3) call Input.action_press/release with these
## same action names, so gameplay code reads one input API on every platform.
## Keyboard + gamepad bindings make desktop testing and controller play work too.

const DEADZONE := 0.25

const KEY_BINDINGS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE, KEY_K],
	"attack": [KEY_J],
	"dodge": [KEY_L, KEY_SHIFT],
	"block": [KEY_Q],
	"skill_1": [KEY_U],
	"skill_2": [KEY_I],
	"skill_3": [KEY_O],
	"ultimate": [KEY_R],
	"interact": [KEY_E],
	"pause": [KEY_P],
	"ui_back": [KEY_ESCAPE, KEY_BACKSPACE],
}

const JOY_BINDINGS := {
	"jump": JOY_BUTTON_A,
	"dodge": JOY_BUTTON_B,
	"attack": JOY_BUTTON_X,
	"interact": JOY_BUTTON_Y,
	"block": JOY_BUTTON_LEFT_SHOULDER,
	"ultimate": JOY_BUTTON_RIGHT_SHOULDER,
	"skill_1": JOY_BUTTON_DPAD_LEFT,
	"skill_2": JOY_BUTTON_DPAD_UP,
	"skill_3": JOY_BUTTON_DPAD_RIGHT,
	"pause": JOY_BUTTON_START,
	"ui_back": JOY_BUTTON_BACK,
}

const JOY_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}


func _ready() -> void:
	register_actions()


func register_actions() -> void:
	for action: String in KEY_BINDINGS:
		_ensure_action(action)
		for keycode: Key in KEY_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			_add_event(action, ev)
	for action: String in JOY_BINDINGS:
		_ensure_action(action)
		var jb := InputEventJoypadButton.new()
		jb.button_index = JOY_BINDINGS[action]
		_add_event(action, jb)
	for action: String in JOY_AXES:
		_ensure_action(action)
		var jm := InputEventJoypadMotion.new()
		jm.axis = JOY_AXES[action][0]
		jm.axis_value = JOY_AXES[action][1]
		_add_event(action, jm)


func all_actions() -> Array[String]:
	var out: Array[String] = []
	for action: String in KEY_BINDINGS:
		out.append(action)
	return out


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)


func _add_event(action: String, ev: InputEvent) -> void:
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)
