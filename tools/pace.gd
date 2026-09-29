extends SceneTree
## Pacing for the whole early game: pretend players (tools/pace_player.gd) play a fresh game with
## the game's own GameState, rules and data, minute by minute: the tutorial, the lever and the
## repair tree, adventures and bits, errands (every job, its tools and goals), gear bought with xp,
## automation and workers. It plays through the real functions and data/, so it can be run again
## after most rule or data changes; but a few rules are copied into pace_player.gd and must be kept in
## step by hand (the automation tick, treats on the trail, the passive coin and care decay, and the
## timestamps it moves onto its own clock: trips, fever, rummage). See pace_player.gd's header. Prints:
##   1. milestones: the median minute each thing first happened, and how many players got there
##   2. coins a minute by source every 10 minutes (and the errands job by job)
##   3. gates: how long players waited on bits and on coins for each gate buy
##   4. what coins went on, and what got bought most
## Run it with a profile, always (it refuses to run without one): the sim's own GameState never saves,
## but Godot's GameState autoload loads and saves the profile's save.json like any -s script:
##   godot --headless -s tools/pace.gd -- --profile=test-sim [--minutes=240] [--runs=5] [--style=steady|casual] [--seed=1] [--treats]
## To try a number without changing data/, --tweak=<path>=<value> changes it in memory for this run
## (any number of them). The path starts at a Catalog field; in a list it picks the entry with that
## id, or a plain index: --tweak=jobs/coin_hunt/tools/noses/max=20 --tweak=rummage_spots/0/coins/1=10
## --treats: the player also tosses every treat on its own trips (the treat pouch counts then).
## Not in it: toys (their boosts need real time), trail pickups, being away.

const PacePlayer := preload("res://tools/pace_player.gd")


func _init() -> void:
	if not DevProfile.active():
		push_error("pace.gd needs -- --profile=<name> (never the real save)")
		quit(1)
		return
	var minutes := float(_arg("minutes", "240"))
	var runs := int(_arg("runs", "5"))
	var style := _arg("style", "steady")
	var seed_base := int(_arg("seed", "1"))
	print("pace: %d %s players%s, %d minutes each (seed %d)" % [runs, style, " tossing treats" if "--treats" in OS.get_cmdline_user_args() else "", int(minutes), seed_base])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tweak="):
			_tweak(a.substr(8))
	var players: Array = []
	var started := Time.get_ticks_msec()
	for r in runs:
		var p = PacePlayer.new(style, seed_base * 1000 + r)
		p.treats = "--treats" in OS.get_cmdline_user_args()
		p.play(minutes)
		players.append(p)
		print("  player %d done in %.1f s: %s coins, %d pets, %d trips, %d pets stayed behind on your trips" % [r + 1,
			(Time.get_ticks_msec() - started) / 1000.0, _num(p.gs.coins), p.gs.collection.count(), p.gs.trips_done, p.lost])
		started = Time.get_ticks_msec()
	_print_milestones(players)
	_print_income(players)
	_print_gates(players)
	_print_spending(players)
	for p in players:
		p.free_game()
	_tidy()
	quit()


## --tweak=jobs/coin_hunt/tools/noses/max=20: changes one number (or any JSON value) in the shared
## catalog, in memory only, before anyone plays.
func _tweak(spec: String) -> void:
	var eq := spec.rfind("=")
	var path := spec.substr(0, eq).split("/")
	var raw := spec.substr(eq + 1).strip_edges()
	var value = JSON.parse_string(raw)
	if value == null and raw != "null":
		push_error("tweak: %s is not JSON" % spec)
		return
	var at: Variant = Catalog.shared().get(path[0])
	for i in range(1, path.size() - 1):
		at = _step(at, path[i])
	var last := path[path.size() - 1]
	if at is Dictionary:
		print("  tweak %s: %s -> %s" % ["/".join(path), str(at.get(last, "(none)")), str(value)])
		at[last] = value
	elif at is Array and last.is_valid_int() and int(last) >= 0 and int(last) < at.size():
		print("  tweak %s: %s -> %s" % ["/".join(path), str(at[int(last)]), str(value)])
		at[int(last)] = value
	else:
		push_error("tweak: can't set %s" % spec)


func _step(at: Variant, key: String) -> Variant:
	if at is Dictionary:
		return at.get(key)
	if at is Array:
		for e in at:
			if e is Dictionary and str(e.get("id", "")) == key:
				return e
		if key.is_valid_int() and int(key) < at.size():
			return at[int(key)]
	return null


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return fallback


