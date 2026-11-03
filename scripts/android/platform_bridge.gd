extends Node
## Android / platform lifecycle glue (autoload: Platform).
## - Android back button (and Esc on desktop) routes through a back-handler stack:
##   the top-most screen/popup handles it; with nothing registered the app exits.
## - Autosaves when the app is backgrounded, loses focus or is closed.
## - Keeps the screen awake during play.

var _back_handlers: Array[Callable] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.screen_set_keep_on(true)


func is_android() -> bool:
	return OS.has_feature("android")


func is_mobile() -> bool:
	return OS.has_feature("mobile")


## Screens/popups push a handler when shown and pop it when hidden or freed.
func push_back_handler(handler: Callable) -> void:
	if not _back_handlers.has(handler):
		_back_handlers.append(handler)


func pop_back_handler(handler: Callable) -> void:
	_back_handlers.erase(handler)


func back_handler_count() -> int:
	return _back_handlers.size()


func handle_back() -> void:
	EventBus.back_requested.emit()
	while not _back_handlers.is_empty():
		var handler: Callable = _back_handlers.back()
		if handler.is_valid():
			handler.call()
			return
		_back_handlers.pop_back() # owner was freed without popping
	quit_game()


func quit_game() -> void:
	GameManager.autosave()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back"):
		get_viewport().set_input_as_handled()
		handle_back()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			handle_back()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			GameManager.autosave()
