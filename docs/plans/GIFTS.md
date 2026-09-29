# GIFTS (care C): presents

From docs/picks.md "Brainstorm 3 picks", care C. Build plan, short.

One present every 3 h of wall clock, open or closed (so closing never pays better), a pocket of 3,
no streak, no calendar. The clock starts when the boxes tab opens; before that there's nothing (no
empty pocket, no hint). A present holds a box of your newest tier, sometimes 2 boxes, sometimes a
toy capsule as well. Never bits, never a pet.

## The clock (pure rules: `scripts/pets/gifts.gd`, `class_name Gifts extends RefCounted`)

- State (in the save): `{ "next_at": float, "pocket": int }`. `next_at == 0` means not started yet.
- `Gifts.tick(state, cfg, now, open) -> int` (presents added):
  - not `open` (boxes tab closed): nothing.
  - `next_at == 0`: start it, `next_at = now + first_after`.
  - while `pocket < cap` and `now >= next_at`: `pocket += 1`, `next_at += every`.
  - pocket full: `next_at = now + every` (the clock waits, so taking one out starts a fresh 3 h,
    and nothing piles up past 3 however long the game was closed).
  - clock set backwards: `next_at` is clamped to at most `now + every`.
- `Gifts.roll(cfg, rng, toys_open) -> { boxes: int, toy: bool }`: always 1 box, a second box with
  `two_boxes` chance, a toy capsule as well with `toy` chance (only when toys are open).
- Same result open or closed: it only looks at the unix time, never at frame time.

## Data: new `data/gifts.json` (Catalog loads it as `catalog.gifts`)

```json
{
  "_note": "...",
  "every": 10800, "first_after": 10800, "pocket": 3,
  "two_boxes": 0.2, "toy": 0.2,
  "dig": 1.6, "dig_again": 30, "pop": 1.2
}
```
`dig`: seconds the desktop pet digs; `dig_again`: seconds after a tap before it digs up the next one;
`pop`: seconds the opened present's contents hop up on the desktop. Its own file (not care.json) so
it doesn't collide with the other care parts.

## GameState

- `var gifts := Gifts.fresh()`, `signal gifts_changed`.
- `newest_box_id() -> String`: returns `FIRST_PET_BOX` ("starter") here. **Merge note:** B1's tiers
  live in another branch; the merge swaps this one helper for the newest open tier.
- `gifts_waiting() -> int` (the pocket), `open_gift() -> Dictionary`: takes one out, rolls it at
  opening time (so the newest tier is today's), grants `{ "box:<newest>": n }` through `grant()`
  (so it lands on the pile), and for a toy does `Toys.roll` + `Toys.add` the way the machine does
  (luck from `boost("luck")`). Returns `{ box, boxes, toy: { id, finish, new } or {} }`. Saves,
  emits `gifts_changed` + `changed`. Nothing here touches bits or the collection.
- Ticked once a second from the existing timer in `_process`, and once at the end of `_load_save`.
- `debug_gift_roll := ""` (dev: next present is "one", "two" or "toy").

## Save: v24 -> v25

- New field `"gifts": { "next_at", "pocket" }`, loaded with clamps (pocket 0..cap).
- Migration v25: nothing to convert. Older saves with the boxes tab open start the clock on load
  (first present 3 h later); saves without it wait for the tab. Noted for the merge renumbering.

## Home tab (your pet holding a wrapped present)

- While `gifts_waiting() > 0`: when your pet is sitting (PackJob SIT, not rummaging, no good pull
  held up) it holds a wrapped present in its paws in `_draw_front` (pixel box, pink paper, lilac
  ribbon and bow, a small wobble every few seconds). When it's busy with the pile or rummaging,
  the present stands on the floor by its feet, so the pile never waits on you.
- More than one waiting: 1 or 2 more wrapped ones stacked small beside it (no number, no text).
- Tap: the pet's click goes present-first (after "busy rummaging" and `_work.tap()`, before pat).
  A small invisible Control over the floor present takes taps too.
- Opening: the present shakes (0.4 s), pops (the existing gold puff), then:
  box(es) fly to the pile (reuse the floaters, "+1 box" / "+2 boxes"); a toy capsule shows the
  machine's `MachineTab.PrizePopup` with a `ToyView` (same title/tag as a machine toy, "new!" when
  new). No tooltip explaining presents.

