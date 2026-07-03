#!/usr/bin/env python3
"""Crop pet GIFs (uniform union bbox, ground-aligned) and door-icon PNGs (per-gif tight crop)."""
import os, subprocess, sys
from PIL import Image, ImageSequence

GALLERY = "/home/user/clawd-emotes-skill/gallery"
SEALS = "/tmp/claude-0/-home-user/c41acf5f-8fff-5f31-a671-a18f4a7ce12f/scratchpad/sealwork/sealgifs"
OUT = "/home/user/kelivo/assets/clawd"
os.makedirs(OUT, exist_ok=True)

PET_POOL = {  # out-name -> source path
    "pet-coffee.gif":    f"{GALLERY}/clawd-coffee.gif",
    "pet-reading.gif":   f"{GALLERY}/clawd-reading.gif",
    "pet-listening.gif": f"{GALLERY}/clawd-listening.gif",
    "pet-sleeping.gif":  f"{GALLERY}/clawd-sleeping.gif",
    "pet-gaming.gif":    f"{GALLERY}/clawd-gaming.gif",
    "pet-painting.gif":  f"{GALLERY}/clawd-painting.gif",
    "pet-photo.gif":     f"{GALLERY}/clawd-photo.gif",
    "pet-guitar.gif":    f"{GALLERY}/clawd-guitar.gif",
    "pet-seal-idle.gif":  f"{SEALS}/clawd-seal-idle.gif",
    "pet-seal-sleep.gif": f"{SEALS}/clawd-seal-sleep.gif",
    "pet-seal-fish.gif":  f"{SEALS}/clawd-seal-fish.gif",
}

ICONS = {  # door id -> source gif
    "sense": "valentine", "calendar": "spring", "countdown": "birthday",
    "lounge": "listening", "theater": "singing", "parlour": "coffee",
    "study": "reading", "diary": "painting", "bedroom": "sleeping",
    "boudoir": "photo", "grounds": "watering", "capsule": "lantern",
    "wander": "exercise", "browser": "coding",
}

def frames_bbox(path):
    """Union alpha bbox across all frames."""
    im = Image.open(path)
    box = None
    for fr in ImageSequence.Iterator(im):
        b = fr.convert("RGBA").getchannel("A").getbbox()
        if b is None:
            continue
        box = b if box is None else (
            min(box[0], b[0]), min(box[1], b[1]),
            max(box[2], b[2]), max(box[3], b[3]))
    return box

# ---- pets: one union box over the whole pool, uniform crop ----
W = H = 240
ub = None
for src in PET_POOL.values():
    b = frames_bbox(src)
    ub = b if ub is None else (min(ub[0], b[0]), min(ub[1], b[1]),
                               max(ub[2], b[2]), max(ub[3], b[3]))
pad = 6
x0 = max(0, ub[0] - pad); y0 = max(0, ub[1] - pad)
x1 = min(W, ub[2] + pad); y1 = min(H, ub[3] + pad)
cw, ch = x1 - x0, y1 - y0
print(f"pet union bbox {ub} -> crop {cw}x{ch}+{x0}+{y0}")

for name, src in PET_POOL.items():
    dst = os.path.join(OUT, name)
    crop = f"crop={cw}:{ch}:{x0}:{y0}"
    pal = dst + ".pal.png"
    subprocess.run(["ffmpeg", "-y", "-i", src, "-vf",
                    f"{crop},palettegen=reserve_transparent=1:stats_mode=full", pal],
                   check=True, capture_output=True)
    subprocess.run(["ffmpeg", "-y", "-i", src, "-i", pal, "-lavfi",
                    f"{crop}[c];[c][1:v]paletteuse=alpha_threshold=128", dst],
                   check=True, capture_output=True)
    os.remove(pal)
    print(f"  {name}: {os.path.getsize(dst)//1024}KB")

# ---- icons: per-gif tight square crop of frame 0 ----
for door, tag in ICONS.items():
    src = f"{GALLERY}/clawd-{tag}.gif"
    im = Image.open(src).convert("RGBA")
    b = im.getchannel("A").getbbox()
    bw, bh = b[2] - b[0], b[3] - b[1]
    side = max(bw, bh) + 10
    cx, cy = (b[0] + b[2]) // 2, (b[1] + b[3]) // 2
    x0 = max(0, min(W - side, cx - side // 2))
    y0 = max(0, min(H - side, cy - side // 2))
    icon = im.crop((x0, y0, x0 + side, y0 + side))
    dst = os.path.join(OUT, f"icon-{door}.png")
    icon.save(dst, optimize=True)
    print(f"  icon-{door}.png ({tag}): {side}px, {os.path.getsize(dst)//1024}KB")

total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
print(f"TOTAL assets/clawd: {total/1024:.0f}KB")
