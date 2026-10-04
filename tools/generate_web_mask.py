"""
Generates assets/masks/preset_c.png — the web-pattern concealment mask.

Drawn rather than sourced, for two reasons:
  * the eye centres end up at coordinates we CHOOSE, so the anchor constants
    in face_mask_presets.dart are exact by construction instead of measured
    off someone else's artwork;
  * it stays original art in the web-mask visual language rather than a copy
    of a specific licensed character costume, which is a real listing risk.

Re-run:  python3 tools/generate_web_mask.py
It prints the anchor values to paste into face_mask_presets.dart.
"""
import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

random.seed(7)          # deterministic: the same art every run
np.random.seed(7)

S = 1024
SS = 3                  # supersample; PIL has no polygon anti-aliasing
W = S * SS

BODY_LIGHT = (46, 46, 52)
BODY_DARK = (16, 16, 19)
WEB = (226, 226, 231)
LENS = (240, 240, 242)
RIM = (7, 7, 9)

CX = 512.0
EYE_Y = 448.0
EYE_DX = 150.0
LEFT_EYE = (CX - EYE_DX, EYE_Y)
RIGHT_EYE = (CX + EYE_DX, EYE_Y)


def sx(v):
    return v * SS


def bezier(points, steps=200):
    out = []
    for i in range(0, len(points) - 3, 3):
        p0, p1, p2, p3 = points[i:i + 4]
        for t in range(steps + 1):
            u = t / steps
            m = 1 - u
            out.append((
                sx(m**3 * p0[0] + 3*m*m*u * p1[0] + 3*m*u*u * p2[0] + u**3 * p3[0]),
                sx(m**3 * p0[1] + 3*m*m*u * p1[1] + 3*m*u*u * p2[1] + u**3 * p3[1]),
            ))
    return out


# ── Silhouette ─────────────────────────────────────────────────────────────
# Face-hugging hood: rounded crown, temples pulled in, cheeks, tapering to a
# soft chin. Mirrored so it is exactly symmetric.
half = [
    (512, 52), (338, 56), (176, 158), (158, 336),
    (146, 476), (160, 606), (206, 706),
    (258, 818), (338, 904), (424, 954),
    (462, 978), (488, 988), (512, 990),
]
left = bezier(half)
silhouette = left + [(sx(2 * CX) - x, y) for (x, y) in reversed(left)]

body_mask = Image.new('L', (W, W), 0)
ImageDraw.Draw(body_mask).polygon(silhouette, fill=255)

# ── Body: vertical gradient + radial vignette ──────────────────────────────
# A flat fill reads as a sticker. Lit slightly from above with the edges
# falling off is what makes it sit ON a face rather than over one.
yy, xx = np.mgrid[0:W, 0:W].astype(np.float32)
gy = yy / W
vert = np.clip(0.42 + 0.62 * (1.0 - gy), 0.0, 1.0)

nx = (xx - W / 2) / (W * 0.46)
ny = (yy - W * 0.5) / (W * 0.52)
vign = np.clip(1.0 - 0.55 * (nx * nx + ny * ny), 0.18, 1.0)

shade = np.clip(vert * 0.55 + vign * 0.65, 0.0, 1.15)

body = np.zeros((W, W, 3), np.float32)
for c in range(3):
    body[..., c] = BODY_DARK[c] + (BODY_LIGHT[c] - BODY_DARK[c]) * shade

# ── Fabric texture ─────────────────────────────────────────────────────────
# Four layers, because one noise layer reads as film grain rather than cloth.
# A real knit has structure at three scales at once: the thread, the weave the
# threads make, and the way the whole panel bunches. Without all three the
# mask stays a flat vector shape sitting on a photographic face.

# 1. Thread — per-pixel, the finest scale. Kept modest on purpose: this
#    asset is drawn at roughly a quarter of its 1024px size on a phone, and
#    per-pixel noise at that reduction stops being texture and becomes
#    sparkle on the downsample.
fine = np.random.normal(0.0, 4.2, (W, W, 1)).astype(np.float32)