```
   window            [sticky notes]
        (bow)
       [####]  <- wrapped present in its paws
        (pet)      [pile x12]
   ~~~~~~~~ rug ~~~~~~~~
   [card: name, food, mood]
```

## Desktop (your pet digs it up and wears it)

- In QuietPaws: new `Pose.DIG` and `var worn := false`. When `worn` is false, the pocket has one,
  the pet is grounded and stopped **on a window edge** (not the screen bottom), and `dig_again` has
  passed: DIG for `dig` s (faces down, squash on a beat, brown dirt pixels spraying behind it), then
  the present pops up and lands on its head: `worn = true`. Priority: hold > dig > wait > stint.
- Worn: drawn by the front PawsView on its head in every pose and while walking or falling; a held
  good pull sits one present higher. `_body_rect()` grows to take in the present so it's tappable.
- Tap while worn: `GameState.open_gift()` instead of a pat; a pop pose (puff, then a tiny pack art
  via `PawsView.draw_pack`, or a two-tone capsule for a toy, hops up and fades over `pop` s).
  No text. A drag is still a drag.
- If the pocket empties from the home tab, `worn` clears (the present just isn't there any more).
- Setting: shown at **big things** and **everything**; at **off** the pet walks like before and the
  present waits on the home tab.

## Dev steps (DevDriver)

- `gift <n>`: n presents in the pocket now (up to the cap; starts the clock).
- `gift-clock <hours>`: moves the present clock that many hours on (`next_at -= hours*3600`, then a
  tick), to check the 3 h step and the pocket cap.
- `gift-roll one|two|toy`: what the next present holds.
- `desk tap`: taps the pretend desktop pet (as a click would).
- `home gift`: taps the present on the home tab.
- `expect gifts <n>`: the pocket holds n.

## Flow: tests/flows/gifts.flow

from pile_full, view full, tab home, expect gifts 0, gift-clock 2.9, expect gifts 0,
gift-clock 0.2, expect gifts 1, wait 1, shot home_present, gift-clock 20, expect gifts 3,
shot home_three, expect fits, gift-roll one, home gift, wait 1.5, expect gifts 2, shot home_opened,
gift-roll toy, home gift, wait 1, shot home_toy, desk on, wait 1.5, wait for the dig (a `wait`
long enough, or `wait dig`), shot desk_dig, wait 2, shot desk_worn, gift-roll two, desk tap, wait 0.5,
shot desk_pop, expect gifts 0, paws off, gift 1, wait 4, shot desk_off (no dig), desk off,
expect fits. Also replay fits, paws and care.

## Tests (tests/test_core.gd, `_test_gifts`)

- Gifts.tick: nothing while the boxes tab is closed (hours pass, still 0, next_at stays 0); opening
  it starts the clock; one at 3 h, not at 2.99 h; the pocket stops at 3 after 100 h and the next
  comes 3 h after one is taken; a clock set backwards doesn't hold presents back forever.
- Open vs closed pays the same: 10 h ticked in 1 s steps == 10 h in one save/load jump (test
  profile save, `saved_at` moved back).
- open_gift: boxes land on the pile as `newest_box_id()`; never bits, never a new pet (collection
  size, bits unchanged over 500 opens); a toy only when toys are open; roll rates near the data
  over many opens; opening with an empty pocket does nothing.
- Save: pocket and next_at survive a save/load; a v24 save loads with a fresh clock.
- QuietPaws: DIG only on a window edge with a present and level >= 1, never at off; after `dig` s
  `worn`; a good pull beats a dig; the pocket emptied elsewhere clears `worn`.
- DesktopPet in stage mode: a tap while worn opens a present (pocket - 1) and isn't a pat (mood
  unchanged); a tap without one is still a pat.
- `tools/balance.gd`: prints presents per day (8 max) and boxes per day from them.

## Docs

docs/design.md (Care: presents), docs/architecture.md (Gifts, the tick, the QuietPaws DIG pose),
and GIFTS-done.md with the dev plan and CLAUDE.md text, the save bump and the newest_box_id merge
note.

## Questions for Emilia (smallest safe pick taken)

- The first present comes 3 h after the boxes tab opens (not straight away). OK?
- A toy capsule comes **with** a box (1 box + toy), not instead of it. OK?
- A toy capsule opens right away (picture card on the home tab), not at the machine. OK?
- Out on your windows, "off" hides the digging too (the present waits on the home tab). OK?
- It only digs on window edges, not on the bottom of the screen. OK?
