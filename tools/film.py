#!/usr/bin/env python3
"""Film the game on Hyprland: launch it, screenshot its window at given times, make a strip.

    python3 tools/film.py <out_dir> <name> "<godot args>" t1 t2 ...
    python3 tools/film.py /tmp/shots rare "--expanded --open=starter:1 --force=rare --autoplay" 1.5 3 5

Kills any running godot first. Screenshots are <out_dir>/<name>_<t>.png plus <name>_strip.png.
Uses grim (Wayland screenshots) and ImageMagick. Pair with --autoplay so nobody has to drag.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

out, name, args, times = Path(sys.argv[1]), sys.argv[2], sys.argv[3].split(), [float(t) for t in sys.argv[4:]]
out.mkdir(parents=True, exist_ok=True)
project = Path(__file__).resolve().parent.parent

subprocess.run(["pkill", "-x", "godot"])
time.sleep(0.6)
log = open(out / "run.log", "w")
subprocess.Popen(["godot", ".", "--"] + args, cwd=project, stdout=log, stderr=log)
start = time.time()
files = []
for t in times:
    time.sleep(max(0.0, t - (time.time() - start)))
    geometry = None
    for c in json.loads(subprocess.check_output(["hyprctl", "clients", "-j"])):
        if c["title"].startswith("Desk Pets ("):
            geometry = f"{c['at'][0]},{c['at'][1]} {c['size'][0]}x{c['size'][1]}"
    if geometry is None:
        sys.exit("game window not found")
    f = out / f"{name}_{t}.png"
    subprocess.run(["grim", "-g", geometry, str(f)])
    files.append(str(f))
subprocess.run(["magick", *files, "-resize", "60%", "+append", str(out / f"{name}_strip.png")])
print((out / "run.log").read_text())
