"""Renders the Forever Quest Tint logo: teal badge, gold ring, "FQT" in Friz Quadrata.
Usage: python make_logo.py <path to frizqt__.ttf>"""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

FONT = sys.argv[1]
S = 1024  # supersampled; downscaled for output
cx = cy = S // 2

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# Gold ring: vertical gradient, light at the top and dark at the bottom
ring = Image.new("RGBA", (S, S))
rd = ImageDraw.Draw(ring)
for y in range(S):
    t = y / S
    c = lerp((246, 222, 150), (140, 96, 40), t) if t < 0.5 else lerp((200, 150, 70), (110, 72, 30), (t - 0.5) * 2)
    rd.line([(0, y), (S, y)], fill=c + (255,))
mask = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(mask)
R_OUT, R_IN = 500, 440
md.ellipse([cx - R_OUT, cy - R_OUT, cx + R_OUT, cy + R_OUT], fill=255)
md.ellipse([cx - R_IN, cy - R_IN, cx + R_IN, cy + R_IN], fill=0)
img.paste(ring, (0, 0), mask)

# Teal disc: radial gradient, lighter in the centre
disc = Image.new("RGBA", (S, S))
dd = ImageDraw.Draw(disc)
R_DISC = R_IN
steps = 200
for i in range(steps):
    t = i / (steps - 1)
    r = int(R_DISC * (1 - t))
    c = lerp((22, 96, 130), (52, 165, 196), t ** 0.8)
    dd.ellipse([cx - r, cy - r * 1 - 0, cx + r, cy + r], fill=c + (255,))
dmask = Image.new("L", (S, S), 0)
ImageDraw.Draw(dmask).ellipse([cx - R_DISC, cy - R_DISC, cx + R_DISC, cy + R_DISC], fill=255)
img.paste(disc, (0, 0), dmask)

# Thin inner gold line
d = ImageDraw.Draw(img)
r2 = R_IN - 26
d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], outline=(222, 190, 110, 200), width=6)

# Text
font = ImageFont.truetype(FONT, 330)
text = "FQT"
bbox = d.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
pos = (cx - tw // 2 - bbox[0], cy - th // 2 - bbox[1] - 6)

shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.text((pos[0] + 8, pos[1] + 12), text, font=font, fill=(0, 30, 45, 200))
shadow = shadow.filter(ImageFilter.GaussianBlur(8))
img = Image.alpha_composite(img, shadow)

d = ImageDraw.Draw(img)
d.text(pos, text, font=font, fill=(255, 244, 214, 255), stroke_width=10, stroke_fill=(70, 46, 16, 255))
d.text(pos, text, font=font, fill=(255, 244, 214, 255))

for size in (512, 256):
    img.resize((size, size), Image.LANCZOS).save(f"logo-{size}.png")
print("ok")
