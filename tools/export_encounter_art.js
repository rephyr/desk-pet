// Copies the encounter art from the mockups (design/mockups/shared/encounters/part*.js) into
// data/encounter_art.json for the game. Run after editing a sprite:
//   node tools/export_encounter_art.js
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const dir = path.join(root, "design/mockups/shared/encounters");
global.window = { ENCOUNTER_SPRITES: {} };
for (const f of fs.readdirSync(dir).filter(f => /^part\d+\.js$/.test(f)).sort())
  eval(fs.readFileSync(path.join(dir, f), "utf8"));
const out = {};
for (const [id, s] of Object.entries(window.ENCOUNTER_SPRITES).sort()) {
  const e = {};
  if (s.alias) e.alias = s.alias;
  if (s.pal) e.pal = s.pal;
  if (s.rows) e.rows = s.rows;
  if (s.glow) e.glow = true;
  if (s.eerie) e.eerie = true;
  if (s.flat) e.flat = true;
  if (s.float) e.float = Math.round(s.float / (s.px || 4));  // mockup px -> sprite pixels
  out[id] = e;
}
const note = "Pixel art for adventure events, shown on the trail just ahead of the pets while they wait at one (scripts/ui/encounter_art.gd). Made in the mockups (design/mockups/screens/encounters-all.html) and copied here by tools/export_encounter_art.js; edit it there. rows: '.' is empty, other letters are colours from pal. alias: use another event's art. glow / eerie: a cyan / pink-red glow. flat: no shadow. float: pixels off the ground.";
let json = JSON.stringify({ _note: note, art: out }, null, "\t");
// keep each sprite's rows on their own lines but the short bits compact
fs.writeFileSync(path.join(root, "data/encounter_art.json"), json + "\n");
console.log(Object.keys(out).length + " sprites -> data/encounter_art.json");