# 2. Weave — the actual crosshatch. Two out-of-phase carriers, one per axis,
#    at slightly different pitches so they never lock into a moire grid, and
#    each one wobbles along its run so the rows aren't ruler-straight.
#    Pitch is set from the DISPLAY size, not this canvas: at ~4x reduction
#    a 5px pitch lands under a pixel and vanishes, which is why the first
#    pass produced grain and no visible weave. 15/18px here is ~4px on
#    screen — coarse enough to survive, fine enough to still read as cloth.
wob_x = np.sin(yy / 47.0) * 3.4 + np.sin(yy / 13.0) * 1.3
wob_y = np.sin(xx / 53.0) * 3.4 + np.sin(xx / 11.0) * 1.3
warp = np.sin((xx + wob_x) * (2.0 * math.pi / 15.0))
weft = np.sin((yy + wob_y) * (2.0 * math.pi / 18.0))
weave = (
    warp * 5.2
    + weft * 5.2
    # The knot where warp crosses weft catches the light hardest.
    + warp * weft * 4.0
).astype(np.float32)[..., None]

# 3. Slub — irregular thickness in the yarn itself, mid-frequency.
slub = np.array(
    Image.fromarray(
        (np.random.normal(128, 30, (W // 34, W // 34))).astype(np.uint8)
    ).resize((W, W), Image.BICUBIC).filter(ImageFilter.GaussianBlur(2.5)),
    np.float32,
)[..., None] - 128.0

# 4. Bunching — the large soft shading that makes cloth read as draped over
#    something rather than printed onto it.
coarse = np.array(
    Image.fromarray(
        (np.random.normal(128, 34, (W // 9, W // 9))).astype(np.uint8)
    ).resize((W, W), Image.BICUBIC).filter(ImageFilter.GaussianBlur(2)),
    np.float32,
)[..., None] - 128.0

body = np.clip(body + fine + weave + slub * 0.40 + coarse * 0.38, 0, 255)

img = Image.fromarray(body.astype(np.uint8), 'RGB').convert('RGBA')
img.putalpha(body_mask)
d = ImageDraw.Draw(img)

# ── Web ────────────────────────────────────────────────────────────────────
# Hand-inked, not plotted: every vertex jitters and every strand varies in
# weight, because a mathematically perfect web is the thing that reads as
# clip-art.
web = Image.new('RGBA', (W, W), (0, 0, 0, 0))
wd = ImageDraw.Draw(web)

ORIGIN = (512.0, 486.0)
SPOKES = 22
RINGS = [88, 158, 238, 328, 424, 528, 642, 766, 900, 1040]


def spoke_point(angle, r, jitter=0.0):
    j = random.uniform(-jitter, jitter) if jitter else 0.0
    return (ORIGIN[0] + math.cos(angle) * (r + j) * 0.94,
            ORIGIN[1] + math.sin(angle) * (r + j) * 1.08)


angles = [(-math.pi / 2) + (2 * math.pi * i / SPOKES) for i in range(SPOKES)]

for a in angles:
    pts = [(sx(ORIGIN[0]), sx(ORIGIN[1]))]
    for r in range(40, int(RINGS[-1] * 1.2), 26):
        p = spoke_point(a + random.uniform(-0.006, 0.006), r, jitter=3)
        pts.append((sx(p[0]), sx(p[1])))
    wd.line(pts, fill=WEB, width=int(sx(random.uniform(2.9, 3.9))), joint='curve')

for r in RINGS:
    for i, a in enumerate(angles):
        b = angles[(i + 1) % SPOKES]
        if b < a:
            b += 2 * math.pi
        p0 = spoke_point(a, r, jitter=4)
        p1 = spoke_point(b, r, jitter=4)
        pm = spoke_point((a + b) / 2, r * random.uniform(0.90, 0.945), jitter=4)
        pts = []
        for t in range(0, 22):
            u = t / 21
            m = 1 - u
            pts.append((
                sx(m*m * p0[0] + 2*m*u * pm[0] + u*u * p1[0]),
                sx(m*m * p0[1] + 2*m*u * pm[1] + u*u * p1[1]),
            ))
        wd.line(pts, fill=WEB, width=int(sx(random.uniform(2.5, 3.5))), joint='curve')

# Web sits under the same grain/shading as the body, and is clipped to it.
web = web.filter(ImageFilter.GaussianBlur(sx(0.30)))
web.putalpha(Image.composite(web.split()[3], Image.new('L', (W, W), 0), body_mask))
img = Image.alpha_composite(img, web)
d = ImageDraw.Draw(img)

# ── Lenses ─────────────────────────────────────────────────────────────────
# The eyes are the whole character of this mask. Two separate shapes, not one
# grown copy: the black surround is its own angular sweep — thick and flared
# over the brow, tapering to a sharp point that drives down toward the nose —
# and the white lens sits inside it. A uniform outline can't do that, which is
# why the previous rounded-blob version read as bland.
# 0.84: at full size the lens plus its surround ran past the silhouette and
# got clipped flat against the mask edge. Scaling the shape rather than
# re-deriving every coordinate keeps the blade geometry intact.
EYE_SCALE = 0.84


def shape(cx, cy, flip, pts, steps=110):
    def P(p):
        return (cx + p[0] * EYE_SCALE * flip, cy + p[1] * EYE_SCALE)
    return bezier([P(p) for p in pts], steps=steps)


# A BLADE, not an almond. The character of this style lives in two sharp
# tips: the outer one riding high and swept back, the inner one driving down
# toward the nose. Bezier control points approach each tip from one side
# only, which is what keeps the corner sharp instead of rounding it off — the
# previous shape had smooth control points on both sides of every vertex, so
# it came out as a blob no matter how the numbers were tuned.
#
# Listed as: outer tip -> top edge -> inner tip -> bottom edge -> close.
# A BLADE, not an almond. The character of this style lives in two sharp
# tips: the outer one riding high and swept back, the inner one driving down
# toward the nose.
#
# bezier() reads this as [anchor, ctrl, ctrl, anchor, ctrl, ctrl, anchor...]
# — indices 0,3,6,9,12,15 are the anchors. A tip is only SHARP when the
# control points either side of it leave in genuinely different directions;
# the previous version had them nearly collinear, so every "tip" smoothed
# itself into a blob no matter how the coordinates were tuned. At each tip
# below, the incoming control sits on one side and the outgoing on the other.
SURROUND = [
    (-208, -18),                                  # OUTER TIP (sharp)
    (-150, -96), (-40, -150),                     # leaves upward
    (52, -130),                                   # brow crest
    (120, -112), (176, -66),
    (192, -4),                                    # temple-side turn
    (204, 62), (196, 122),
    (178, 156),                                   # INNER TIP (sharp, driving down)
    (108, 126), (0, 132),                         # leaves up-left
    (-96, 112),                                   # underside
    (-156, 96), (-196, 56),                       # arrives from below-right
    (-208, -18),
]
LENS_SHAPE = [
    (-172, -16),                                  # OUTER TIP (sharp)
    (-122, -84), (-30, -126),
    (48, -106),
    (104, -90), (146, -50),
    (158, -2),
    (168, 52), (160, 100),
    (146, 124),                                   # INNER TIP (sharp)
    (86, 98), (-4, 102),
    (-88, 82),
    (-138, 68), (-166, 34),
    (-172, -16),
]

for eye, flip in ((LEFT_EYE, 1.0), (RIGHT_EYE, -1.0)):
    d.polygon(shape(eye[0], eye[1], flip, SURROUND), fill=RIM)
    d.polygon(shape(eye[0], eye[1], flip, LENS_SHAPE), fill=LENS)

# ── Soft edge ──────────────────────────────────────────────────────────────
# The silhouette used to end on a hard 1px cut, which is what made it read as
# a sticker pasted on top. Feathering the alpha lets the mask fall off into
# the face instead of stopping dead at an outline.
alpha = img.split()[3].filter(ImageFilter.GaussianBlur(sx(4.5)))
a = np.array(alpha, np.float32)
a = np.clip((a - 46) * (255.0 / (232 - 46)), 0, 255)   # tighten the ramp
alpha = Image.fromarray(a.astype(np.uint8), 'L').filter(
    ImageFilter.GaussianBlur(sx(2.2))
)
img.putalpha(alpha)

img = img.resize((S, S), Image.LANCZOS)
img.save('assets/masks/preset_c.png')

# ── Report the anchor ──────────────────────────────────────────────────────
arr = np.array(img)
opaque = arr[..., 3] > 40
cols = np.where(opaque.any(axis=0))[0]
print('eyeSpanRatio: %.4f' % ((RIGHT_EYE[0] - LEFT_EYE[0]) / S))
print('eyeMidX:      %.4f' % (((LEFT_EYE[0] + RIGHT_EYE[0]) / 2) / S))
print('eyeMidY:      %.4f' % (EYE_Y / S))
print('body spans x  %.4f..%.4f  (= %.4f of width)'
      % (cols.min() / S, cols.max() / S, (cols.max() - cols.min()) / S))
