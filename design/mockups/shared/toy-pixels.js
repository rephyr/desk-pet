// Pixel-art versions of the capsule toys (14 x 14, like the pets' chunky pixels), for the toy
// design sheet. Letters are colours from TOY_PAL; "." is empty. The stand is drawn separately.

const TOY_PAL = {
  o: "#1a0f22", w: "#f5dcec", W: "#c9b3c2",
  p: "#ff79c6", P: "#a64f81", m: "#8fe8c0", M: "#4f9d80",
  g: "#ffe08a", G: "#b8914a", c: "#8be9fd", C: "#4fa9c9",
  l: "#c9a0ff", L: "#7d62a3", k: "#f3c4b4", b: "#8a6448", B: "#5c4130",
};

const TOY_PIXELS = {
  snail: [
    "..............",
    "..o...o.......",
    "..m...m.oooo..",
    "..m...m.oppppo",
    "..mm.mmopPooPo",
    "...mmm.opopPpo",
    "...mmm.opoPppo",
    "...mmmopPoopPo",
    "..mmmmmoppppo.",
    ".mmmmmmmoooo..",
    ".mwmmwmmmmmmo.",
    ".MmmmmmmmmmMo.",
    "..oooooooooo..",
    "..............",
  ],
  ladybug: [
    "....o....o....",
    ".....o..o.....",
    "....oooooo....",
    "...oowoowoo...",
    "..opppoopppo..",
    ".opppPoPpppPo.",
    ".opooppopooPo.",
    ".oppppoppppPo.",
    ".oppoopoppoPo.",
    ".opppPoPpppPo.",
    "..oppPoPppPo..",
    "...oooooooo...",
    "..............",
    "..............",
  ],
  mushroom: [
    "....oooooo....",
    "..oolllwllloo.",
    ".olwwlllllwwlo",
    ".ollllwwllllLo",
    "olwwllwwlllwLo",
    "olwwlllllllLLo",
    ".oLLLLLLLLLLo.",
    "..oooWWWWooo..",
    ".....owwwo....",
    ".....owowo....",
    ".....owwwo....",
    ".....oWwWo....",
    "......ooo.....",
    "..............",
  ],
  acorn: [
    "......oo......",
    "......Bo......",
    "...oooBBooo...",
    "..obBbBbBbBo..",
    ".obBbBbBbBbBo.",
    ".oBBBBBBBBBBo.",
    "..oggggggggo..",
    "..ogwgggggGo..",
    "..ogwgggggGo..",
    "..oggggggGGo..",
    "...ogggggGo...",
    "....ogggGo....",
    ".....oooo.....",
    "..............",
  ],
  bee: [
    "...oo....oo...",
    "..owwo..owwo..",
    "..owWwoowWwo..",
    "...owwoowwo...",
    "....ooooooo...",
    "..oggoggoggo..",
    ".oggoooggoogo.",
    "ogwgoggoggowgo",
    "oggoooggoooggo",
    ".oggoggoggogo.",
    "..oGGoGGoGGo..",
    "...oooooooo...",
    "..............",
    "..............",
  ],
  frog: [
    "...ooo..ooo...",
    "..omwmo.omwmo.",
    "..omoom.omoom.",
    "..ommmooommmo.",
    ".ommmmmmmmmmmo",
    ".ommmmmmmmmmmo",
    ".opmmmmmmmmpmo",
    ".ommoommmoommo",
    ".ommmooooommMo",
    "..ommmmmmmmMo.",
    ".omMmo...omMmo",
    ".oooo.....ooo.",
    "..............",
    "..............",
  ],
  gnome: [
    "........o.....",
    ".......opo....",
    "......oppo....",
    ".....opppPo...",
    "....oppppPo...",
    "...opppppPPo..",
    "..oooooooooo..",
    "...okkkkkko...",
    "...okokkoko...",
    "..owkkppkkwo..",
    "..owwwwwwwwo..",
    ".occwwwwwwcco.",
    ".occcwwwwccCo.",
    "..oooooooooo..",
  ],
  moth: [
    "..............",
    ".ooo..oo..ooo.",
    "ollloo..oollLo",
    "olglllowolllgo",
    "ollllLowoLlllo",
    ".olllLowoLllo.",
    "..ollLowoLlo..",
    "..oLLLowoLLLo.",
    ".oLLlLowoLlLLo",
    ".oLlLo.o.oLlLo",
    "..ooo.....ooo.",
    "..............",
    "..............",
    "..............",
  ],
};

// the toy as a data URL image, `scale` screen pixels per art pixel
function toyPixelUrl(id, scale = 6) {
  const rows = TOY_PIXELS[id];
  const c = document.createElement("canvas");
  c.width = 14 * scale; c.height = 14 * scale;
  const g = c.getContext("2d");
  rows.forEach((row, y) => [...row].forEach((ch, x) => {
    if (ch === ".") return;
    g.fillStyle = TOY_PAL[ch];
    g.fillRect(x * scale, y * scale, scale, scale);
  }));
  return c.toDataURL();
}
