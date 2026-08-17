# Handoff: Group Post Cards (layouts 1–4)

## Overview
Four feed-card layouts for group posts in a social app: **Float**, **Mosaic**, **Stack** (swipeable photo deck), **Strip** (horizontal scroll). Each card shows the same data — group name, member avatars, photos/selfies, reactions, comment preview — arranged differently so a feed of cards doesn't feel repetitive.

## About the Design Files
`reference.html` is a **design reference built in plain HTML/CSS/JS** — a working prototype of the exact look and the swipe interaction, not production code to import as-is. **Target stack: Flutter / Dart.** Recreate each card as a Flutter widget using your app's existing theme (colors, text styles, spacing constants) rather than copying the HTML.

### Flutter mapping notes
- Card shell → `Container` with `BoxDecoration(color, border, borderRadius: 26)` + `Padding(16)` + `Column(spacing via SizedBox or the `spacing` param on Flutter 3.27+)`.
- Overlapping avatars → `Stack`/`Row` with negative margin via `Transform.translate` or a `Stack` of positioned `CircleAvatar`s.
- Photo containers → `ClipRRect(borderRadius) > Container/Image`, gradients via `BoxDecoration(gradient: LinearGradient(...))`.
- Blur pills/buttons → `ClipRRect` + `BackdropFilter(filter: ImageFilter.blur(sigmaX:10, sigmaY:10))` over a semi-transparent `Container`.
- Card 3 swipe → `GestureDetector(onHorizontalDragUpdate/onHorizontalDragEnd)` updating an `Animatable`/`AnimationController`-driven offset (or a package like `flutter_card_swiper`/`swipe_cards` if you already depend on one), driving `Transform.translate` + `Transform.rotate` on the top card and interpolated `Transform` on the two behind it — same progress-based interpolation described below. Use `AnimationController` + `Curves.easeOutBack`-ish curve (`Cubic(.22,.61,.36,1)` via `Curves` custom cubic) to match the `.32s` snap-back/fly-off timing.
- Strip's horizontal scroll → `ListView(scrollDirection: Axis.horizontal)`.

## Fidelity
**High-fidelity.** Colors, spacing, radii, typography, and the swipe transition in `reference.html` are final — implement pixel-for-pixel. Photo/selfie tiles are striped placeholder fills (real photos replace them 1:1, same container shape and radius).

## Screens / Cards

### 1. Float
- Card: 390px wide, `#0e0e11` background, 1px `#1c1c22` border, 26px radius, 16px padding, 14px gap between sections.
- Header row: overlapping avatar stack (34px circles, -12px overlap, 2px `#0e0e11` border ring), group name (16px/600, Space Grotesk), meta line (11px IBM Plex Mono, `#82828d`: "N members · time · 🔥 streak"), "···" menu (20px, `#5e5e68`).
- Photo area: 400px tall, 20px radius, striped placeholder background. Two selfie tiles float absolutely at top-left/top-right/bottom-left (96×120 / 88×110 / 88×110), 14px radius, gradient fills, slight rotation (-4°/5°/-6°), `0 12px 30px rgba(0,0,0,.5)` shadow, 2px `rgba(255,255,255,.14)` border.
- Bottom-right: two 44px circular icon buttons (bell, smiley) stacked vertically, `rgba(10,12,18,.62)` background + 10px blur.
- Footer: overlapping comment-avatar row (30px, -10px overlap) + reaction emoji summary + comment count, then two comment lines (`bold username` + gray text, 14px/1.45).

### 2. Mosaic
- Same card shell/header pattern as Float.
- Photo grid: CSS grid, `1.15fr 1fr` columns × 2 rows, 4px gap, 360px tall, 20px radius overflow-hidden. Main memory photo spans both rows (left); one selfie tile top-right; two selfie tiles split bottom-right.
- Location pill (`📍 Santa Monica`) bottom-left of the main photo: pill shape, `rgba(10,12,18,.66)` + blur, 12px text.
- Same icon-button pair bottom-right; same comment footer pattern.

### 3. Stack — swipeable photo deck
- Card shell/header identical pattern (2-avatar variant).
- **Stack container**: 380px tall, centered, `position:relative`, `user-select:none`.
- **3 visible layers** (this pattern cycles through a longer photo array — see Interactions below):
  - Back layer: 250×320, 20px radius, `opacity:0.9`, no label.
  - Middle layer: 250×320, 20px radius, faint label text (`rgba(255,255,255,.42)`).
  - Top layer (draggable): 258×330, 20px radius, `box-shadow:0 24px 60px rgba(0,0,0,.6)`, label text (`rgba(255,255,255,.5)`, 12px, pre-line for line breaks), counter pill top-right ("2 / 7" style), location pill bottom-left.
- Two icon buttons bottom-right, `z-index:4` above the stack.
- **Progress dots** below the stack: one 6px circle per photo, `#33333d`; active dot widens to 18px and turns `#f2f2f4`, animated over `.3s`.

