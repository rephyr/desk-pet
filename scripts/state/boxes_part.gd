class_name BoxesPart
extends RefCounted
## GameState's code for boxes: the shop, the pile, opening them (by you or your pet in the
## background), good pulls pinned, the idle log.
## A part of GameState (see tools/state_parts.py): works on GameState's state through gs; GameState
## forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Turns one of your pet's jobs ("packs" or "buying") on or off, from settings or the corner panel.
func set_job(job: String, on: bool) -> void:
	match job:
		"packs":
			if on:
				gs.set_task("boxes")
			elif gs.automation.task == "boxes":
				gs.set_task("")
		"buying": gs.buying_on = on
	gs.save_game()
	gs.changed.emit()


## The coins your pet keeps when it buys boxes itself: its reserve of capsules x what a capsule is
## worth now, so it keeps up with box prices.
func coin_reserve() -> int:
	return roundi(minf(float(gs.reserve_capsules) * gs.capsule_value(), Jobs.MAX_PRICE))


## Where the reserve starts, its step and its top, in capsules (data/boxes.json "reserve").
func default_reserve() -> int:
	return int(gs.catalog.box_rules.get("reserve", {}).get("capsules", 50))


func reserve_step() -> int:
	return int(gs.catalog.box_rules.get("reserve", {}).get("step", 50))


func reserve_max() -> int:
	return int(gs.catalog.box_rules.get("reserve", {}).get("max", 2000))


## Sets the reserve to `capsules` (0 up to reserve_max) and saves.
func set_reserve(capsules: int) -> void:
	gs.reserve_capsules = clampi(capsules, 0, reserve_max())
	gs.save_game()


## What `count` of a box cost in coins now (see box_cost).
func box_price(box_id: String, count := 1) -> int:
	return GameStateNode.box_cost(gs.catalog.box(box_id), gs.capsule_value(), count)


## The box tiers in the shop: the ones whose map page is open, cheapest first.
func shop_boxes() -> Array[Dictionary]:
	return BoxShop.open_tiers(gs.catalog, gs.page_open, gs.debug_all_tiers and OS.is_debug_build())


## The best box rank in the shop: the book only counts looks those boxes can hold (Book).
func book_rank() -> int:
	var best := 0
	for b in shop_boxes():
		best = maxi(best, gs.catalog.box_rank(str(b.id)))
	return best


func box_in_shop(box_id: String) -> bool:
	return shop_boxes().any(func(b): return b.id == box_id)


## The piles on your stash: every tier in the shop, and any other box you have some of.
func stash_boxes() -> Array[Dictionary]:
	var out := shop_boxes()
	for b in gs.catalog.shop_boxes():
		if in_bag(b.id) > 0 and not out.has(b):
			out.append(b)
	out.sort_custom(func(a, b): return gs.catalog.box_rank(a.id) < gs.catalog.box_rank(b.id))
	return out


## A tier that just came into the shop wears a gold "new!" tag until you buy your first one (the
## first tier never does: it was always there).
func box_is_new(box_id: String) -> bool:
	return gs.catalog.box_rank(box_id) > 0 and box_in_shop(box_id) and int(gs.boxes_bought.get(box_id, 0)) == 0


## Something waits in the boxes tab: boxes on the pile, or a tier that came into the shop.
func box_news() -> bool:
	return gs.bag.values().any(func(n): return int(n) > 0) or shop_boxes().any(func(b): return box_is_new(b.id) and not gs.boxes_greeted.has(b.id))


## The boxes tab showed this tier arriving (its row popped in, your pet said so): only once.
func greet_box(box_id: String) -> void:
	if not gs.boxes_greeted.has(box_id):
		gs.boxes_greeted[box_id] = true
		gs.save_game()


## Buys boxes: they go on your pile (the bag) to open later, by you or your pet. Returns
## whether you could afford them (and the shop sells that tier).
func buy_boxes(box_id: String, count := 1) -> bool:
	var price := box_price(box_id, count)
	if count <= 0 or gs.coins < price or not box_in_shop(box_id):
		return false
	gs.coins -= price
	gs.bag[box_id] = in_bag(box_id) + count
	gs.boxes_bought[box_id] = int(gs.boxes_bought.get(box_id, 0)) + count
	gs.changed.emit()
	gs.save_game()
	return true


## Debug: puts one box on your pile for free (the dev buttons open it straight away).
func debug_give_box(box_id: String) -> void:
	if OS.is_debug_build():
		gs.bag[box_id] = in_bag(box_id) + 1


## How many more coins you'd need to buy `count` of a box, 0 if you can.
func coins_short(box_id: String, count := 1) -> int:
	return maxi(0, box_price(box_id, count) - gs.coins)


