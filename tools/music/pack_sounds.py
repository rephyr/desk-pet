#!/usr/bin/env python3
"""Every sound of opening one pack (except the tear, a recording), made in LMMS.

The idea: when the strip comes off the pack breathes out (a soft airy shimmer) and a hum starts
inside it. The hum is the base; each rarity step the light climbs adds a layer on top, all in F
major at 100 bpm and locked together (the game plays them with AudioStreamSynchronized):

    air        the pack breathing: shaped noise and a few crystal glints      (from the rip)
    hum        a humming voice and a warm pad                                 (from the rip)
    uncommon   a celesta twinkling                                            (1st step)
    rare       pizzicato bouncing, soft strings                               (2nd step)
    epic       choir, harp running up, timpani                                (3rd step)
    legendary  brass swelling, glockenspiel tune                              (4th step)
    mythic     a low bell and a shimmer that's slightly wrong                 (5th step)
    hold       tremolo strings on C7 (wants to resolve)                       (pulling the pet out)

Each step also plays a little rising harp chime (step_1..5), and the reveal plays the rarity's
fanfare (reveal_<rarity>): it resolves the held C7 to F, from a music-box ta-da (common) to the
whole orchestra (legendary); mythic takes a detour through D flat on the way. "finish" is the
sparkle for a special finish.

    python3 tools/music/pack_sounds.py            writes assets/sounds/pack/*.ogg and previews
    python3 tools/music/pack_sounds.py --preview  only remixes the previews

The LMMS projects land in tools/music/pack/ (open them in LMMS to listen or tinker; running this
again writes over them). Previews of a whole opening per rarity, at 1x reveal speed with a hand
like --autoplay, land in assets/sounds/_preview/ (Godot ignores that folder).
"""
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lmms import BAR, BEAT, RATE, Track, db, drum, limit, loudness, project, read, render, render_tracks, trim_tail, write_ogg, write_wav  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).resolve().parent / "pack"
OUT = ROOT / "assets" / "sounds" / "pack"
PREVIEW = ROOT / "assets" / "sounds" / "_preview"
WORK = SRC / "_work"

BPM = 100
LOOP_BARS = 4
LOOP_SECONDS = LOOP_BARS * 4 * 60.0 / BPM
LOOP_FRAMES = round(LOOP_SECONDS * RATE)
E = BEAT // 2  # an eighth
S = BEAT // 4  # a sixteenth
T = BEAT // 3  # an eighth-note triplet
RARITIES = ["common", "uncommon", "rare", "epic", "legendary", "mythic"]
LAYERS = ["air", "hum", "uncommon", "rare", "epic", "legendary", "mythic", "hold"]

# how loud each loop layer is on its own (LUFS): the breath stays in the background, the hum is
# clear, and every layer after it is loud enough to hear it arrive
LOOP_LOUDNESS = {"air": -31.0, "hum": -24.0, "uncommon": -26.5, "rare": -26.0, "epic": -25.0,
                 "legendary": -24.0, "mythic": -26.0, "hold": -25.0}
REVEAL_LOUDNESS = {"common": -21.0, "uncommon": -20.0, "rare": -18.5, "epic": -17.0, "legendary": -15.5, "mythic": -15.0}
STEP_LOUDNESS = -21.0
FINISH_LOUDNESS = -19.0

# the loop's chords, one a bar: F, F, Bb over F, F
IS_BB = [False, False, True, False]


# ---- the loop layers ----------------------------------------------------------------

