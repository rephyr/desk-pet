# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

The shipped game is a native desktop app (Godot 4.7, Linux first, then Windows, sold on Steam).
The web platform applies only to the browser mockups in `design/mockups/`, which are the visual
reference the Godot screens are built from. Nothing web-based ships.

## Stack

delegated: plain static HTML/CSS, one self-contained file per screen in `design/mockups/`, no
build step, so each mockup opens straight in a browser and reads easily when porting to Godot.

## Users

- **Idle/incremental fans**: like numbers going up, automation ladders and checking in a few
  times a day.
- **Pack-opening / TCG fans**: love the rip, the glow and the rare pull, and chase a collection
  book.
- **Cozy desktop-pet people**: want a cute companion living on their screen while they work or
  play.
- **Desk workers**: at a computer all day, want something small and non-intrusive on the side.

All four are the same player at different moments: the game sits quietly on the desktop most
of the day and gets focused attention in short sessions.

## Product Purpose

Desk Pets is an idle collecting game that lives on the desktop. You open loot boxes like card
packs, collect pets built from random parts in rare variations, and chase an extremely rare pet
over months. One active pet walks on your windows; behind it, more and more pets go on
adventures to fund the next pulls. Not all of them come back. Success is a player who keeps the
game open all day, checks in because it is always rewarding (never because it punishes absence),
and keeps chasing the collection for months.

## Positioning

A cute desktop pet on the outside, with a TCG pack-opening ritual and an idle adventure game
underneath, plus a dark sacrificial twist that the game itself never acknowledges. The darkness
grows only from what the player chooses to do.

## Operating Context

The game has three layers, each a real OS window:
- **Desktop pet**: a see-through overlay; the pet walks on top of other windows.
- **Home panel**: a small pinned corner panel (300x318) with the pet, food/mood and a
  few buttons. Always on top, hides while something is fullscreen.
- **Expanded view**: the full game (920x600, drawn at 1.5x on the 4K screen) with tabs: home (the pet's room), boxes,
  collection, adventures, errands, inventory, settings, and more unlocked through play. The
  layout is 920x600 and scales up to the chosen resolution; nothing may spill past the window.

Sessions: glanced at all day while working; opened for short focused sessions (opening packs,
trips on the trail, grafting).

## Capabilities and Constraints

- Mockups use the game's window sizes above.
- Mockups use only looks Godot can reproduce: rounded boxes, borders, glow and drop shadows,
  flat colour, drawn doodles, and crisp pixel art (nearest-neighbour scaling). No backdrop blur,
  glass or CSS-only effects the game can't match.
- Pixel art pets built from layered parts (`art/parts/`, data in `data/`).
- Tabs and features unlock through play. Mockups may show a screen fully unlocked.
- Packs are earned in game only; nothing is ever sold for real money.
- Terminology: pets, parts, boxes/packs, trips/adventures, errands, grafting, the trail, xp,
  coins (◆), finds, rumours, the map.

## Brand Commitments

- **No fixed colour scheme.** The game may offer several colour themes, light and dark; the
  scheme is a design choice still being explored, not a brand rule.
- **The game never winks.** Everything is cute and upbeat at every depth. No text, sound or UI
  acknowledges that anything is dark. Never graphic (target about PEGI 12).
- **The active pet narrates** in short, lowercase, sincere speech bubbles and never shows odds.
- Name: Desk Pets. Current fonts in the game are Coiny (titles) and Maple Mono (text).

## Evidence on Hand

- The running game (`godot .`); screenshots are taken with `tools/film.py`.
- Current colours and fonts: `scripts/ui/ui_theme.gd`.
- Game design and decisions: `docs/design.md` (this is the game design doc, not a visual
  design system).
- No real art yet beyond the pixel-art pet parts; no sound, no store page, no testimonials.

## Product Principles

1. **Checking in is always rewarded, never required.** Active play advances faster than idling;
   absence never costs a pet.
2. **The pull is the heart.** Anything that leads to opening packs or showing off a pull gets
   the most care.
3. **Stay out of the way.** Small and quiet on the desktop, rich only when the player opens it.
4. **Discovery over explanation.** Features appear when found; the pet hints instead of
   tutorials and numbers.
5. **Cute surface, choices underneath.** The mood darkens only through what the player does.