### 4. Strip
- Card shell/header identical pattern.
- Horizontally scrollable row (`overflow-x:auto`) of varying-height tiles (170–250px), 8px gap, bottom-aligned (`align-items:flex-end`), 16px radius each: two photo tiles with a caption label, two selfie tiles (gradient + initial), one dashed "+3 more" tile.
- Below: location pill (flat `#15151a` background, no blur) + two flat icon buttons (bell, smiley), left/right split.
- Same comment footer pattern (single comment line here).

## Interactions & Behavior

### Card 3 swipe transition (the one behavior to get exactly right)
1. **Drag**: pointerdown on the top card captures the pointer and records the start X. On pointermove, compute `dx = clientX - startX` and directly (no transition) set:
   - Top card: `translateX(dx)` + `rotate(dx / 26deg)`; fades to `opacity:0` once `|dx| > 400px` (safety net, rarely reached before release).
   - Middle/back cards: interpolate their rotation/offset/scale toward "promoted" position as a function of `progress = min(|dx| / 140, 1)` — they visibly un-stack as the top card is dragged, so the transition reads as continuous, not just "card 1 disappears, card 2 appears."
     - Middle card target at progress 1: `rotate(0deg) translateX(0) scale(1)`; at progress 0: `rotate(6deg) translateX(24px) scale(0.94)`.
     - Back card target at progress 1: `rotate(-6deg) translateX(-18px) scale(0.94)`; at progress 0: `rotate(-9deg) translateX(-26px) scale(0.9)`.
2. **Release**:
   - If `|dx| < 80px` (didn't cross the commit threshold): animate all three layers back to rest with `transition: transform .32s cubic-bezier(.22,.61,.36,1), opacity .32s ease`.
   - If `|dx| >= 80px`: animate the top card flying off-screen in the drag direction (`dx = ±560px`) with the same easing/duration, wait 300ms (roughly matching the animation), then advance the photo index (`i = (i+1) % length`), reset `dx = 0`, and re-render without a transition (so the new top card doesn't visibly fly in from the old off-screen position).
3. **Counter & dots** update immediately on index change: `"{current+1} / {total}"`, and the active dot animates width/color over `.3s ease`.
4. Photo array in the reference has 7 entries, cycling — swap in the group's actual photos in order, same data shape (`label`, `bg` placeholder → real image).
5. `touch-action: pan-y` on the draggable card so horizontal swipe doesn't fight vertical feed scroll.

### General
- No modals/navigation are wired — "···" menu, icon buttons (🔔/😊), and comment rows are visual only; wire tap targets per your existing post-detail/reaction flows.
- All four cards are read-only mocks except the card-3 swipe, which is a live interaction in `reference.html`.

## State Management
- Card 3 needs: `photos: Array<{label, imageUrl}>`, `currentIndex: number`, drag-in-progress `dx: number` (transient, not persisted). On commit, increment `currentIndex` modulo array length.
- Other cards are stateless renders of group/post data (name, emoji, member avatars, photo URLs, reaction summary, comment preview, member/comment counts, timestamp, optional location).

## Design Tokens
- **Fonts**: Space Grotesk (headings/body, weights 400–700), IBM Plex Mono (meta text, counters, labels) — both via Google Fonts.
- **Colors**: background `#08080a` (page), card `#0e0e11`, card border `#1c1c22`, primary text `#f2f2f4`, secondary text `#82828d` / `#9a9aa5` / `#6f6f7a`, comment body text `#c9c9d2`, dividers `#1c1c22`.
- **Accent gradients** (per-member avatar/selfie colors, pick consistently per user, not per card): purple `#7c5cff→#a78bfa`, pink `#ff5fa2→#ff8fc4`, cyan `#35c8ff→#7ee0ff`, amber `#ffc531→#ff9f1c`, orange-red `#ff6a3d→#e8431c`, green `#2fd18b→#0fa96b`, teal `#5eead4→#14b8a6`, indigo `#818cf8→#6366f1`, rose `#fb7185→#e11d48`, yellow `#facc15→#eab308`.
- **Radii**: card 26px, photo containers 20px, small tiles 14–16px, pills/buttons 99px (full).
- **Shadows**: selfie tiles `0 12px 30px rgba(0,0,0,.5)`; stack top card `0 24px 60px rgba(0,0,0,.6)`.
- **Blur surfaces** (icon buttons, floating pills over photos): `rgba(10,12,18,.62–.66)` + `backdrop-filter: blur(10px)`.
- **Spacing**: card padding 16px, section gap 14px, header row gap 12px, avatar overlap -10px to -12px.

## Assets
No real photography included — all photo/selfie areas are striped placeholder fills standing in for user-uploaded images. Replace with actual group photos/selfies at the same aspect ratios and container shapes.

## Files
- `reference.html` — self-contained HTML/CSS/JS reference for all four cards, including the working card-3 swipe transition (open directly in a browser).
