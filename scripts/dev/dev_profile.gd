class_name DevProfile
extends RefCounted
## Debug builds: a test profile, so testing never touches the real save or settings.
##   godot . -- --profile=test                 saves and settings in user://profiles/test/
##   godot . -- --profile=test --from=pile_full  starts from tests/saves/pile_full.json
##   godot . -- --from=new                     a brand new game (implies --profile=test)
## A profile run is also kept out of your way: its window is parked off-screen and the pet never
## goes out onto the desktop (see home.gd). Release builds always use the real paths.

const FIXTURES := "res://tests/saves/"

static var _prepared := false


## The profile's name, or "" for the real game.
static func profile_name() -> String:
	var n := DevArgs.value("profile")
	if n == "" and DevArgs.value("from") != "":
		n = "test"  # starting from a fixture never touches the real save
	return n.validate_filename()


## Whether this is a test run (a profile).
static func active() -> bool:
	return profile_name() != ""


## Where a save-like file lives: user://<file>, or inside the profile's folder.
static func path(file: String) -> String:
	if not active():
		return "user://" + file
	_prepare()
	return "user://profiles/%s/%s" % [profile_name(), file]


## The profile's folder on disk (for screenshots and logs).
static func folder() -> String:
	return ProjectSettings.globalize_path("user://profiles/%s/" % profile_name()) if active() else ProjectSettings.globalize_path("user://")


## Makes the folder, then puts the fixture from --from in place of the profile's save ("new":
## no save at all, so a fresh game starts). Runs once, before anything loads.
static func _prepare() -> void:
	if _prepared:
		return
	_prepared = true
	var dir := "user://profiles/%s/" % profile_name()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var from := DevArgs.value("from")
	if from == "":
		return
	for f in ["save.json", "save.json.bak", "save.json.tmp"]:
		if FileAccess.file_exists(dir + f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + f))
	if from == "new":
		return
	var fixture := FIXTURES + from + ".json"
	if not FileAccess.file_exists(fixture):
		push_error("no such test save: %s" % fixture)
		return
	var out := FileAccess.open(dir + "save.json", FileAccess.WRITE)
	out.store_string(FileAccess.get_file_as_string(fixture))
	out.close()
