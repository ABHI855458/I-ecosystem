# Handoff: Post Card Feed

## Overview
A dark, mobile-first social feed built from stacked **post cards**. Each card has a header (author + a "Live / N here" presence pill), a rounded photo with overlaid widgets, an expandable reactions strip, and a comment card. Includes a live-presence dropdown, a horizontally-scrollable reactions viewer, and an anonymous/real-name toggle for commenting.

## About the Design Files
The file in this bundle (`Feed.dc.html`) is a **design reference created in HTML** — a prototype showing the intended look and behavior. It is **not production code to copy directly**. The `.dc.html` format wraps the markup in a custom `<x-dc>` runtime with `{{ }}` template holes and a `class Component` logic block; ignore that scaffolding. The task is to **recreate this design in the target codebase's existing environment** (React, SwiftUI, Vue, native, etc.) using its established components, tokens, and patterns. If no environment exists yet, choose the most appropriate framework and implement it there.

All styling in the prototype is inline; the values below are the source of truth.

## Fidelity
**High-fidelity (hifi).** Final colors, typography, spacing, radii, and interactions are all specified. Recreate the UI pixel-perfectly, then map the raw values onto the codebase's design tokens where equivalents exist.

---

## Screens / Views

### Feed
- **Purpose:** Scrollable vertical list of post cards.
- **Layout:**
  - Page background `#000`. Content column centered, `width: 430px`, `max-width: 100vw` (full-bleed on smaller phones).
  - Cards stack vertically; each card is separated by an **8px solid `#000` bottom border** (this is the inter-card gap).
  - No outer horizontal padding on the column itself — inner elements handle their own insets.

### Post Card
Vertical stack: **Header → Photo → (Reactions strip, when open) → Comment card.**

---

## Components

### 1. Card header (above the photo)
- Container: `display:flex; align-items:center; justify-content:space-between; padding:12px 14px 11px;`
- **Author group** (left): `display:flex; align-items:center; gap:11px;`
  - Avatar: `42×42px`, `border-radius:50%`, solid color placeholder.
  - Username: `#fff`, `font-size:15.5px`, `font-weight:700`, truncates with ellipsis.
  - Verified badge (optional): 15×15px blue seal, fill `#3897f0` with white check, `gap:5px` after username.
  - Date line: `rgba(255,255,255,.5)`, `font-size:12.5px`, `font-weight:500`, `margin-top:1px`.
- **Live "N here" pill** (right corner) — see Widget A.

### 2. Photo
- Container: `position:relative; margin:0 12px; border-radius:26px; overflow:hidden;`
- Aspect ratio varies per post (`4/5` and `1/1` used in the mock). Ratio is the only per-card size difference.
- Image fills the container (`object-fit: cover`).
- **Scrim overlay** (non-interactive, `pointer-events:none`): `linear-gradient(to bottom, rgba(0,0,0,.22) 0%, transparent 18%, transparent 60%, rgba(0,0,0,.42) 100%)` — darkens top and bottom so overlaid widgets stay legible.
- **Picture-in-picture inset** (top-left): `position:absolute; top:14px; left:14px; width:34%; aspect-ratio:3/4; border-radius:14px; border:2px solid rgba(255,255,255,.9); box-shadow:0 6px 18px -6px rgba(0,0,0,.7);` — a second image thumbnail.

### Widget A — Live "N here" pill (header, top-right)
Compact white pill; opens the Live dropdown on tap.
- `height:34px; border-radius:17px; padding:0 13px 0 5px; background:#faf8f4; color:#2e2a22; font-size:13px; font-weight:700; gap:7px;`
- `box-shadow:0 5px 14px -8px rgba(0,0,0,.5);`
- Avatar cluster: three `22×22px` circles, `border-radius:50%`, each `border:1.5px solid #faf8f4`, overlapped with `margin-left:-9px` on the 2nd and 3rd. Colors in order: `#b9ad97` (tan), `#9db29a` (sage), `#a79bbf` (lavender).
- Live dot: `8×8px` circle `background:#37c9e6` with glow `box-shadow:0 0 7px 1px rgba(55,201,230,.8)`.
- Label: `"{count} here"`.

### Widget A-dropdown — Live presence panel
Anchored over the top of the photo when the pill is tapped.
- Position: `absolute; top:12px; right:12px; left:12px; z-index:6;`
- Surface: `border-radius:18px; background:rgba(28,28,30,.72); backdrop-filter:blur(24px); border:1px solid rgba(255,255,255,.1); box-shadow:0 20px 42px -14px rgba(0,0,0,.75); padding:11px 3px;`
- Entry animation: `ddIn` — `0.22s cubic-bezier(.2,.8,.2,1)` (fade + translateY(-8px→0) + scale(.97→1)).
- Header row: small label — `rgba(255,255,255,.55)`, `font-size:11.5px`, `font-weight:700`, `letter-spacing:.03em`, `text-transform:uppercase`, preceded by a `6px` red dot `#ff453a`; text `"live"`.
- Avatar rail: `display:flex; gap:12px; overflow-x:auto;` (hidden scrollbar). Each item `width:50px`, column, `gap:6px`:
  - Avatar `44×44px` circle (pastel color).
  - Emoji badge: `19×19px` circle `background:#1c1c1e`, `font-size:10px`, positioned `right:-2px; bottom:-2px`.
  - Name: `max-width:50px`, `rgba(255,255,255,.82)`, `font-size:11px`, `font-weight:600`, truncated.

