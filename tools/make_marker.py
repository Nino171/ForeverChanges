"""Renders Media/Infinity.tga: a white infinity sign on a transparent 64x64 canvas. The sign is a
lemniscate drawn as a thick curve, so no font is involved. The addon tints it at draw time.
Usage: python make_marker.py <output .tga>"""
import math
import sys
from PIL import Image, ImageDraw

OUT = sys.argv[1]
S = 1024
STROKE = 115
Y_STRETCH = 1.6  # a plain lemniscate is flat, so stretch it to make the loops roomier
img = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(img)
pts = []
for i in range(721):
    t = 2 * math.pi * i / 720
    k = 1 + math.sin(t) ** 2
    pts.append((S / 2 + 380 * math.cos(t) / k, S / 2 + 380 * Y_STRETCH * math.sin(t) * math.cos(t) / k))
d.line(pts, fill=255, width=STROKE, joint="curve")
r = STROKE / 2
for x, y in pts[::6]:
    d.ellipse((x - r, y - r, x + r, y + r), fill=255)
box = img.getbbox()
img = img.crop(box)
# fit to the full width of a square 64x64 canvas
scale = 62 / max(img.size)
img = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)
canvas = Image.new("RGBA", (64, 64), (255, 255, 255, 0))
alpha = Image.new("L", (64, 64), 0)
alpha.paste(img, ((64 - img.width) // 2, (64 - img.height) // 2))
canvas.putalpha(alpha)
canvas.save(OUT)
ys = [i for i in range(64) if alpha.crop((0, i, 64, i + 1)).getbbox()]
xs = [i for i in range(64) if alpha.crop((i, 0, i + 1, 64)).getbbox()]
print("ok", img.size, "rows", ys[0], ys[-1] + 1, "cols", xs[0], xs[-1] + 1)