static func _median(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	if s.is_empty():
		return NAN
	return s[s.size() / 2] if s.size() % 2 == 1 else (s[s.size() / 2 - 1] + s[s.size() / 2]) / 2.0


func _print_milestones(players: Array) -> void:
	var at := {}
	for p in players:
		for what in p.milestones:
			if not at.has(what):
				at[what] = []
			at[what].append(p.milestones[what])
	var rows := []
	for what in at:
		rows.append([_median(at[what]), what, at[what].size(), at[what].min(), at[what].max()])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	print("\n== milestones (median minute, players who got there of %d, earliest-latest) ==" % players.size())
	for r in rows:
		print("%7.1f  %-44s %d  (%.0f-%.0f)" % [r[0], r[1], r[2], r[3], r[4]])


func _print_income(players: Array) -> void:
	var sources: Array = PacePlayer.SOURCES
	print("\n== coins a minute by source, average of the players, every 10 minutes ==")
	var head := "%5s" % "min"
	for s in sources:
		head += " %10s" % s
	head += " %10s %10s %6s %6s %5s %9s" % ["total", "banked", "pets", "xp", "trips", "capsule"]
	print(head)
	var rows: int = players[0].windows.size()
	var jobs := {}
	for i in rows:
		var line := "%5d" % int(players[0].windows[i].minute)
		var total := 0.0
		for s in sources:
			var v := _avg(players, i, func(w): return float(w.per_min.get(s, 0.0)))
			total += v
			line += " %10s" % _num(v)
		line += " %10s %10s %6.0f %6.0f %5.0f %9s" % [_num(total), _num(_avg(players, i, func(w): return float(w.coins))),
			_avg(players, i, func(w): return float(w.pets)), _avg(players, i, func(w): return float(w.xp)),
			_avg(players, i, func(w): return float(w.trips)), _num(_avg(players, i, func(w): return float(w.cv)))]
		print(line)
		for p in players:
			for j in p.windows[i].errands:
				jobs[j] = true
	if jobs.is_empty():
		return
	print("\n-- errands, coins a minute by job --")
	head = "%5s" % "min"
	for j in jobs:
		head += " %10s" % j
	print(head)
	for i in rows:
		var line := "%5d" % int(players[0].windows[i].minute)
		for j in jobs:
			line += " %10s" % _num(_avg(players, i, func(w): return float(w.errands.get(j, 0.0))))
		print(line)


func _avg(players: Array, i: int, f: Callable) -> float:
	var s := 0.0
	for p in players:
		s += f.call(p.windows[i])
	return s / players.size()


func _print_gates(players: Array) -> void:
	var names := []
	for p in players:
		for g in p.gates:
			if not g in names:
				names.append(g)
	var rows := []
	for g in names:
		var seen := []
		var bits := []
		var coins := []
		var bought := []
		for p in players:
			if not p.gates.has(g):
				continue
			var e: Dictionary = p.gates[g]
			seen.append(float(e.seen) / 60.0)
			if float(e.ready) >= 0.0:
				bits.append((float(e.ready) - float(e.seen)) / 60.0)
				if float(e.bought) >= 0.0:
					coins.append((float(e.bought) - float(e.ready)) / 60.0)
					bought.append(float(e.bought) / 60.0)
		rows.append([_median(seen), g, _median(bits), _median(coins), _median(bought), bought.size()])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	print("\n== gates: median minutes (shows up, then waiting on bits, then saving coins; bought at) ==")
	print("%7s  %-36s %9s %9s %9s  %s" % ["shows", "gate", "on bits", "on coins", "bought", "players"])
	for r in rows:
		print("%7.1f  %-36s %9s %9s %9s  %d" % [r[0], r[1], _m(r[2]), _m(r[3]), _m(r[4]), r[5]])


func _print_spending(players: Array) -> void:
	var spent := {}
	var buys := {}
	for p in players:
		for k in p.spent:
			spent[k] = float(spent.get(k, 0.0)) + float(p.spent[k]) / players.size()
		for k in p.buys:
			buys[k] = float(buys.get(k, 0.0)) + float(p.buys[k]) / players.size()
	print("\n== coins spent, average per player ==")
	for k in spent:
		print("  %-14s %s" % [k, _num(spent[k])])
	var list := buys.keys()
	list.sort_custom(func(a, b): return buys[a] > buys[b])
	print("\n== bought most (times, average per player) ==")
	for k in list.slice(0, 30):
		print("  %-28s %.1f" % [k, buys[k]])


static func _m(v: float) -> String:
	return "-" if is_nan(v) else "%.1f" % v


## 950, 12.3k, 4.5M, 1.2B, 7.3T.
static func _num(v: float) -> String:
	var a := absf(v)
	if a >= 1.0e12:
		return "%.1fT" % (v / 1.0e12)
	if a >= 1.0e9:
		return "%.1fB" % (v / 1.0e9)
	if a >= 1.0e6:
		return "%.1fM" % (v / 1.0e6)
	if a >= 1.0e4:
		return "%.1fk" % (v / 1.0e3)
	return "%.0f" % v


## debug_new_game copies the save aside first: those copies (of the scratch file) go again.
func _tidy() -> void:
	var dir := DevProfile.path("")
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("save-before-new-game-") and FileAccess.get_file_as_string(dir + f) == "{}":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DevProfile.path("pace-scratch.json")))
