// The game frame for screen mockups, plus the player's look (colours, font, icons).
// The look is remembered in this browser, so picking it in settings changes every mockup page.
// URL params (?theme=&font=&icons=) win, for screenshots.

const LOOK_KEY = "deskpets-look-v2";
const LOOK_DEFAULT = { theme: "plum", font: "coiny", icons: "doodle" };

function loadLook() {
  let saved = {};
  try { saved = JSON.parse(localStorage.getItem(LOOK_KEY) || "{}"); } catch (e) { saved = {}; }
  const look = { ...LOOK_DEFAULT, ...saved };
  const params = new URLSearchParams(location.search);
  for (const key of Object.keys(LOOK_DEFAULT)) if (params.get(key)) look[key] = params.get(key);
  return look;
}

function applyLook(look) {
  const root = document.documentElement;
  root.dataset.theme = look.theme;
  root.dataset.font = look.font;
  root.dataset.icons = look.icons;
  try { localStorage.setItem(LOOK_KEY, JSON.stringify(look)); } catch (e) { /* private window: fine */ }
  paintIcons();
}

// set the look before the page is drawn, so it never flashes the default theme first
(() => {
  const look = loadLook(), root = document.documentElement;
  root.dataset.theme = look.theme; root.dataset.font = look.font; root.dataset.icons = look.icons;
  requestAnimationFrame(() => requestAnimationFrame(() => root.classList.add("ready")));
})();

const TABS = [
  { id: "home", label: "home", icon: "home" },
  { id: "boxes", label: "boxes", icon: "boxes", news: true },
  { id: "pets", label: "pets", icon: "collection" },
  { id: "trips", label: "trips", icon: "adventures" },
  { id: "errands", label: "errands", icon: "errands" },
  { id: "gear", label: "gear", icon: "upgrades" },
  { id: "inventory", label: "bag", icon: "inventory" },
];

// One tiny dim star per pet that never came back, tinted from that pet. Never explained, never counted.
function stars(count = 26) {
  const tints = ["#c9a0ff", "#ffb59a", "#8fe8c0", "#8cc8ff", "#ff8fc8", "#f5dcec"];
  let seed = 7;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  let out = "";
  for (let i = 0; i < count; i++) {
    const x = Math.floor(rnd() * 74) + 2, y = Math.floor(rnd() * 590) + 4;
    out += `<rect x="${x}" y="${y}" width="1" height="1" fill="${tints[i % tints.length]}" opacity="${(0.25 + rnd() * 0.35).toFixed(2)}"/>`;
  }
  return out;
}

// Builds the window into <div class="app" data-tab="settings" data-say="...">. Returns #content.
function mountFrame() {
  const app = document.querySelector(".app");
  const active = app.dataset.tab;
  // early game: only the tabs found so far (data-tabs="boxes,pets"); data-nopet="1" before the first pet
  const shown = app.dataset.tabs ? app.dataset.tabs.split(",") : null;
  const tab = t => t.locked
    ? `<button class="tab locked" title="found on a trip"><span data-icon="${t.icon}"></span>${t.label}</button>`
    : `<a class="tab${t.id === active ? " on" : ""}" href="${t.id}.html"><span data-icon="${t.icon}"></span>${t.label}${t.news ? `<span class="new" title="something new"></span>` : ""}</a>`;
  app.innerHTML = `
    <nav class="spine">
      <svg class="sky" width="80" height="600" aria-hidden="true">${stars()}</svg>
      <div class="moon" title="${app.dataset.nopet ? "your pet will sit here" : "lilac blob, your active pet"}">${app.dataset.nopet ? `<span class="empty-seat"></span>` : `<img class="px" src="../assets/pets/lilac-blob.png" alt="lilac blob">`}</div>
      ${TABS.filter(t => !shown || shown.includes(t.id)).map(tab).join("")}
      <div class="grow"></div>
      ${tab({ id: "settings", label: "", icon: "settings" })}
    </nav>
    <main class="page dots">
      <div class="top">
        <div class="bubble">${app.dataset.say || ""}</div>
        <span class="chip coins"><span data-icon="coin"></span>10,421</span>
        <span class="chip xp"><span data-icon="xp"></span>72</span>
        <div class="winbtns"><button title="shrink">▾</button><button title="close">✕</button></div>
      </div>
      <div id="content">${app.innerHTML}</div>
    </main>`;
  return document.getElementById("content");
}
