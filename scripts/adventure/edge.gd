class_name Edge
extends RefCounted
## Past the edge (data/edge.json): the beyond-the-fence map stops at a torn edge, and herd pets you
## send there never come back. They fill the next page (tucked under the tear) with their crayon
## scribbles; when a page has its "need" of pets it opens (an unlock waiting for { "edge": page id }).
## Pure rules on the saved state:
##   { page: pages filled so far, sent: pets on the page being filled, ever: every pet sent,
##     marks: [palette ids], one per scribble on the page being filled (up to marks_max) }


static func fresh() -> Dictionary:
	return { "page": 0, "sent": 0, "ever": 0, "marks": [] }


static func pages(catalog: Catalog) -> Array:
	return catalog.edge.get("pages", [])


## The page being filled now, or {} once every page in the data is full.
static func page(catalog: Catalog, state: Dictionary) -> Dictionary:
	var list := pages(catalog)
	var i := int(state.get("page", 0))
	return list[i] if i >= 0 and i < list.size() else {}


## Every page in the data is full: nothing is tucked under the edge any more.
static func done(catalog: Catalog, state: Dictionary) -> bool:
	return page(catalog, state).is_empty()


## Pets the page being filled needs in all (0 once every page is full).
static func need(catalog: Catalog, state: Dictionary) -> int:
	return maxi(1, int(page(catalog, state).get("need", 1))) if not done(catalog, state) else 0


## Pets still to go for the page being filled.
static func to_go(catalog: Catalog, state: Dictionary) -> int:
	return maxi(0, need(catalog, state) - int(state.get("sent", 0))) if not done(catalog, state) else 0


## Whether the page `page_id` is full (it has opened).
static func page_full(catalog: Catalog, state: Dictionary, page_id: String) -> bool:
	var list := pages(catalog)
	for i in list.size():
		if str(list[i].get("id", "")) == page_id:
			return i < int(state.get("page", 0))
	return false


## How many scribbles a page shows with `sent` of its `need` pets: one a pet, spread over at most
## marks_max once a page needs more than that.
static func marks_for(catalog: Catalog, sent: int, need_n: int) -> int:
	if need_n <= 0:
		return 0
	var most := mini(need_n, int(catalog.edge.get("marks_max", 520)))
	return clampi(roundi(float(mini(sent, need_n)) / need_n * most), 0, most)


## `n` pets went past the edge; `palettes` are some of their colours (for the scribbles). Pages
## that fill open and the next one starts. Returns the ids of the pages that filled.
static func add(catalog: Catalog, state: Dictionary, n: int, palettes: Array) -> Array[String]:
	var filled: Array[String] = []
	var used := 0
	while n > 0 and not done(catalog, state):
		var take := mini(n, to_go(catalog, state))
		n -= take
		state.sent = int(state.get("sent", 0)) + take
		state.ever = int(state.get("ever", 0)) + take
		var marks: Array = state.get("marks", [])
		var want := marks_for(catalog, int(state.sent), need(catalog, state))
		while marks.size() < want:
			marks.append(str(palettes[used % palettes.size()]) if not palettes.is_empty() else "")
			used += 1
		state.marks = marks
		if int(state.sent) >= need(catalog, state):
			filled.append(str(page(catalog, state).get("id", "")))
			state.page = int(state.get("page", 0)) + 1
			state.sent = 0
			state.marks = []
	return filled


## The state from a save: whole numbers in range, known palettes only (older saves: fresh).
static func clean(catalog: Catalog, raw) -> Dictionary:
	var out := fresh()
	if not raw is Dictionary:
		return out
	out.page = clampi(int(_num(raw.get("page", 0))), 0, pages(catalog).size())
	out.ever = maxi(0, int(_num(raw.get("ever", 0))))
	if not done(catalog, out):
		out.sent = maxi(0, int(_num(raw.get("sent", 0))))
		out.ever = maxi(int(out.ever), int(out.sent))
		var marks = raw.get("marks", [])
		# a page that needs fewer pets now than the save already sent opens (like add); the rest
		# carry on to the next page (its scribbles start again)
		while not done(catalog, out) and int(out.sent) >= need(catalog, out):
			out.sent = int(out.sent) - need(catalog, out)
			out.page = int(out.page) + 1
			marks = []
		if done(catalog, out):
			out.sent = 0
		elif marks is Array:
			var want := marks_for(catalog, int(out.sent), need(catalog, out))
			for m in marks:
				if out.marks.size() >= want:
					break
				out.marks.append(str(m) if m is String and not catalog.part("palette", str(m)).is_empty() else "")
	out.ever = maxi(int(out.ever), int(out.sent))
	return out


static func _num(v) -> float:
	return float(v) if v is int or v is float else 0.0
