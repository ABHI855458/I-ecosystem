# Handoff: "Send a reaction" camera screen

## Overview
A full-screen capture flow for reacting to a group post with your own photo: circular viewfinder, a horizontally scrolling filter rail with a **fixed shutter button at its center**, and a second center-selection carousel for picking the reaction emoji.

## About the Design Files
`reference-camera.html` is a **working prototype in plain HTML/CSS/JS** — the visual and behavioral source of truth, not code to port. **Target stack: Flutter / Dart.**

## Fidelity
**High-fidelity.** All sizes, colors, radii, and animation timings are final.

## Layout (390 x 780 logical px, top to bottom)
1. **Title** — "Send a reaction", 19px, weight 600, centered, 20px top padding.
2. **Subhead** — 14px, `#9A9AA5`, line-height 1.5, centered, 32px horizontal padding, 20px bottom margin: "Capture your own take on the reaction, then pick which one to send."
3. **Viewfinder** — 248px circle, horizontally centered, takes the remaining vertical space (`Expanded`). 3px border `#1C1C22`, black fill, clipped to an oval.
4. **Filter rail + fixed shutter** — 96px tall stack (details below).
5. **Centered filter name** — 11px monospace, letter-spacing 0.08em, `#F2F2F4`, centered, 2px top margin.
6. **Retake / Save row** — only after a capture. Two pills, 9px x 18px padding, 13px weight 600, 12px gap, centered: "Retake" on `#1C1C22` with white text; "Save photo" on `#F2F2F4` with `#0E0E11` text, switching to "Saved ✓" for 2s after a save.
7. **Reaction rail** — label "swipe to choose a reaction" (11px monospace, uppercase, letter-spacing 0.1em, `#6F6F7A`, centered) above a center-selection carousel of 48px emoji circles, 26px bottom padding.

## Viewfinder states
- **Idle** — 📷 glyph at 34px, plus "tap to open camera" in 11px monospace `#5C5C66`. Tapping anywhere on the circle (or the shutter) requests camera access.
- **Error** — 🚫 glyph plus a message in 11px monospace `#FF8A7A`, line-height 1.5, 30px horizontal padding, centered:
  - permission denied → "Camera blocked — allow access in your browser settings" (adapt wording to the platform, e.g. "in Settings")
  - no camera / unavailable → "No camera available here. Open on a device to use it."
  - **Never fail silently.** A tap that can't open the camera must always produce one of these messages.
- **Live** — front-facing preview, mirrored horizontally, cover-fit, with the active filter applied live.
- **Captured** — the square photo, cover-fit, filter already baked in.

## Filter rail + shutter
- Horizontal scroll list of **46px filter circles**, 22px gaps, 2px `#23232B` border, each inside a 52px tap target.
- Leading and trailing padding = `(railWidth / 2) - 26` so any item can sit dead center.
- Snap to center (proximity), scrollbar hidden.
- Edge fade: horizontal gradient mask — transparent at 0%, opaque from 20% to 80%, transparent at 100%.
- **Shutter button** — pinned at the rail's exact center, above it: 84px circle, 5px `#F2F2F4` border, **centered off the border box** (a content-box centered element sits half a border off — this was a real bug), shadows `0 0 0 4px rgba(10,10,12,.9)` and `0 10px 26px rgba(0,0,0,.55)`, fill `#0E0E11`. Inner 64px circle filled with the **currently centered filter's gradient** (fallback `#7C5CFF → #4F2FD8` for "None"), inset highlights `inset 0 3px 10px rgba(255,255,255,.28)` and `inset 0 -6px 12px rgba(0,0,0,.35)`, 220ms color transition.
- Shutter tap: opens the camera when inactive, captures when live.

## Reaction rail
Same carousel mechanics: 48px circles on `#1C1C22`, 23px emoji, 20px gaps, snap to center, same edge fade, with a **fixed 66px ring** at center — 4px `#F2F2F4` border, `0 0 0 3px rgba(242,242,244,.14)` halo, non-interactive, centered off the border box.

Reactions, in order: 👍 ❤️ 😂 😍 🔥 😮 🥲 😭 🥳 💯 👏 🙌 🤯 😎 🫶 😴 🤝 ✨ 🙃 😤