## Opens `count` boxes from your pile. Returns the new pets, every pet in every box (a sunset box
## holds 2-3), box by box; empty if there aren't that many on the pile.
## Only as many boxes as the room has space for open (a full room opens none: they wait on the pile).
## `force_tier` only works in debug builds, for testing reveals (the first pet of each box).
## `by_pet`: your pet opened it (doesn't count toward packs you opened yourself).
## Once the sorting rule is on, the new pets it sorts leave for new homes (or go to work) as they
## arrive: they're still in what this returns (the reveal shows everything you pulled).
func open_boxes(box_id: String, count := 1, force_tier := "", by_pet := false) -> Array[Pet]:
	var pulled: Array[Pet] = []
	if count <= 0 or in_bag(box_id) < count:
		return pulled
	if not gs.tutorial_active():
		count = mini(count, boxes_that_fit(box_id))
		if count <= 0:
			gs._room_hit()
			if not by_pet:
				gs.room_full.emit()
			return pulled
	gs.bag[box_id] = in_bag(box_id) - count
	if gs.bag[box_id] <= 0:
		gs.bag.erase(box_id)
	# the tutorial's boxes are plain commons: your first pets shouldn't be a mythic by luck
	var roll_from := GameStateNode.TUTORIAL_BOX if gs.tutorial_active() else box_id
	var forced := force_tier if OS.is_debug_build() and not gs.tutorial_active() else ""
	for i in count:
		pulled.append_array(gs._roller.roll_box(roll_from, forced))
	gs._sent_home.clear()
	for pet in gs.collection.add(pulled, gs._sorter()):
		gs._sent_home[pet.uid] = true
	if gs.room_left() <= 0 and not gs.tutorial_active():
		gs._room_hit()
	if not by_pet:
		gs.packs_by_hand += count
		gs.check_unlocks()
	gs.changed.emit()
	gs.save_game()
	return pulled


func in_bag(box_id: String) -> int:
	return int(gs.bag.get(box_id, 0))


## How many of a box fit in the room now: each counts as its most pets (a sunset box as 3), rounded
## up, so the last box can squeeze a pet or two past the cap. 0 when the room is full.
func boxes_that_fit(box_id: String) -> int:
	var left := gs.room_left()
	if left <= 0:
		return 0
	var range_: Array = gs.catalog.box(box_id).get("pets", [1, 1])
	return ceili(float(left) / maxi(1, int(range_[range_.size() - 1])))


## Debug: `count` more pets from starter boxes, straight into the collection.
func debug_give_pets(count: int) -> void:
	if not OS.is_debug_build():
		return
	var pulled: Array[Pet] = []
	for i in count:
		pulled.append(gs._roller.roll(GameStateNode.FIRST_PET_BOX))
	gs.collection.add(pulled)
	gs.changed.emit()
	gs.save_game()


func add_debug_coins() -> void:
	gs.coins += GameStateNode.DEBUG_COINS
	gs.changed.emit()


func _give_first_pet() -> void:
	var first: Array[Pet] = [gs._roller.roll(GameStateNode.FIRST_PET_BOX)]
	gs.collection.add(first)


## Whether your pet may open this kind of box (you didn't save it for yourself).
func pet_opens(box_id: String) -> bool:
	return not gs.saved_boxes.has(box_id)


## "Save for me" on or off for a kind of box.
func save_for_me(box_id: String, on: bool) -> void:
	if on:
		gs.saved_boxes[box_id] = true
	else:
		gs.saved_boxes.erase(box_id)
	gs.save_game()
	gs.changed.emit()


## The box your pet would open next: one on the pile it's allowed to open, or, once it has the
## piggy bank, the cheapest one it may open that it can buy and still keep the reserve. "" if none.
func next_pet_box() -> String:
	for id in pet_box_order():
		if in_bag(id) > 0:
			return id
	if not (gs.feature_on("shopping") and gs.buying_on):
		return ""
	for box in shop_boxes():
		if pet_opens(box.id) and gs.coins - box_price(box.id) >= coin_reserve():
			return box.id
	return ""


## The kinds of box your pet (and the box workers) may open, in the order they get to them.
func pet_box_order() -> Array:
	return stash_boxes().filter(func(b): return pet_opens(b.id)).map(func(b): return b.id)


## How many boxes wait on your pile, all kinds together.
func boxes_on_pile() -> int:
	var n := 0
	for box_id in gs.bag:
		n += in_bag(box_id)
	return n


