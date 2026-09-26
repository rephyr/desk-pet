class_name SaveFile
extends RefCounted
## Crash-safe JSON save files. Writes go to a temp file that then replaces the real one, and the
## previous save is kept as a backup, so a crash mid-write can never leave you with nothing.


## Writes `data` to `path`. Returns false if it couldn't.
static func write(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("can't write save: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, _backup(path))
	return DirAccess.rename_absolute(tmp, path) == OK


## Reads the save, falling back to the backup. A file that can't be read is renamed aside
## (never deleted) so nothing gets overwritten. Returns {} when there is no usable save.
static func read(path: String) -> Dictionary:
	for candidate in [path, _backup(path)]:
		if not FileAccess.file_exists(candidate):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if typeof(data) == TYPE_DICTIONARY:
			return data
		var aside := "%s.corrupt-%d" % [candidate, Time.get_unix_time_from_system()]
		push_warning("save %s is unreadable, moved it to %s" % [candidate, aside])
		DirAccess.rename_absolute(candidate, aside)
	return {}


static func _backup(path: String) -> String:
	return path + ".bak"
