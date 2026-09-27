# Architecture

How the code is laid out and where new things go. Game design lives in `design.md`.

## Layers

```
data/*.json          what exists: parts, rarities, finishes, traits, boxes (tune here, not in code)
scripts/core/        generic helpers with no game rules (Catalog loads data/, Weighted picks)
scripts/pets/        pet rules and pet visuals (Pet, PetRoller, Collection, PetLook, PetView)
scripts/adventure/   adventure rules: runs, events, parties, rewards, rumours, the pet's voice
scripts/idle/        errands (Jobs): pure rules for idle jobs, see data/errands.json
scripts/dev/         debug-only: launch flags, test profiles, scripted test flows (DevDriver)
scripts/game_state   the player's progress + saving (autoload "GameState")
scripts/ui/          screens and widgets; they read GameState and call its functions
scripts/platform/    everything OS/compositor specific, behind WindowSource
scripts/home.gd      the window: switches layers, sizes the window, runs the desktop pet
```

Dependencies only point downwards: UI → GameState → pets → core → data. Nothing below the UI
knows the UI exists; state changes are announced with signals (`GameState.changed`,
`Collection.pets_added`, `Collection.active_changed`).

## Pets

- `Pet` is plain data (parts, finish, traits, stats, rarity) with `to_dict` / `from_dict`.
- `PetRoller` rolls pets like card packs: the rarity is rolled once with the box odds, one
  "signature" part gets that rarity, the others roll at or below it. The finish is a separate
  roll. So the odds shown on a box are exactly what you get (checked by `tests/test_core.gd`).
- `Collection` owns the pets, the active pet and the book counts (`part:<slot>:<id>`,
  `finish:<body>:<finish>`).
- `PetLook` is the placeholder art (pixel maps in code). Real art replaces `PetLook` only;
  `PetView` (draws a pet, blinking, squash, finish shader) and everything above stay the same.
- Finish effects are one shader, `shaders/finish.gdshader`; `finishes.json` picks the mode.

## Screens

`home.gd` holds two layers inside one window:

- `CompactView` - the small idle panel (active pet opening packs, needs, feed / pat / let out).
- `ExpandedView` - the full game: the `Spine` of tabs and the page. Tabs: `HomeTab` (the pet's
  room), `BoxesTab` (shop, `PackOpening` for one box, `BoxReveal` grid for many),
  `CollectionTab` (pets grid + `PetDetails`, and the `BookView`), `AdventuresTab` (`MapView`,
  the place card, trip cards, and `TrailView` for watching a trip), `ErrandsTab` (the corkboard of
  jobs), `InventoryTab` (the bag and sewing) and `SettingsTab` (general and video pages).
  Tabs can be locked or hidden until something opens them (`data/unlocks.json`).
- The full game is laid out at 920x600 (`home.gd` `EXPANDED_SIZE`) and scaled to the chosen
  resolution with `content_scale_factor`, never past what fits the screen. Nothing may need more
  room than that: long one-line labels shrink with "…" or wrap (checked by `expect fits`).

`scripts/ui/reveal/` is the single-box ritual: `PackOpening` runs the steps (land, rip, light
climb, peek, pull, mist, celebration, result) and owns input and timing; `CardPack`,
`RevealEffects` (stacking effect layers named in `data/reveal.json`), `RevealBlocker` (the mist)
and `RevealResult` only draw. Every tween goes through `PackOpening._tween()` so the reveal
speed setting and skipping apply to all of it.

A new tab is a new Control added in `ExpandedView._init`. Shared colours, the Theme and small
widget helpers live in `UiTheme`.

## Platform

`WindowSource` is the only place that talks to the OS or compositor about windows:
where other windows are, fullscreen apps, the mouse, placing the overlay, sizing the home window
and the UI scale. The base class has plain Godot fallbacks; `HyprlandWindowSource` does it through
`hyprctl` (window rules can't be used because Godot sets titles after windows open, so it styles
our windows with direct dispatches). The Windows port adds a `WindowsWindowSource` backed by a
small GDExtension; nothing else should need to change.

## Saving

`GameState` saves to `user://save.json` every 30 s, after opening boxes and on quit. The file
has a `version`; `GameState._migrate` upgrades older files step by step, so bump
`SAVE_VERSION` and add a migration step whenever the format changes.

## Testing

- `godot --headless -s tests/test_core.gd` - data sanity, box odds over 100k rolls, save round
  trip, adventures, errands.
- `godot --headless -s tools/balance.gd` - what every place pays per minute, and errands for
  crews of 1 to 1000.
- `python3 tools/play.py <flow>` - plays `tests/flows/<flow>.flow` in a test profile (its own save
  and settings, window parked off-screen), prints the log and saves screenshots. Steps are listed
  in `DevDriver`; `expect fits` checks the full game fits its window. Test saves: `tests/saves/`.
- A headless script check must use a profile: `godot --headless --quit-after 30 -- --profile=check`
  (without one it loads and saves the real save).
- `godot -s tests/look_sheet.gd -- out.png` - renders every part and finish into one picture.
- Debug launch flags (`DevArgs`): `godot . -- --expanded --tab=collection --book --open=starter:10`,
  and `--open=starter:1 --force=mythic --autoplay` to watch a reveal at any rarity hands-free.
- `python3 tools/film.py <out_dir> <name> "<godot args>" 1.5 3 5` - launches the game on Hyprland
  and screenshots its window at those times (combine with `--autoplay` to check animations).