def loops() -> list:
    t = {
        "air-crystal": Track("air-crystal", 98, vol=38, reverb=0.9, pan=20),
        "hum-oohs": Track("hum-oohs", 53, vol=74, reverb=0.6),
        "hum-pad": Track("hum-pad", 89, vol=58, reverb=0.5),
        "uncommon-celesta": Track("uncommon-celesta", 8, vol=52, reverb=0.7, pan=-20),
        "rare-pizz": Track("rare-pizz", 45, vol=66, reverb=0.4),
        "rare-strings": Track("rare-strings", 48, vol=44, reverb=0.6, pan=15),
        "epic-choir": Track("epic-choir", 52, vol=50, reverb=0.7),
        "epic-harp": Track("epic-harp", 46, vol=50, reverb=0.6, pan=-25),
        "epic-timpani": Track("epic-timpani", 47, vol=64, reverb=0.5),
        "legendary-brass": Track("legendary-brass", 61, vol=46, reverb=0.6),
        "legendary-glock": Track("legendary-glock", 9, vol=50, reverb=0.7, pan=25),
        "mythic-bell": Track("mythic-bell", 14, vol=52, reverb=0.8),
        "mythic-shimmer": Track("mythic-shimmer", 102, vol=34, reverb=0.9, pan=-30),
        "mythic-voice": Track("mythic-voice", 54, vol=36, reverb=0.8, pan=30),
        "hold-tremolo": Track("hold-tremolo", 44, vol=56, reverb=0.5),
        "hold-timpani": Track("hold-timpani", 47, vol=40, reverb=0.4),
    }
    glock_tune = [["C6", "D6", "F6", "G6"], ["A6", "G6", "F6", "D6"], ["D6", "F6", "Bb6", "A6"], ["G6", "F6", "E6", "F6"]]
    # three times round: the middle pass is cut out as the loop, so every tail rings into it
    for rep in range(3):
        for bar in range(LOOP_BARS):
            at = (rep * LOOP_BARS + bar) * BAR
            bb = IS_BB[bar]
            # air: a glint now and then
            if bar % 2 == 0:
                t["air-crystal"].add("F6" if bar == 0 else "C7", at + BEAT, 2 * BEAT, 60)
            # hum: the voice hums F and C (D over the Bb), the pad holds the low F
            t["hum-oohs"].add("F3", at, BAR, 78)
            t["hum-oohs"].add("D4" if bb else "C4", at, BAR, 70)
            t["hum-pad"].add("F2 C3", at, BAR, 72)
            # uncommon: celesta eighths
            arp = ["F5", "Bb5", "D6", "F6", "D6", "Bb5", "F5", "D6"] if bb else ["F5", "A5", "C6", "F6", "E6", "C6", "A5", "C6"]
            for i, n in enumerate(arp):
                t["uncommon-celesta"].add(n, at + i * E, E, 74 if i % 2 == 0 else 60)
            # rare: pizzicato bounce, strings held
            bass = ["Bb2", "F3", "Bb2", "F3"] if bb else ["F2", "C3", "F2", "C3"]
            for i, n in enumerate(bass):
                t["rare-pizz"].add(n, at + i * BEAT, E, 84 if i == 0 else 66)
            t["rare-strings"].add("F4 Bb4" if bb else "F4 A4", at, BAR, 64)
            # epic: choir chords, harp running up every beat, timpani on the one
            t["epic-choir"].add("F4 Bb4 D5" if bb else "F4 A4 C5", at, BAR, 66)
            tones = ["F4", "Bb4", "D5", "F5", "Bb5", "D6", "F6"] if bb else ["F4", "A4", "C5", "F5", "A5", "C6", "F6"]
            for beat in range(4):
                for i in range(4):
                    t["epic-harp"].add(tones[min(beat + i, len(tones) - 1)], at + beat * BEAT + i * S, S * 2, 62 + i * 6)
            t["epic-timpani"].add("F2" if not bb else "Bb1", at, BEAT, 80)
            if bar % 2 == 1:
                t["epic-timpani"].add("C2", at + 2 * BEAT, BEAT, 60)
            # legendary: brass swells, glockenspiel tune
            t["legendary-brass"].add("F3 C4 F4 A4" if not bb else "F3 Bb3 D4 F4", at, BAR, 60)
            for i, n in enumerate(glock_tune[bar]):
                t["legendary-glock"].add(n, at + i * BEAT, BEAT, 70)
            # mythic: a low bell every other bar, one of them a half step off; a shimmer that
            # rubs against it; a voice up high
            if bar == 0:
                t["mythic-bell"].add("F2", at, 2 * BAR, 76)
            if bar == 2:
                t["mythic-bell"].add("Gb2", at, 2 * BAR, 60)
            t["mythic-shimmer"].add("C6 Db6", at + 2 * BEAT, 2 * BEAT, 50)
            t["mythic-voice"].add("A5" if not bb else "Bb5", at, BAR, 60)
            # hold: tremolo strings on C7, a soft timpani roll on C
            t["hold-tremolo"].add("C3 E3 G3 Bb3 C4", at, BAR, 70)
            for i in range(16):
                t["hold-timpani"].add("C2", at + i * S, S, 44 + (i % 4 == 0) * 10)
    return list(t.values())


