# Handoff: "Ping" Page — Campus Social App

## Overview
The Ping page is the core messaging surface for "I," a campus-exclusive, anti-performance-anxiety social app. It replaces standard chat with "pings" — prompt-based questions answered with an in-the-moment photo + text reply. This handoff covers the full page: the ping feed (To Reply / Replies / Sent), the hold-to-reveal reveal gesture, the in-place reply/camera experience, the "Ping someone" composer, and the ping-back loop.

## About the Design Files
The bundled file (`Ping Page.dc.html`) is a **design reference prototype built in HTML/React-like syntax (Design Component format)** — it demonstrates layout, states, copy, motion, and interaction timing. It is **not production code to copy directly**. The task is to **recreate this design in the target app's existing environment** (SwiftUI / Kotlin+Compose / React Native / native Android / whatever the app already uses) using its established component patterns, navigation, and state management — or choose the most appropriate framework if this is a fresh build.

`ios-frame.jsx` is only a device-bezel wrapper used for previewing in a browser; it has no equivalent in production and should be ignored by the implementing developer.

## Fidelity
**High-fidelity.** Colors, typography, spacing, radii, and motion timing below are final-intent values from the prototype and should be recreated pixel-close. Camera capture, gallery picker, and live video preview are mocked with placeholder rectangles/text in the prototype (browsers can't easily fake camera access) — these must be wired to real camera/photo-library APIs in the app.

## Screens / Views

### 1. Ping — Main Feed
**Purpose:** Single scrollable feed combining all ping activity (no more Friends/Groups/Anonymous tabs — merged into one feed called "Everyone").

**Layout (top to bottom):**
- Status/header row: "CAMPUS · [SCHOOL]" eyebrow label (10px monospace, 0.22em tracking, 34% white) + "Ping" title (27px/1.2, weight 600, -0.02em tracking). Right-aligned: Ping Score (20px number + "score" label) and a tier tag pill below it (see Design Tokens → Score Tiers).
- **Ping Back banner** (conditional): appears only when a viewed reply has an active 24h ping-back window. Full-width rounded pill (18px radius), gradient background (violet→cyan at 10-18% opacity), left side shows "Ping back?" (13.5px/500) + "open for Xh" (10.5px monospace, 40% white), right side a pill button "Ping back" (violet-cyan gradient fill, dark text).
- **"Ping Someone" strip**: horizontal scrolling row of friend avatars (52px circles, tinted gradient fills, initials), each with a small streak badge bottom-right (dark pill, 🔥 + streak count) and a name label below (10.5px, 55% white). Tapping an avatar opens the compose sheet.
- **Compose sheet** (conditional, appears under the strip when a friend is tapped): rounded card (20px radius) with header "Ping {name}" + close (×), a **scrollable list (max-height 220px)** of 4 preset prompt chips (tap to send immediately), and below it a **persistent input bar** (pill-shaped, dark translucent) with placeholder "or write your own prompt…" + a Send button that activates (cyan gradient) only when text is present.
- **Empty state** (shown only if the whole feed is empty): centered, soft pulsing violet glow circle, title (21px/600), body copy (14.5px, 50% white, max-width 270px), and a CTA pill button.
- **"TO REPLY" section**: section label (11px monospace, 0.18em tracking, 72% white) + count on the right. List of received-ping rows (see Component: To-Reply Row below).
- **"REPLIES" section**: section label (55% white). List of reply rows (see Component: Reply Row below).
- **"SENT" section**: section label (40% white, quieter than others). List of sent-ping rows — flatter/quieter styling than To Reply.
- Footer: centered caption "that's everything · no feed, no streaks" (10.5px monospace, 20% white).

All section headers/lists are hidden entirely when their list is empty (no empty section headers shown).

### Component: To-Reply Row (unrevealed state)
- Rounded rect, 22px radius, 1px border (11% white), frosted glass background (gradient 8.5%→4% white opacity), backdrop-blur 26px.
- Single row, vertically centered: 36px circular avatar (tinted gradient) + name (13px/500, 62% white) + prompt text (16px/500, full white, wraps).
- Content under a CSS `filter: blur()` that is **driven by hold progress** (see Interactions).
- Right side (90px wide gradient-fade zone): a 42px circular progress ring (conic-gradient arc using the accent color, revealed portion) with a small 7px dot in the center (no lock icon — just a plain glowing dot), and below it a hint label ("hold 1s to reveal" / "keep holding" / "opening", 8.5px monospace).

### Component: To-Reply Row (revealed, collapsed state)
- Once a user has held-to-reveal once, this row **permanently stops blurring** — it never re-blurs, even after collapsing back from the expanded reply card.
- Same row shape, quieter cyan-tinted border/background (no more violet gradient), fully unblurred content, tapping anywhere reopens the expanded reply card directly (no hold needed).
- Optionally show a quiet "window open · Xh Ym to send more" caption with a small pulsing cyan dot (see To-Reply Reply Window below) — current build omits the countdown chip inside the expanded header per latest revision but the row-level dot+time can still be shown here if useful.

### Component: To-Reply Row → Expanded Reply Card
Tapping/holding through a To-Reply row expands it in place (no navigation) into a larger card:
- Card: 22px radius, brighter frosted glass, stronger shadow + soft cyan ambient glow.
- **Header section** (bottom border): 32px avatar, sender name (12.5px/500), "pinged you · {time}" caption (10px monospace, 36% white), close (×) button top-right. Below that, the prompt text at 17px/500, -0.01em tracking.
- **Reply window**: opening a ping starts a **3-hour reply window** (`windowHours = 3` in source) during which the user can send unlimited replies to that same ping without re-triggering the hold gesture. Window remaining time is computed as `revealedAt + windowHours*3600000 - now`.
- **Media/photo area**: A rounded-rectangle drop zone/button, 120×150px (roughly 1.25x a normal thumbnail — sized at 2.5x-then-halved from an original 96×120 base per design iteration), dashed border, "+" glyph + "add photo" caption. Tapping it opens the **full-screen dual camera**:
  - Full-bleed camera preview (back camera), with a smaller front-camera picture-in-picture window bottom-right (76×96px, rounded 14px, white border) — this is the "dual camera" (BeReal-style simultaneous front+back capture).
  - Top-left "LIVE" badge with pulsing magenta dot.
  - Bottom toolbar: gallery/photo-picker button (left), large capture shutter button (center, cyan gradient fill), spacer (right).
  - Close (×) button top-right returns to the card without capturing.
  - Capturing or picking from gallery closes the full-screen camera and shows the captured frame in the drop-zone box (with a "retake" option before sending).
- **Text input bar**: pill-shaped input ("say something…") + Send button (disabled/muted until a photo is captured; activates with cyan gradient + glow once ready).
- **Sent replies list**: after sending, the card **stays open** (does not close/navigate away) and each send appends a small "sent" chip row (thumbnail placeholder + text preview + "sent" tag) below the composer, so the user can keep sending more replies to the same ping. Caption: "unlimited within the window — send more anytime."

### Component: Reply Row (unviewed / blurred)
- **Identical sizing/shape to the To-Reply row** (same 22px radius, same padding, same 90px hold-ring zone) for visual consistency — this was an explicit design decision to make all "things to unwrap" feel the same weight.
- Left: 36px rounded-square photo placeholder (striped/gradient placeholder) instead of a circular avatar. Text: "{name} replied" (13px/500) + prompt (16px/500).
- Same hold-to-reveal gesture as To-Reply (2s default, tunable) with the same plain-dot progress ring.

### Component: Reply Row (viewed)
- Quiet, flat card (no blur, 20px radius, subtle 7.5% white background, no glass blur needed since it's a resting state).
- **Ping Back banner** (conditional, appears only within 24h of viewing): thin strip at the top of this specific reply card — "Ping back?" + "open for Xh" caption, and a pill CTA button "Ping {name}" (violet-cyan gradient). Disappears after 24h; the reply itself remains permanently below regardless.
- Body: 62×76px photo thumbnail placeholder, sender name + relative timestamp, "re: {prompt}" caption, reply body text (13.5px/1.5), and a quiet "viewed · stays here" footnote (10px monospace, 22% white) confirming the reply never disappears from the list.

### Component: Sent Row
- Flatter than To Reply/Replies: 18px radius, 6% white background, no blur/glow.
- Dashed-circle placeholder avatar (matches "no reply yet" feeling), "to {name}" caption, prompt preview text.
- Right side: **Seen indicator** — if seen, a small pulsing cyan dot + "Seen" label (10.5px monospace); if not yet seen, quiet "Delivered" label (24% white, no dot/pulse).

## Interactions & Behavior

### Hold-to-reveal gesture (To Reply & Replies rows)
- Trigger: `pointerdown` starts a timer; `pointerup`/`pointerleave` before completion cancels and resets to 0% with no reveal.
- Duration: default **1 second** (tunable via a "Hold duration" control, 0.4s–4s range in the prototype's tweak panel — pick a sensible fixed value for production, e.g. 1–1.5s, based on user testing).
- Visual feedback while holding: the card's `filter: blur()` continuously decreases from ~9px to 0px in step with progress; a circular conic-gradient ring around a center dot fills clockwise from 0–360° in the accent color, with a growing glow (box-shadow) that intensifies near completion; a text hint below cycles "hold Xs to reveal" → "keep holding" → "opening".
- On completion (100%): the row expands in place into the full reply/reveal experience (see below). No separate screen/route — this is an inline expand/collapse, ideally an animated height+opacity transition (~250–350ms ease-out recommended).
- **Important divergence from earlier "reveal" patterns**: once a To-Reply ping has been revealed once, it must **never blur again** — even when the user collapses the expanded card back down. The collapsed row after first reveal shows unblurred content and a lighter/quieter treatment, and simply reopens the expanded card on tap (no hold required a second time). Reply rows, by contrast, DO show a quieter "viewed" state that's a genuinely different, flatter card design (not just unblurred) — implement To-Reply "revealed-collapsed" and Reply "viewed" as two distinct visual states per the specs above.

### Reply window (To Reply only)
- First reveal timestamps a 3-hour window (`windowHours`, currently 3 in source — confirm final value with product).
- Within the window, the user may send as many photo+text replies as desired to that ping; each send resets the capture state (photo cleared, text cleared) but keeps the card open, appending a "sent" confirmation chip to a running list inside the card.
- After the window elapses, decide product behavior (not fully speced in prototype): likely soft-lock further sends or hide the "add more" affordance — confirm with product before shipping; the prototype does not enforce a hard cutoff in the UI.

### Dual camera capture
- Tapping the "add photo" drop zone opens a full-screen camera view (should be a true native camera view, not a page navigation, to preserve the "in place" feel — e.g. a modal/sheet presentation).
- Two live feeds shown simultaneously: primary back-camera preview full-bleed, secondary front-camera preview as a PiP inset bottom-right — mirrors BeReal-style dual capture.
- Shutter button captures both frames; a gallery-icon button allows picking existing photos instead of live capture.
- After capture, return to the reply card showing the captured frame with a "retake" option before sending.

### Ping Back
- Appears as a call-to-action for 24 hours after a reply is first viewed (timestamp when hold-reveal completes on a Reply row).
- Two placements: (1) inline atop that specific viewed reply's card, and (2) a page-level banner surfacing the single highest-priority pending ping-back, placed directly below the "Ping Someone" strip — a re-engagement nudge so the action is visible immediately on page load, not buried in the list.
- After 24h, the CTA disappears in both places; the reply content remains permanently.

### Compose / "Ping Someone"
- Tapping a friend avatar opens an inline compose sheet (not a new screen).
- Prompt selection is a **scrollable list** (cap the visible height, e.g. 220px, and scroll for more presets) OR a free-typed custom prompt via a persistent text input + Send button at the bottom of the sheet (always visible, not just after scrolling).
- Sending (preset tap or custom Send) immediately creates a new row in "Sent" for that friend and closes the compose sheet.

### Ping Score & Tier Tag
- A numeric "Ping Score" shown top-right of the header, with a tier tag pill beneath it that changes color/label based on score thresholds (see Design Tokens).

## State Management
Key state needed per ping-page session (see prototype's `Component` class for full shape):
- `revealed: { [pingId]: revealedAtTimestamp }` — persists which To-Reply pings have been opened at least once, and when (drives the reply-window countdown and the "never re-blur" rule).
- `viewed: { [replyId]: boolean }` — which Replies have been opened.
- `pingedBack: { [replyId]: boolean }` — whether the user already used their Ping Back for a given reply.
- `sentReplies: { [pingId]: [{ text }] }` — the running list of replies sent within an open ping's window.
- `captured: { [pingId]: boolean }`, `mediaOpen: { [pingId]: boolean }` — camera/capture UI state per open ping.
- `composeFor: friendId | null`, `composeDraft: string` — "Ping Someone" compose sheet state.
- Hold-gesture transient state: which row is currently being held and its 0–1 progress (drive via `requestAnimationFrame`, not `setInterval`, for smooth 60fps ring/blur animation — this matches the prototype's approach).
- Data needed from backend: list of To-Reply pings (sender, prompt, received-at/expiry), list of Sent pings (recipient, prompt, seen-at), list of Replies (sender, prompt, reply photo+text, received-at), friend list with streak counts, ping score.

## Design Tokens

### Colors
- Background base: `#0a0a0d` (near-black, cool dark)
- Primary text: `#f4f4f7`
- Text at reduced opacity: use white at 22–72% opacity depending on hierarchy (see per-component notes above) rather than distinct gray tokens.
- Accent — cyan: `#7fe4ee` (default hold-ring/live accent; tunable)
- Accent — violet: `#b9a7ff` (ping-back / compose gradient)
- Accent — magenta: `#f39ddd` (live-camera badge, streak flame, deeply-present tier)
- Ambient background glows: radial gradients using violet (~16% opacity) top-left, cyan (~12% opacity) upper-right, magenta (~10% opacity) lower-left — very large, soft, blurred (10–12px blur), animated with slow 18–26s drift keyframes.

### Score Tiers (Ping Score tag)
- ≥700: "Deeply Present" — magenta (`#f39ddd`)
- 400–699: "Showing Up" — cyan (`#7fe4ee`)
- <400: "Getting Started" — violet (`#b9a7ff`)
Each tag: 10px/500 text, pill background at 12% of its color, 1px border at 30% of its color.

### Typography
- Primary font: system UI sans-serif (San Francisco / Roboto / platform default) — no custom font was loaded in the final build.
- Monospace (for labels, timestamps, hints, section eyebrows): system monospace (SF Mono / Roboto Mono / platform default), typically 8.5–11px with wide letter-spacing (0.06–0.22em) for eyebrow/section labels.
- Scale used: 27px/600 (page title) · 21px/600 (empty-state title) · 17px/500 (expanded card prompt) · 16px/500 (row prompt text) · 14.5px/400 (empty-state body) · 13–13.5px/500 (names, buttons) · 10–11.5px monospace (captions, hints, timestamps).

### Spacing & Radii
- Page padding: 28px top, 24px sides (compact — the full layout is a phone-width column, no need for generous outer margins beyond this).
- Card radii: 22px (primary rows/cards), 20px (viewed replies, empty-state elements), 18px (photo drop zone), 100px/pill (buttons, chips, badges).
- Row internal padding: ~17px vertical, 18px left / 90px right (to clear the hold-ring zone).
- Section vertical rhythm: 8px between section label and list, 12px gap between rows within a list, 20–30px between sections.

### Motion
- Hold-to-reveal: drive via `requestAnimationFrame`, default 1000ms (tune per product testing), easing is linear progress mapped to blur/ring (no additional easing curve needed — the ring fill itself reads as the easing).
- Ambient background blob drift: 18–26s ease-in-out infinite, translate ±20px.
- Pulsing dots (seen indicator, live badge, ping-back availability): 2.6–3s ease-in-out infinite, opacity 0.35→1 and scale 1→1.35.
- Card expand/collapse: recommend 250–350ms ease-out on height/opacity (prototype does this instantly via conditional render; production should animate the transition).

## Assets
No real photography/imagery is used — all photo/video surfaces (avatars beyond initials, reply thumbnails, camera previews, captured frames) are **placeholder rectangles** with diagonal striped gradients and monospace labels describing what belongs there (e.g. "captured frame", "back camera preview", "their photo"). Production implementation needs:
- Real avatar images (or keep initials-on-gradient as the permanent style — confirm with product).
- Real camera integration (native camera APIs, not a mocked preview).
- Real photo-library/gallery picker integration.

## Files
- `Ping Page.dc.html` — the full interactive prototype (all states reachable via a "Jump to State" panel alongside the phone mockup, plus real hold/tap gestures). Open in any browser to explore.
- `ios-frame.jsx` — device-bezel wrapper used only for prototype preview; not needed in production.