## Whether your pet may open a pack now: it's allowed to, there's one for it, and there's room.
func can_auto_open() -> bool:
	return gs.packs_on and gs.knows_job("boxes") and not gs.tutorial_active() and gs.room_left() > 0 and next_pet_box() != ""


## A view is showing your pet at work (the home room or the corner panel), so it opens packs
## there, one by one, with its little animation. Called every frame it's on screen.
func pack_job_seen() -> void:
	gs._pack_seen = 0.0


## When nothing shows your pet at work (you're on another tab), it keeps opening packs anyway, at
## about the pace of its animation. What it opened goes in the idle log and good pulls get pinned,
## so the home screen tells you about them when you're back.
func _open_in_background(delta: float) -> void:
	gs._pack_seen += delta
	if gs._pack_seen < GameStateNode.BACKGROUND_AFTER:
		gs._pack_timer = 0.0
		return
	gs._pack_timer += delta * gs.boost("automation") * gs.boost("pets")
	if gs._pack_timer >= GameStateNode.BACKGROUND_PACK_EVERY:
		gs._pack_timer = 0.0
		var pet := auto_open_pack()
		if pet:
			gs.opened_in_background.emit(pet)


## How far along the pack your pet is opening out of sight is, 0 to 1, or -1 if it isn't.
func background_packing() -> float:
	if gs._pack_seen < GameStateNode.BACKGROUND_AFTER or not can_auto_open():
		return -1.0
	return gs._pack_timer / GameStateNode.BACKGROUND_PACK_EVERY


## Your pet opens a box from the pile, buying one first if it has to and may (the corner panel
## calls this when its little animation pops). Returns the best pet in it (the one its animation
## shows), or null. Every pet in it goes in the idle log; good pulls get pinned for you to see.
func auto_open_pack() -> Pet:
	if not can_auto_open():
		return null
	var box_id := next_pet_box()
	if in_bag(box_id) == 0 and not buy_boxes(box_id, 1):
		return null
	var pulled := open_boxes(box_id, 1, "", true)
	if pulled.is_empty():
		return null
	var good: Array = []
	var pins: Array[String] = []
	for pet in pulled:
		if is_good_pull(pet) and gs.collection.get_pet(pet.uid) == pet:  # not one the sorting rule sent off
			pins.append(pet.uid)
			good.append(pet.display_name(gs.catalog))
	_pin(pins)
	_log_idle({ "packs": 1, "good": good })
	return BoxShop.best_first(pulled, gs.catalog)[0]


## Good pulls wait for you to see them, the newest PINNED_MAX only: a pinned pet stays a card (it
## can't fold, go to new homes or past the edge), so a pile of unseen pulls would fill the room.
func _pin(uids: Array[String]) -> void:
	if uids.is_empty():
		return
	gs.pinned.append_array(uids)
	gs._spare_changed()
	if gs.pinned.size() > GameStateNode.PINNED_MAX:
		gs.pinned = gs.pinned.slice(gs.pinned.size() - GameStateNode.PINNED_MAX)
		gs.collection.refold()  # the ones that stopped waiting may fold into the herd now


## Rare or better, or a holo-or-better finish: worth showing you.
func is_good_pull(pet: Pet) -> bool:
	return gs.catalog.rank(pet.rarity) >= 2 or gs.catalog.finish_rank(pet.finish) >= 2


## You've seen a good pull: `uid` that one (if it's still pinned), or "" the oldest.
func dismiss_pinned(uid := "") -> void:
	var i := 0 if uid == "" else gs.pinned.find(uid)
	if i >= 0 and i < gs.pinned.size():
		gs.pinned.remove_at(i)
		gs._spare_changed()
		gs.collection.refold()  # a good pull you've seen may fold into the herd now
		gs.changed.emit()


## What your pet did while you weren't looking, then forgotten (the home screen tells you once).
func take_idle_log() -> Dictionary:
	var out := gs.idle_log
	gs.idle_log = {}
	return out


func _log_idle(add: Dictionary) -> void:
	for key in add:
		if add[key] is Array:
			var list: Array = gs.idle_log.get(key, [])
			list.append_array(add[key])
			gs.idle_log[key] = list
		else:
			gs.idle_log[key] = Rewards.plus(int(gs.idle_log.get(key, 0)), int(add[key]))  # (kept until your pet tells you: never wraps)


## The box a present holds: the newest tier in the shop (the highest box rank whose map page is
## open), the first tier when none is.
func newest_box_id() -> String:
	var best := GameStateNode.FIRST_PET_BOX
	for b in shop_boxes():
		if gs.catalog.box_rank(str(b.id)) > gs.catalog.box_rank(best):
			best = str(b.id)
	return best
