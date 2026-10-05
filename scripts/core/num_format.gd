class_name NumFormat
extends RefCounted
## How numbers read on screen (UiTheme.num / full_num use these). Pure: no theme or game needed,
## so the tests can check it.


## A whole number in full with thousands commas: 1,234,567.
static func full(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## A number short: in full under 10,000, then 12.3k, 456M, 7.8B, 1.2T, 3.4Qa ... (the idle-game
## units, so late-game coins never turn into 3.11e+15).
static func short(n: float) -> String:
	var a := absf(n)
	if a < 10000.0:
		return full(roundi(n))
	var units := ["k", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
	var v := a
	for u in units:
		v /= 1000.0
		var digits := 1 if v < 99.95 else 0
		var shown := snappedf(v, pow(10, -digits))
		if shown < 1000.0:  # 999.96k rounds up to the next unit, never "1000k"
			return ("-" if n < 0 else "") + str(shown).trim_suffix(".0") + u
	return "%.2e" % n
