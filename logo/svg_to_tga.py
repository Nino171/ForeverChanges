"""Converts the WoW Forever infinity logo SVG to a 256x256 32-bit TGA for use in-game.
Usage: python svg_to_tga.py <logo.svg> <out.tga>
(WoW cannot load SVG, and texture sizes must be powers of two.)"""
import io, re, sys
import resvg_py
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
svg = open(src, encoding="utf-8").read()
# The file contains two tiny bright-green helper shapes (class cls-4); drop them.
svg = re.sub(r'<path class="cls-4"[^>]*/>', "", svg)

png = resvg_py.svg_to_bytes(svg_string=svg, width=256)
logo = Image.open(io.BytesIO(png)).convert("RGBA")
canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
canvas.paste(logo, (0, (256 - logo.height) // 2), logo)
canvas.save(out, format="TGA", compression=None)
print("wrote", out, logo.size)