### Widget B — Right action rail (over photo, bottom-right)
- Container: `position:absolute; right:14px; bottom:16px; display:flex; flex-direction:column; align-items:center; gap:12px;`
- **Accessibility button:** `44×44px` circle, `background:rgba(250,248,244,.95)`, `box-shadow:0 8px 20px -8px rgba(0,0,0,.6)`; 21px accessibility (person) icon, stroke `#1c1c1e`, `stroke-width:2`.
- **Add-reaction button:** `44×44px` circle, `background:#1c1c1e`, same shadow; 22px smiley icon, stroke `#9db29a`. Small `+` badge top-right: `16×16px` circle `background:#ff453a`, `#fff`, `font-size:12px`, `font-weight:800`.

### Widget C — Reactions pill (over photo, bottom-left)
Tappable; toggles the reactions strip.
- `position:absolute; left:14px; bottom:16px; height:40px; border-radius:20px; padding:0 14px 0 6px; gap:9px;`
- `background:rgba(28,28,30,.62); backdrop-filter:blur(14px); box-shadow:0 8px 20px -8px rgba(0,0,0,.5);`
- Avatar cluster: three `28×28px` circles, `border:2px solid rgba(28,28,30,.9)`, overlap `margin-left:-12px`. Colors `#b9ad97`, `#9db29a`, `#a79bbf`.
- Count label: `#fff`, `font-size:14px`, `font-weight:700`, text `"+{count}"`.

### Reactions strip (expands below the photo)
Rendered between photo and comment card when Widget C is active.
- Wrapper: `padding:12px 0 2px;`, `ddIn` animation.
- Heading: `rgba(255,255,255,.6)`, `font-size:13px`, `font-weight:700`, `padding:0 14px 10px`, text `"Reactions · {count}"`.
- Horizontal rail: `display:flex; gap:16px; overflow-x:auto;` hidden scrollbar. Each item `width:62px`, column, `gap:8px`:
  - Avatar `56×56px` pastel circle.
  - Emoji badge `23×23px` circle `background:#1c1c1e`, `font-size:12px`, `right:-2px; bottom:-2px`.
  - Name `max-width:62px`, `rgba(255,255,255,.82)`, `font-size:11.5px`, `font-weight:600`, truncated.

### Comment card
- Container: `margin:10px 12px; border-radius:18px; background:#111113; border:1px solid rgba(255,255,255,.06); overflow:hidden;`
- **Header row:** `padding:11px 14px 8px; space-between.`
  - Title `"Comments"`: `#fff`, `font-size:13px`, `font-weight:700`.
  - `"View all {count}"` button: `rgba(255,255,255,.5)`, `font-size:12px`, `font-weight:600`.
- **Comment list:** `padding:0 14px 11px; display:flex; flex-direction:column; gap:10px.` Each comment:
  - Avatar `27×27px` circle (pastel).
  - Row gap `9px`. Text `#fff`, `font-size:13px`, `line-height:1.3`: username `font-weight:700` + body `rgba(255,255,255,.85)`.
  - Timestamp: `rgba(255,255,255,.4)`, `font-size:11px`, `font-weight:600`, `margin-top:2px`.
- **Composer row (input):** `padding:9px 11px; gap:9px; border-top:1px solid rgba(255,255,255,.06); background:rgba(255,255,255,.02).`
  - **Identity toggle avatar** (`32×32px` circle button) — see Interactions. Real-name = `linear-gradient(140deg,#b9ad97,#a79bbf)`; anonymous = `#26262a` with a 19px domino-mask icon (`#cfcfd4`). A `15×15px` cyan `#37c9e6` switch badge (with a 2px `#111113` border and an 8px "swap/plus-box" glyph) sits at `right:-3px; bottom:-3px`.
  - Text block (flex:1): placeholder line `rgba(255,255,255,.4)`, `font-size:13px`; helper line `rgba(255,255,255,.35)`, `font-size:10.5px`, `font-weight:600`, reads `Posting as {name} · tap avatar to switch` with `{name}` colored `#37c9e6`.
  - **Send button:** `30×30px` circle, `background:#37c9e6`; 15px paper-plane icon, stroke `#08080a`.

---

