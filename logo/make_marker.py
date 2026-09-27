"""Renders Media/Infinity.tga: a white infinity sign on a transparent 64x64 canvas.
The addon tints it with the marker colour at draw time.
Usage: python make_marker.py <path to frizqt__.ttf> <output .tga>"""
import sys
from PIL import Image, ImageDraw, ImageFont

FONT, OUT = sys.argv[1], sys.argv[2]
S = 512
font = ImageFont.truetype(FONT, 700)
img = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(img)
bbox = d.textbbox((0, 0), "\u221e", font=font, stroke_width=9)
w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
d.text(((S - w) // 2 - bbox[0], (S - h) // 2 - bbox[1]), "\u221e", font=font, fill=255, stroke_width=9, stroke_fill=255)
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
