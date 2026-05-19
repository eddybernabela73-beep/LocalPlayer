"""
Generates the LocalPlayer app icon (1024x1024 PNG).
Run via GitHub Actions before xcodebuild.
Requires: pip3 install Pillow
"""
from PIL import Image, ImageDraw
import math, os

SIZE = 1024
OUT  = os.path.join("Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")

img = Image.new("RGB", (SIZE, SIZE))

# ── Gradient background: deep navy → vivid purple ─────────────────────────────
top = (10, 8, 45)
bot = (90, 20, 140)
for y in range(SIZE):
    t = y / (SIZE - 1)
    color = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    img.paste(Image.new("RGB", (SIZE, 1), color), (0, y))

draw = ImageDraw.Draw(img)

# ── Soft glow circle behind the play button ───────────────────────────────────
for r in range(300, 240, -1):
    alpha = int(30 * (1 - (r - 240) / 60))
    draw.ellipse(
        [SIZE//2 - r, SIZE//2 - r, SIZE//2 + r, SIZE//2 + r],
        outline=(180, 120, 255, alpha)
    )

# ── White circle ──────────────────────────────────────────────────────────────
R = 290
cx = cy = SIZE // 2
draw.ellipse([cx - R, cy - R, cx + R, cy + R], fill=(255, 255, 255))

# ── Purple play triangle (centred inside circle) ──────────────────────────────
TW, TH = 210, 240
tx = cx - TW // 2 + 18   # slight optical offset to the right
ty = cy - TH // 2
draw.polygon(
    [(tx, ty), (tx, ty + TH), (tx + TW, cy)],
    fill=(65, 15, 110)
)

# ── Subtle white equalizer bars at the bottom ─────────────────────────────────
bar_heights = [55, 90, 130, 90, 55]
bar_w  = 26
gap    = 16
total  = len(bar_heights) * bar_w + (len(bar_heights) - 1) * gap
bx     = cx - total // 2
by_bot = SIZE - 90
for bh in bar_heights:
    draw.rectangle(
        [bx, by_bot - bh, bx + bar_w, by_bot],
        fill=(255, 255, 255, 180)
    )
    bx += bar_w + gap

img.save(OUT)
print(f"✅ Icon saved → {OUT}  ({SIZE}×{SIZE})")
