extends Node
## Semantic input shared by keyboard, gamepad, and independently tracked fingers.

signal pause_requested
const LEFT := 1
const RIGHT := 2
const UP := 4
const DOWN := 8
const JUMP := 16
const RUN := 32
const SPECIAL := 64
var touch_actions: Dictionary = {}
var key_actions: Dictionary = {}
var joy_buttons := {"jump": JOY_BUTTON_A, "run": JOY_BUTTON_B, "special": JOY_BUTTON_X}
var alternate := false
var enabled := false
var pause_enabled := false

func set_touch(finger: int, action: int) -> void:
	if action == 0:
		touch_actions.erase(finger)
	else:
		touch_actions[finger] = action

func release_all() -> void:
	touch_actions.clear()
	key_actions.clear()

func _input(event: InputEvent) -> void:
	if pause_enabled:
		if (event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START and event.pressed):
			pause_requested.emit()
			return
	if not enabled:
		return
	if event is InputEventKey and not event.echo:
		var mapping = {KEY_LEFT: LEFT, KEY_RIGHT: RIGHT, KEY_UP: UP, KEY_DOWN: DOWN, KEY_Z: JUMP, KEY_X: RUN, KEY_C: SPECIAL, KEY_SPACE: JUMP}
		if alternate:
			mapping[KEY_Z] = RUN
			mapping[KEY_X] = SPECIAL
			mapping[KEY_C] = JUMP
		if mapping.has(event.keycode):
			if event.pressed:
				key_actions[event.keycode] = mapping[event.keycode]
			else:
				key_actions.erase(event.keycode)

func mask() -> int:
	var result := 0
	for action in touch_actions.values():
		result |= int(action)
	for action in key_actions.values():
		result |= int(action)
	if not enabled:
		return result
	for device in Input.get_connected_joypads():
		var axis_x = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		var axis_y = Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
		if axis_x < -0.35 or Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT): result |= LEFT
		if axis_x > 0.35 or Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT): result |= RIGHT
		if axis_y < -0.35 or Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP): result |= UP
		if axis_y > 0.35 or Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN): result |= DOWN
		if Input.is_joy_button_pressed(device, int(joy_buttons.jump)): result |= JUMP
		if Input.is_joy_button_pressed(device, int(joy_buttons.run)): result |= RUN
		if Input.is_joy_button_pressed(device, int(joy_buttons.special)): result |= SPECIAL
	return result
