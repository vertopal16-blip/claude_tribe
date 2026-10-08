class_name InputSetup
extends RefCounted
## Registers the game's input actions at startup, so bindings live in code
## (easy to review / extend) and never depend on hand-edited project files.

const BINDINGS := {
	&"cam_forward": [KEY_W, KEY_UP],
	&"cam_back": [KEY_S, KEY_DOWN],
	&"cam_left": [KEY_A, KEY_LEFT],
	&"cam_right": [KEY_D, KEY_RIGHT],
	&"cam_rotate_left": [KEY_Q],
	&"cam_rotate_right": [KEY_E],
	&"toggle_pause": [KEY_SPACE, KEY_P],
	&"speed_1": [KEY_1],
	&"speed_2": [KEY_2],
	&"speed_3": [KEY_3],
	&"speed_4": [KEY_4],
	&"focus_home": [KEY_H, KEY_HOME],
	&"build_hut": [KEY_B],
	&"follow_selected": [KEY_F],
	&"cancel": [KEY_ESCAPE],
	&"toggle_debug": [KEY_F3],
}


static func register() -> void:
	for action: StringName in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
