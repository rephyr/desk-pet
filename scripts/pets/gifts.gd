class_name Gifts
extends RefCounted
## Presents (data/gifts.json): one every few hours of wall clock into a small pocket, open or
## closed alike (only the unix time counts, never frame time), so closing the game never pays
## better. No streak, no calendar. Nothing starts until the boxes tab opens. Pure rules: GameState
## holds the state { next_at, pocket } (next_at 0: not started yet) and hands out what's inside.


static func fresh() -> Dictionary:
	return { "next_at": 0.0, "pocket": 0 }


static func every(cfg: Dictionary) -> float:
	return maxf(60.0, float(cfg.get("every", 10800)))


static func cap(cfg: Dictionary) -> int:
	return maxi(1, int(cfg.get("pocket", 3)))


## Moves the clock on to `now`. `open`: the boxes tab is open (before that nothing happens, not
## even the clock starting). Returns how many presents went into the pocket.
static func tick(state: Dictionary, cfg: Dictionary, now: float, open: bool) -> int:
	if not open:
		return 0
	var step := every(cfg)
	var first := maxf(0.0, float(cfg.get("first_after", step)))
	if float(state.next_at) <= 0.0:
		state.next_at = now + first
		return 0
	# a clock set backwards never holds presents back for longer than one step
	state.next_at = minf(float(state.next_at), now + maxf(step, first))
	var added := 0
	while int(state.pocket) < cap(cfg) and now >= float(state.next_at):
		state.pocket = int(state.pocket) + 1
		state.next_at = float(state.next_at) + step
		added += 1
	if int(state.pocket) >= cap(cfg):
		state.next_at = now + step  # full: the clock waits, taking one out starts a fresh step
	return added


## What's inside a present, rolled when it's opened: { boxes: 1 or 2, toy: bool }. A toy capsule
## only once toys are open (`toys_open`).
static func roll(cfg: Dictionary, rng: RandomNumberGenerator, toys_open: bool) -> Dictionary:
	var boxes := 2 if rng.randf() < float(cfg.get("two_boxes", 0.0)) else 1
	var toy := toys_open and rng.randf() < float(cfg.get("toy", 0.0))
	return { "boxes": boxes, "toy": toy }


## A saved state, kept sane (a pocket over the cap, a missing field).
static func clean(saved: Variant, cfg: Dictionary) -> Dictionary:
	var out := fresh()
	if saved is Dictionary:
		out.next_at = maxf(0.0, float(saved.get("next_at", 0.0)))
		out.pocket = clampi(int(saved.get("pocket", 0)), 0, cap(cfg))
	return out


## Presents a day at most (the pocket emptied as they come).
static func per_day(cfg: Dictionary) -> float:
	return 86400.0 / every(cfg)
