#!/usr/bin/env python3
"""The home room loop: a sleepy music box over soft electric piano, for the pet's room at night.

Writes tools/music/home_room.mmp (an LMMS project: open it in LMMS to play with it by hand, but
running this again writes over it) and renders assets/music/home_room.ogg with LMMS. Instruments are General MIDI sounds from the
FluidR3 soundfont (sf2player). 16 bars at 84 bpm, loops seamlessly.

    python3 tools/music/home_room.py
"""
import subprocess
from pathlib import Path

BPM = 84
BAR = 192  # LMMS ticks in a 4/4 bar
E = BAR // 8  # an eighth
SWING = 5  # ticks the off-beat eighths lag, for a lazy feel
SF2 = "/usr/share/soundfonts/FluidR3_GM.sf2"

NOTE = {"C": 0, "Db": 1, "D": 2, "Eb": 3, "E": 4, "F": 5, "Gb": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11}


def key(name: str) -> int:
    """'A5' -> LMMS key (A4 = 57, like MIDI minus 12)."""
    pitch, octave = name[:-1], int(name[-1])
    return NOTE[pitch] + 12 * octave  # LMMS: C0 = 0, so A4 = 57 (MIDI is 12 higher)


def swung(pos: int) -> int:
    return pos + (SWING if (pos // E) % 2 == 1 and pos % E == 0 else 0)


# ---- the tune --------------------------------------------------------------------

# one chord per bar (two when split), low to high, for the piano
CHORDS = [
    [("F3 A3 C4 E4", 8)],
    [("A3 C4 E4 G4", 8)],
    [("Bb3 D4 F4 A4", 8)],
    [("C4 F4 G4 Bb4", 4), ("C4 E4 G4 Bb4", 4)],
    [("D4 F4 A4 C5", 8)],
    [("G3 Bb3 D4 F4", 8)],
    [("Bb3 D4 F4 A4", 4), ("Bb3 Db4 F4 G4", 4)],
    [("C4 F4 G4", 4), ("C4 E4 G4 Bb4", 4)],
]
ROOTS = ["F2", "A2", "Bb2", "C3", "D3", "G2", "Bb2", "C3"]
FIFTHS = ["C3", "E3", "F3", "G3", "A2", "D3", "F3", "G2"]

# the music box: (note or "-" for a rest, length in eighths), 8 eighths a bar
MELODY_A = [
    [("A5", 2), ("C6", 1), ("A5", 1), ("G5", 2), ("E5", 2)],
    [("E5", 3), ("G5", 1), ("A5", 4)],
    [("D6", 1), ("C6", 1), ("A5", 2), ("F5", 2), ("-", 2)],
    [("G5", 2), ("Bb5", 1), ("A5", 1), ("G5", 4)],
    [("F5", 1), ("A5", 1), ("C6", 2), ("A5", 1), ("C6", 1), ("D6", 2)],
    [("D6", 3), ("C6", 1), ("Bb5", 2), ("A5", 2)],
    [("A5", 2), ("F5", 2), ("Db6", 3), ("C6", 1)],
    [("C6", 4), ("-", 4)],
]
MELODY_B = [
    [("C6", 1), ("A5", 1), ("C6", 1), ("E6", 1), ("D6", 2), ("C6", 2)],
    [("E6", 3), ("D6", 1), ("C6", 2), ("A5", 2)],
    [("D6", 1), ("F6", 1), ("D6", 1), ("C6", 1), ("A5", 4)],
    [("Bb5", 2), ("A5", 1), ("G5", 1), ("E5", 2), ("G5", 2)],
    [("A5", 2), ("C6", 2), ("F6", 3), ("E6", 1)],
    [("D6", 2), ("Bb5", 2), ("C6", 1), ("D6", 1), ("F6", 2)],
    [("D6", 2), ("C6", 2), ("Db6", 2), ("Bb5", 2)],
    [("G5", 2), ("A5", 1), ("C6", 1), ("-", 4)],
]


def piano() -> list:
    notes = []
    for rep in range(2):
        for bar, chords in enumerate(CHORDS):
            at = (rep * 8 + bar) * BAR
            for chord, eighths in chords:
                # a soft stab on the beat, then held from the "and" of 2 (a little push)
                for i, n in enumerate(chord.split()):
                    if eighths == 8:
                        notes.append((key(n), at + i * 2, 3 * E - 4, 62))
                        notes.append((key(n), swung(at + 3 * E) + i * 2, 5 * E - 6, 52))
                    else:
                        notes.append((key(n), at + i * 2, eighths * E - 6, 60))
                at += eighths * E
    return notes


def bass() -> list:
    notes = []
    for rep in range(2):
        for bar in range(8):
            at = (rep * 8 + bar) * BAR
            notes.append((key(ROOTS[bar]), at, 3 * E, 90))
            notes.append((key(FIFTHS[bar]), swung(at + 5 * E), 2 * E, 70))
            if bar % 2 == 1:
                notes.append((key(ROOTS[bar]), at + 7 * E + SWING, E, 60))
    return notes


def melody() -> list:
    notes = []
    for rep, part in enumerate([MELODY_A, MELODY_B]):
        for bar, line in enumerate(part):
            at = (rep * 8 + bar) * BAR
            assert sum(l for _, l in line) == 8, f"bar {bar + 1} of part {rep} isn't 8 eighths"
            for n, length in line:
                if n != "-":
                    notes.append((key(n), swung(at), length * E - 4, 84 if (at % BAR) == 0 else 74))
                at += length * E
    return notes


def sparkles() -> list:
    """A kalimba answering the music box in the second half: little arpeggios every other bar."""
    notes = []
    for bar in range(8):
        if bar % 2 == 0:
            continue
        at = (8 + bar) * BAR + 4 * E
        tones = CHORDS[bar][-1][0].split()[-3:]
        for i, n in enumerate(tones):
            notes.append((key(n) + 12, swung(at + i * E), 2 * E, 52 + i * 4))
    return notes


def drums() -> list:
    kick, stick, shaker = 36 - 12, 37 - 12, 70 - 12  # General MIDI drum notes, as LMMS keys
    notes = []
    for bar in range(16):
        at = bar * BAR
        notes.append((kick, at, E, 70))
        notes.append((kick, swung(at + 5 * E), E, 45))
        if bar % 4 == 3:
            notes.append((kick, at + 6 * E, E, 40))
        for beat in (2, 6):
            notes.append((stick, at + beat * E, E, 55))
        for i in range(8):
            notes.append((shaker, swung(at + i * E), E, 34 if i % 2 else 48))
    return notes


# ---- the project -----------------------------------------------------------------

def track(name: str, bank: int, patch: int, vol: int, notes: list, reverb: float, pan: int = 0) -> str:
    rev = f'reverbOn="{1 if reverb > 0 else 0}" reverbLevel="{reverb}" reverbRoomSize="0.7" reverbDamping="0.4" reverbWidth="0.9"'
    body = "\n".join(f'        <note pan="0" key="{k}" vol="{v}" pos="{p}" len="{l}"/>' for k, p, l, v in sorted(notes, key=lambda n: n[1]))
    return f'''    <track type="0" name="{name}" muted="0" solo="0">
      <instrumenttrack vol="{vol}" pan="{pan}" pitch="0" pitchrange="1" basenote="57" usemasterpitch="1" fxch="0">
        <instrument name="sf2player">
          <sf2player src="{SF2}" bank="{bank}" patch="{patch}" gain="1" {rev} chorusOn="0" chorusNum="3" chorusLevel="2" chorusSpeed="0.3" chorusDepth="8"/>
        </instrument>
        <chordcreator chord="0" chordrange="1" chord-enabled="0"/>
        <arpeggiator arp-enabled="0" arp="0" arprange="1" arptime="100" arpgate="100" arpdir="0" arpmode="0" syncmode="0" arptime_numerator="4" arptime_denominator="4"/>
        <fxchain enabled="0" numofeffects="0"/>
      </instrumenttrack>
      <pattern type="1" name="{name}" pos="0" len="{16 * BAR}" muted="0" steps="16">
{body}
      </pattern>
    </track>'''


def project() -> str:
    tracks = [
        track("music box", 0, 10, 78, melody(), 0.7, 10),
        track("electric piano", 0, 4, 58, piano(), 0.5, -12),
        track("bass", 0, 32, 80, bass(), 0.15),
        track("kalimba", 0, 108, 80, sparkles(), 0.6, 25),
        track("brushes", 128, 40, 55, drums(), 0.2),
    ]
    return f'''<?xml version="1.0"?>
<!DOCTYPE lmms-project>
<lmms-project version="1.0" creator="LMMS" creatorversion="1.2.2" type="song">
  <head bpm="{BPM}" timesig_numerator="4" timesig_denominator="4" mastervol="100" masterpitch="0"/>
  <song>
    <trackcontainer type="song" visible="1" x="5" y="5" width="600" height="300" maximized="0" minimized="0">
{chr(10).join(tracks)}
    </trackcontainer>
    <timeline lpstate="1" lp0pos="0" lp1pos="{16 * BAR}"/>
    <controllers/>
  </song>
</lmms-project>
'''


if __name__ == "__main__":
    out = Path(__file__).resolve().parents[2] / "assets" / "music"
    out.mkdir(parents=True, exist_ok=True)
    mmp = Path(__file__).resolve().parent / "home_room.mmp"
    mmp.write_text(project())
    wav = Path(__file__).resolve().parent / "home_room.wav"
    subprocess.run(["lmms", "render", str(mmp), "-f", "wav", "-o", str(wav)], check=True, capture_output=True)
    # LMMS renders past the end (the reverb's tail): fold that back onto the start so it loops
    # without a seam, then bring it up to game-music loudness
    length = 16 * 4 * 60.0 / BPM
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-filter_complex",
                    f"[0]asplit[a][b];[a]atrim=0:{length:.5f},asetpts=N/SR/TB[body];"
                    f"[b]atrim=start={length:.5f},asetpts=N/SR/TB[tail];"
                    "[body][tail]amix=inputs=2:duration=first:normalize=0,"
                    f"loudnorm=I=-18:TP=-1.5:LRA=7,aresample=44100,atrim=0:{length:.5f}", "-c:a", "libvorbis", "-q:a", "6", str(out / "home_room.ogg")], check=True)
    wav.unlink()
    print(f"wrote {mmp} and {out / 'home_room.ogg'}")