## Carousel behavior (both rails — get this exact)
1. **Selection follows the center line.** On every scroll, the selected index is the item whose box-center is nearest the rail's horizontal midpoint. Selection is never independent of scroll position.
2. **Tap to center.** Tapping an item selects it and animates it to center over **300ms with an ease-out cubic** curve (`1 - (1-t)^3`).
3. **Tap lock.** Suppress scroll-driven reselection for **650ms** after a tap so the tap's target wins while the animation runs; re-sync the last-known scroll offset when the lock expires.
4. **Rest centered.** On first layout both rails start centered on **index 3**, so the shutter/ring is flanked by items on both sides. Re-assert this until the measured centered index matches the target (layout can settle late).
5. Snap-to-center is proximity, not mandatory.

## Filters
Apply as a color matrix to the live preview **and bake the same matrix into the captured image** — do not merely overlay it.

| Name | Effect | Swatch gradient |
| --- | --- | --- |
| None | identity | `#2A2A32` (flat) |
| Warm | saturate 1.3, sepia .28, contrast 1.05 | `#FFC531 → #FF6A3D` |
| Cool | saturate 1.15, hue-rotate 180°, brightness 1.05 | `#35C8FF → #6366F1` |
| Mono | grayscale 1, contrast 1.15 | `#E5E5E8 → #5C5C66` |
| Faded | contrast .85, brightness 1.12, saturate .8 | `#D9C9B8 → #A08F80` |
| Punch | saturate 1.75, contrast 1.2 | `#FF5FA2 → #7C5CFF` |
| Night | brightness .85, saturate 1.2, hue-rotate -15° | `#1E3A8A → #0F172A` |

All swatch gradients run at 160°.

## Capture & save
- Front-facing camera, **square center-crop** at `min(videoWidth, videoHeight)`.
- Preview is mirrored, and the capture is written mirrored too, so the saved photo matches what the user saw.
- Encode JPEG at ~0.9 quality.
- "Save photo" writes to the device gallery (request permission as needed) and shows "Saved ✓" for 2 seconds.
- "Retake" clears the capture and returns to the idle viewfinder.

## State
```
cameraActive: bool
hasCapture: bool
captureBytes: Uint8List?
cameraError: String?      // null, or one of the two messages above
filterIndex: int          // default 3
reactionIndex: int        // default 3
saved: bool               // transient, 2s
```

## Design Tokens
- **Fonts**: Space Grotesk (UI text), IBM Plex Mono (meta text, labels, counters).
- **Colors**: shell `#111114`, card/surface `#0E0E11`, borders `#1C1C22` / `#23232B`, chip fill `#1C1C22`, primary text `#F2F2F4`, secondary `#9A9AA5` / `#82828D` / `#6F6F7A` / `#5C5C66`, error text `#FF8A7A`.
- **Radii**: shell 36px, viewfinder and all rail items fully circular.
- **Timing**: tap-to-center 300ms ease-out cubic; tap lock 650ms; filter/shutter color transition 220ms; "Saved ✓" 2000ms.

## Flutter mapping notes
- Rails → `ListView(scrollDirection: Axis.horizontal)` inside a `Stack`, with a `ScrollController` listener computing the centered index; `ShaderMask` + `LinearGradient` for the edge fade; `ScrollController.animateTo` with `Curves.easeOutCubic` (300ms) for tap-to-center.
- Shutter / center ring → `Align(alignment: Alignment.center)` inside the same `Stack`, with `Container(decoration: BoxDecoration(shape: BoxShape.circle, border: …, boxShadow: […]))`.
- Viewfinder → `ClipOval` over `CameraPreview` / `Image.memory`, wrapped in `ColorFiltered` for the live filter, and `Transform.scale(scaleX: -1)` for the mirror.
- Filters → `ColorFilter.matrix`; bake into the capture with the `image` package.
- Camera / save / permissions → `camera`, `gal` (or `photo_manager`), `permission_handler`.

## Files
- `reference-camera.html` — self-contained prototype of this screen (open directly in a browser; camera needs a real device and granted permission).
- `README.md` / `reference.html` — the four feed-card layouts, handed off separately.
