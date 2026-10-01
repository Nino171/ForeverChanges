"""Renders Media/Glow.tga: a white 128x64 blob whose alpha fades smoothly to zero at every edge.
The addon tints it with the teal glow colour at draw time.
Usage: python make_glow.py <output .tga>"""
import sys
from PIL import Image

W, H = 128, 64
SIDE, TOP, BOTTOM = 0.35, 0.6, 0.3  # feather width as a share of the width (sides) or height


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


img = Image.new("RGBA", (W, H))
px = img.load()
for y in range(H):
    v = (y + 0.5) / H
    fy = smooth(v / TOP) * smooth((1 - v) / BOTTOM)
    for x in range(W):
        u = (x + 0.5) / W
        fx = smooth(u / SIDE) * smooth((1 - u) / SIDE)
        px[x, y] = (255, 255, 255, round(255 * fx * fy))
img.save(sys.argv[1])
print("ok", img.size)