def air_noise() -> np.ndarray:
    """The pack breathing out: pinkish noise between about 400 Hz and 7 kHz that swells twice a
    loop. Shaped in the frequency domain, so it repeats seamlessly."""
    rng = np.random.default_rng(7)
    n = LOOP_FRAMES
    out = np.zeros((n, 2), dtype=np.float32)
    freqs = np.fft.rfftfreq(n, 1.0 / RATE)
    shape = np.where(freqs > 0, 1.0 / np.sqrt(np.maximum(freqs, 1.0)), 0.0)
    shape *= 1.0 / (1.0 + (400.0 / np.maximum(freqs, 1.0)) ** 4)  # low cut
    shape *= 1.0 / (1.0 + (freqs / 7000.0) ** 4)  # high cut
    for ch in range(2):
        spectrum = (rng.normal(size=freqs.size) + 1j * rng.normal(size=freqs.size)) * shape
        out[:, ch] = np.fft.irfft(spectrum, n)
    out /= np.max(np.abs(out))
    swell = 0.65 + 0.35 * np.sin(np.linspace(0.0, 2.0 * 2.0 * np.pi, n, endpoint=False) - np.pi / 2)
    return out * swell[:, None] * 0.25


# ---- one-shots --------------------------------------------------------------------

def steps() -> dict:
    """step_1..5: a harp flick up to a higher note each time, with a glockenspiel ping on it."""
    scale = ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5", "G5", "A5", "Bb5", "C6", "D6", "E6", "F6", "G6", "A6", "Bb6", "C7"]
    targets = ["A5", "C6", "F6", "A6", "C7"]
    out = {}
    for i, target in enumerate(targets):
        harp = Track("harp", 46, vol=70, reverb=0.6)
        glock = Track("glock", 9, vol=58 + i * 4, reverb=0.7)
        top = scale.index(target)
        for j, n in enumerate(scale[top - 3:top + 1]):
            harp.add(n, j * (S // 2), BEAT, 70 + j * 6)
        glock.add(target, 3 * (S // 2), 2 * BEAT, 90)
        out[f"step_{i + 1}"] = ([harp, glock], 2)
    return out


def finish() -> dict:
    celesta = Track("celesta", 8, vol=70, reverb=0.8)
    glock = Track("glock", 9, vol=56, reverb=0.8, pan=20)
    kit = Track("triangle", 48, vol=60, bank=128, reverb=0.7)
    run = ["F7", "C7", "A6", "F6", "C6", "A5"]
    for i, n in enumerate(run):
        celesta.add(n, i * (S // 2), BEAT, 86 - i * 4)
        glock.add(n, i * (S // 2) + S, BEAT, 70 - i * 6)
    kit.add(drum(81), 0, 2 * BEAT, 80)  # open triangle
    celesta.add("F5 A5 C6", 4 * S, 2 * BEAT, 60)
    return {"finish": ([celesta, glock, kit], 2)}


def reveals() -> dict:
    out = {}
    # common: a music-box ta-da
    box = Track("music box", 10, vol=80, reverb=0.6)
    pizz = Track("pizz", 45, vol=64, reverb=0.4)
    celesta = Track("celesta", 8, vol=52, reverb=0.7)
    box.add("C6", 0, S, 80).add("F6", S + 4, 3 * BEAT, 90)
    pizz.add("F3", S + 4, BEAT, 90)
    celesta.add("F5 A5 C6", S + 4, 2 * BEAT, 60)
    out["reveal_common"] = ([box, pizz, celesta], 2)

    # uncommon: marimba and glockenspiel run up, a bright chord
    marimba = Track("marimba", 12, vol=72, reverb=0.5)
    glock = Track("glock", 9, vol=58, reverb=0.7, pan=20)
    pizz = Track("pizz", 45, vol=64, reverb=0.4)
    for i, n in enumerate(["C5", "F5", "A5", "C6", "F6"]):
        marimba.add(n, i * S, S * 2, 72 + i * 5)
        glock.add(n, i * S, S, 60 + i * 5)
    marimba.add("A5 C6 F6", 5 * S, 3 * BEAT, 90)
    glock.add("A6 F6", 5 * S, 3 * BEAT, 84)
    pizz.add("F2", 5 * S, BEAT, 90).add("F3", 5 * S + BEAT, BEAT, 70)
    out["reveal_uncommon"] = ([marimba, glock, pizz], 3)

    # rare: harp sweeps up into strings, a bell on top
    harp = Track("harp", 46, vol=70, reverb=0.6)
    strings = Track("strings", 48, vol=60, reverb=0.6)
    celesta = Track("celesta", 8, vol=56, reverb=0.7)
    timpani = Track("timpani", 47, vol=70, reverb=0.5)
    bell = Track("bell", 14, vol=48, reverb=0.8)
    sweep = ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5", "G5", "A5", "Bb5", "C6", "D6", "E6", "F6"]
    for i, n in enumerate(sweep):
        harp.add(n, i * 6, BEAT, 60 + i * 2)
    land = len(sweep) * 6
    strings.add("F3 C4 F4 A4 C5", land, 2 * BAR // 2 + BEAT, 80)
    celesta.add("F5 A5 C6 F6", land, 2 * BEAT, 76)
    timpani.add("F2", land, BEAT, 90)
    bell.add("F5", land, 2 * BAR // 2, 70)
    out["reveal_rare"] = ([harp, strings, celesta, timpani, bell], 4)

    # epic: a timpani roll builds, the harp sweeps, and choir and strings land together with a crash
    timpani = Track("timpani", 47, vol=72, reverb=0.5)
    harp = Track("harp", 46, vol=64, reverb=0.6)
    choir = Track("choir", 52, vol=62, reverb=0.7)
    strings = Track("strings", 48, vol=62, reverb=0.6)
    glock = Track("glock", 9, vol=56, reverb=0.8, pan=20)
    kit = Track("orchestra kit", 48, vol=62, bank=128, reverb=0.6)
    for i in range(16):
        timpani.add("C2", i * (S // 2 + 3), S, 40 + i * 4)
    land = 16 * (S // 2 + 3)
    for i, n in enumerate(sweep):
        harp.add(n, land - len(sweep) * 4 + i * 4, BEAT, 56 + i * 3)
    timpani.add("F2", land, BEAT, 100)
    choir.add("F3 A3 C4 F4 A4 C5", land, 6 * BEAT, 84)
    strings.add("F2 F3 C4 A4 F5", land, 6 * BEAT, 84)
    glock.add("F6 A6 C7", land, 2 * BEAT, 80)
    kit.add(drum(49), land, 4 * BEAT, 80)  # crash
    out["reveal_epic"] = ([timpani, harp, choir, strings, glock, kit], 5)

    # legendary: ta-ta-ta-TAAA, the whole orchestra
    trumpet = Track("trumpet", 56, vol=70, reverb=0.6)
    brass = Track("brass", 61, vol=62, reverb=0.6)
    choir = Track("choir", 52, vol=60, reverb=0.7)
    strings = Track("strings", 48, vol=62, reverb=0.6)
    timpani = Track("timpani", 47, vol=72, reverb=0.5)
    harp = Track("harp", 46, vol=60, reverb=0.6)
    glock = Track("glock", 9, vol=56, reverb=0.8, pan=25)
    kit = Track("orchestra kit", 48, vol=62, bank=128, reverb=0.6)
    for i in range(3):
        trumpet.add("C5", i * T, T - 2, 84)
        timpani.add("C2", i * T, T, 70)
    land = 3 * T
    trumpet.add("F5", land, BEAT + E, 96).add("A5", land + BEAT + E, E, 88).add("C6", land + 2 * BEAT, 5 * BEAT, 100)
    brass.add("F3 C4 F4 A4", land, 7 * BEAT, 90)
    choir.add("F4 A4 C5 F5", land, 7 * BEAT, 80)
    strings.add("F2 F3 C4 A4 C5", land, 7 * BEAT, 84)
    timpani.add("F2", land, BEAT, 110).add("F2", land + 2 * BEAT, BEAT, 90)
    for i, n in enumerate(sweep):
        harp.add(n, land + 2 * BEAT + i * 5, BEAT, 56 + i * 3)
    for i, n in enumerate(["F6", "A6", "C7", "F7", "C7", "A6", "F6", "A6"]):
        glock.add(n, land + 2 * BEAT + i * S, S * 2, 76)
    kit.add(drum(49), land, 4 * BEAT, 90).add(drum(57), land + 2 * BEAT, 4 * BEAT, 70)
    out["reveal_legendary"] = ([trumpet, brass, choir, strings, timpani, harp, glock, kit], 6)

    # mythic: the same call, but the answer lands somewhere strange (D flat), holds its breath,
    # and only then comes home to F, with a low bell and a shimmer that doesn't quite fit
    trumpet = Track("trumpet", 56, vol=70, reverb=0.7)
    brass = Track("brass", 61, vol=62, reverb=0.7)
    choir = Track("choir", 52, vol=64, reverb=0.8)
    strings = Track("strings", 48, vol=62, reverb=0.7)
    timpani = Track("timpani", 47, vol=72, reverb=0.6)
    bell = Track("bell", 14, vol=58, reverb=0.9)
    glock = Track("glock", 9, vol=56, reverb=0.9, pan=25)
    shimmer = Track("shimmer", 102, vol=40, reverb=0.9, pan=-30)
    kit = Track("orchestra kit", 48, vol=62, bank=128, reverb=0.7)
    for i in range(3):
        trumpet.add("C5", i * T, T - 2, 84)
        timpani.add("C2", i * T, T, 70)
    odd = 3 * T
    trumpet.add("Db5", odd, 3 * BEAT, 92)
    brass.add("Db3 Ab3 Db4 F4", odd, 3 * BEAT, 84)
    choir.add("Db4 F4 Ab4", odd, 3 * BEAT, 76)
    strings.add("Db2 Db3 Ab3 F4", odd, 3 * BEAT, 80)
    timpani.add("Db2", odd, BEAT, 100)
    kit.add(drum(49), odd, 3 * BEAT, 70)
    home = odd + 3 * BEAT
    for i in range(6):
        timpani.add("C2", home - 6 * (S // 2) + i * (S // 2), S // 2, 60 + i * 8)
    trumpet.add("C5", home - E, E, 80).add("F5", home, BEAT, 100).add("A5", home + BEAT, BEAT, 96).add("C6", home + 2 * BEAT, 6 * BEAT, 104)
    brass.add("F3 C4 F4 A4 C5", home, 8 * BEAT, 96)
    choir.add("F4 A4 C5 F5 A5", home, 8 * BEAT, 86)
    strings.add("F2 F3 C4 A4 F5", home, 8 * BEAT, 90)
    timpani.add("F2", home, BEAT, 120).add("F1", home + 4 * BEAT, 2 * BEAT, 80)
    bell.add("F3", home, 8 * BEAT, 90).add("F2", home + 4 * BEAT, 8 * BEAT, 70)
    for i, n in enumerate(["F6", "A6", "C7", "F7", "A7", "F7", "C7", "A6", "F6", "C7", "F7", "C7"]):
        glock.add(n, home + BEAT + i * S, S * 2, 70)
    shimmer.add("C7 Db7", home + 4 * BEAT, 4 * BEAT, 40)
    kit.add(drum(49), home, 6 * BEAT, 96).add(drum(57), home + 2 * BEAT, 6 * BEAT, 76)
    out["reveal_mythic"] = ([trumpet, brass, choir, strings, timpani, bell, glock, shimmer, kit], 8)
    return out


# ---- making the files -------------------------------------------------------------

def make_loops() -> dict:
    tracks = loops()
    (SRC / "loops.mmp").write_text(project(tracks, BPM, LOOP_BARS * 3))  # all of it, for LMMS
    stems = render_tracks(tracks, BPM, LOOP_BARS * 3, WORK / "loops")
    layers = {name: np.zeros((LOOP_FRAMES, 2), dtype=np.float32) for name in LAYERS}
    for track, path in stems.items():
        a = read(path)
        middle = a[LOOP_FRAMES:2 * LOOP_FRAMES]
        layers[track.split("-")[0]][:len(middle)] += middle
    layers["air"] += air_noise()
    for name in LAYERS:
        layers[name] = layers[name] * db(LOOP_LOUDNESS[name] - loudness(np.tile(layers[name], (2, 1)), WORK))
    for name, a in layers.items():
        write_ogg(OUT / f"loop_{name}.ogg", a, WORK)
    # how loud the stack gets, layer by layer
    stack = np.zeros_like(layers["hum"])
    for name in LAYERS:
        stack = stack + layers[name]
        print(f"  loop {name:10s} alone {loudness(np.tile(layers[name], (2, 1)), WORK):6.1f} LUFS, stack so far {loudness(np.tile(stack, (2, 1)), WORK):6.1f}")
    return layers


def make_one_shot(name: str, tracks: list, bars: int, target: float) -> np.ndarray:
    mmp = SRC / f"{name}.mmp"
    mmp.write_text(project(tracks, BPM, bars))
    wav = WORK / f"{name}.wav"
    render(mmp, wav)
    a = trim_tail(read(wav))
    a = limit(a * db(target - loudness(a, WORK)))
    write_ogg(OUT / f"{name}.ogg", a, WORK)
    return a


def make_one_shots() -> None:
    jobs = []
    for name, (tracks, bars) in steps().items():
        jobs.append((name, tracks, bars, STEP_LOUDNESS))
    for name, (tracks, bars) in finish().items():
        jobs.append((name, tracks, bars, FINISH_LOUDNESS))
    for name, (tracks, bars) in reveals().items():
        jobs.append((name, tracks, bars, REVEAL_LOUDNESS[name.removeprefix("reveal_")]))
    with ThreadPoolExecutor(max_workers=8) as pool:
        for name, a in zip([j[0] for j in jobs], pool.map(lambda j: make_one_shot(*j), jobs)):
            print(f"  {name:18s} {len(a) / RATE:4.1f} s")


# ---- previews: a whole opening per rarity --------------------------------------------

def decode(path: Path) -> np.ndarray:
    tmp = WORK / (path.stem + ".dec.wav")
    import subprocess
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(path), "-ar", str(RATE), "-ac", "2", str(tmp)], check=True)
    a = read(tmp)
    tmp.unlink()
    return a


def previews() -> None:
    """The same steps PackOpening goes through at 1x speed, with --autoplay's hand."""
    import json
    reveal = json.loads((ROOT / "data" / "reveal.json").read_text())
    tear = decode(ROOT / "assets" / "sounds" / "pack" / "tear.ogg")
    loops_ = {n: decode(OUT / f"loop_{n}.ogg") for n in LAYERS}
    PREVIEW.mkdir(parents=True, exist_ok=True)
    (PREVIEW / ".gdignore").touch()
    for rank, rarity in enumerate(RARITIES):
        land, rip = 0.45, 1.65
        events = []  # (time, layer, fade seconds) for loops coming in
        shots = [(0.6, tear)]
        events += [(rip, "air", 0.3), (rip + 0.2, "hum", 1.2)]
        t = rip
        for r in range(1, rank + 1):
            t += float(reveal["tiers"][RARITIES[r]]["pause"])
            events.append((t, LAYERS[r + 1], float(reveal["layer_fade"])))
            shots.append((t, decode(OUT / f"step_{r}.ogg")))
            t += float(reveal["color_fade"])
        t += 0.35
        events.append((t, "hold", 2.5))
        t += 0.35 + 1.2 + 0.22
        if rarity == "mythic":  # the mist
            t += 1.2 + 0.4
        stinger = decode(OUT / f"reveal_{rarity}.ogg")
        shots.append((t, stinger))
        end = t + len(stinger) / RATE + 0.5
        n = int(end * RATE)
        mix = np.zeros((n, 2), dtype=np.float32)
        for at, a in shots:
            i = int(at * RATE)
            m = min(len(a), n - i)
            mix[i:i + m] += a[:m]
        stop = int(t * RATE)
        out_fade = np.clip(1.0 - (np.arange(n) - stop) / (0.9 * RATE), 0.0, 1.0)
        for at, layer, fade in events:
            start = int(at * RATE)
            env = np.clip((np.arange(n) - start) / max(1.0, fade * RATE), 0.0, 1.0) * out_fade
            looped = np.tile(loops_[layer], (n // LOOP_FRAMES + 2, 1))
            begin = int(rip * RATE)  # every loop starts at the rip, in sync
            body = np.zeros((n, 2), dtype=np.float32)
            body[begin:] = looped[:n - begin]
            mix += body * env[:, None]
        write_ogg(PREVIEW / f"opening_{rank + 1}_{rarity}.ogg", limit(mix, -0.5), WORK)
        print(f"  preview {rarity:9s} {end:4.1f} s")


if __name__ == "__main__":
    SRC.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    if "--preview" not in sys.argv:
        print("loops:")
        make_loops()
        print("one-shots:")
        make_one_shots()
    print("previews:")
    previews()
