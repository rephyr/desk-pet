class_name DevArgs
extends RefCounted
## Debug-build launch flags for testing screens quickly, passed after "--":
##   godot . -- --expanded --tab=collection --book --open=starter:10
##   godot . -- --expanded --open=starter:1 --force=mythic   (test a reveal at a given rarity)
## Release builds ignore them.


static var overrides := {}  # key -> value, set by a headless script before anything loads (tests)


static func has(flag: String) -> bool:
	return OS.is_debug_build() and ("--" + flag) in OS.get_cmdline_user_args()


static func value(key: String, fallback := "") -> String:
	if not OS.is_debug_build():
		return fallback
	if overrides.has(key):
		return str(overrides[key])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.split("=", true, 1)[1]
	return fallback