## Interactions & Behavior
- **Live pill → dropdown:** Tapping Widget A opens the Live presence panel (only one open at a time, tracked per card id). Animates in with `ddIn`.
- **Reactions pill → strip:** Tapping Widget C expands the reactions strip below the photo (per card id).
- **Dismiss rules (apply to both dropdown and reactions strip):**
  - Clicking/tapping **anywhere outside** the open panel or its trigger closes it. (Implemented via a capture-phase `pointerdown` listener that checks `closest('.live-keep')` / `closest('.rx-keep')`.)
  - **Scrolling the feed** (window scroll) closes any open panel. Horizontal scrolling *within* a strip does NOT close it.
- **Identity toggle:** Tapping the composer avatar flips between **real name** and **anonymous**. This swaps the avatar visual, the placeholder text (`Add a comment…` ↔ `Comment anonymously…`), and the `{name}` in the helper line (`theo_b` ↔ `anon`). In the prototype this is a single shared flag across the feed; in production, scope it per composer/session as appropriate.
- **Animations:**
  - `ddIn` (dropdown/strip in): `0.22s cubic-bezier(.2,.8,.2,1)`, opacity 0→1, translateY(-8px→0), scale(.97→1).
  - `livePulse` (available for a pulsing live dot): `2s infinite`, expanding `box-shadow` ring in `rgba(255,69,58,…)`.

## State Management
- `live`: id of the card whose Live dropdown is open, or `null`.
- `reactions`: id of the card whose reactions strip is open, or `null`.
- `anon`: boolean, real-name vs anonymous composer identity.
- Global listeners on mount: capture-phase `pointerdown` (outside-click close) and `scroll` (close on feed scroll); remove on unmount.

## Design Tokens

### Colors
| Token | Value | Use |
|---|---|---|
| Feed background | `#000` | page + inter-card gap |
| Comment card surface | `#111113` | composer/comment card |
| Dark chip/badge | `#1c1c1e` | emoji badges, add-reaction button |
| Anon avatar | `#26262a` | anonymous identity |
| Light pill | `#faf8f4` | Live pill, accessibility button (`rgba(250,248,244,.95)`) |
| Text primary | `#fff` | usernames, labels |
| Text secondary | `rgba(255,255,255,.5)` | dates, "View all" |
| Text tertiary | `rgba(255,255,255,.4)` / `.35` | timestamps, helper text |
| Text on light | `#2e2a22` | Live pill label |
| Accent cyan | `#37c9e6` | live dot, send button, switch badge, links |
| Accent red | `#ff453a` | live indicator dot, `+` badge |
| Verified blue | `#3897f0` | verified seal |
| Pastel avatars | `#b9ad97` `#9db29a` `#a79bbf` `#ddd6c8` `#d9e0d4` `#e2ddec` `#eadfe0` `#d7e2e6` `#e6ddc9` `#e6d9d4` `#d3ddd9` | avatar placeholders |
| Hairline border | `rgba(255,255,255,.06)` | card borders/dividers |

### Spacing / layout
- Column width `430px` (max `100vw`).
- Inter-card gap: `8px` (bottom border).
- Header padding `12px 14px 11px`; photo side margin `12px`; comment card margin `10px 12px`.
- Overlay widget insets from photo edges: `14px` (rail/pills), `12px` (dropdown).
- Widget gaps: action rail `12px`, live rail `12px`, reactions rail `16px`, comment list `10px`.

### Typography
- **Font family:** `-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif` (system UI / SF Pro). Map to the platform's native system font.
- Sizes used: `15.5` (username) · `14` (reaction count) · `13` (comment title/body, live pill, placeholder) · `12.5` (date) · `12` (View all, emoji badges) · `11.5` (reactor name, live label) · `11` (live name, timestamp) · `10.5` (helper line) px.
- Weights: `800` (+ badge), `700` (names, titles, pills), `600` (secondary/meta), `500` (dates, placeholder).
- Line-height `1.3` for comment text.

### Border radius
- Photo `26px` · comment card / live dropdown `18px` · Live pill `17px` · reactions pill `20px` · PiP inset `14px` · circular elements `50%`.

### Shadows
- Live pill `0 5px 14px -8px rgba(0,0,0,.5)`
- Action buttons `0 8px 20px -8px rgba(0,0,0,.6)`
- Reactions pill `0 8px 20px -8px rgba(0,0,0,.5)`
- Live dropdown `0 20px 42px -14px rgba(0,0,0,.75)`
- PiP inset `0 6px 18px -6px rgba(0,0,0,.7)`

## Assets
- **No raster assets shipped.** Post photos and the PiP thumbnail are user-supplied drop targets in the prototype (`<image-slot>`); in production wire them to real image URLs (`object-fit: cover`).
- **Icons** are inline SVG (24×24 viewBox): accessibility person, smiley, verified seal, paper-plane (send), domino mask (anon), swap/plus-box (switch badge). Replace with the codebase's icon set where equivalents exist.
- **Emoji** (🔥 ❤️ 👀 😂 💀 😍 🤤) are native Unicode used as reaction badges.

## Files
- `Feed.dc.html` — the full design reference (markup + interaction logic). All measurements above are drawn from it.
