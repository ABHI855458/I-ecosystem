# Anonymous Feed — Complete Implementation Spec

Campus social app. Dark, mobile-first vertical feed of **post cards**. Two card families share one widget system: **Solo posts** (one author, one 4:5 photo) and **Group posts** (a shared album shown in four layout variants). Every measurement, color, font, and interaction below is the source of truth.

---

## 0. Global / Feed shell

- **Page background:** `#000000` (pure black), full viewport height (`min-height: 100vh`).
- **Content column:** centered horizontally. `width: 430px; max-width: 100vw` (full-bleed on narrower phones). Everything lives in this column.
- **Font families** (load both):
  - **Inter** — weights 400, 500, 600, 700, 800. Default UI font for the whole app (`body { font-family: Inter }`).
  - **Nunito** — weights 600, 700, 800. Used ONLY for display text: author/group names, the "N here" live pill label.
  - Monospace fallback stack for the group timestamp line: `ui-monospace, SFMono-Regular, Menlo, monospace`.
- **Link colors** (define globally even if unused): `a { color: #5ac8e0 }`, `a:hover { color: #7fdcf0 }`.
- **Font smoothing:** `-webkit-font-smoothing: antialiased`.
- **Hidden scrollbars:** every horizontal scroller sets `scrollbar-width: none` and `::-webkit-scrollbar { display: none }`.

### Gap between cards (feed rhythm)
Each card is wrapped in a container with a **solid black bottom border that IS the inter-card gap**:
```
border-bottom: 8px solid #000000;   /* default gap = 8px */
```
This is a tweakable value (`cardGap`, range 0–24px, step 2, default **8px**). The black border reads as breathing room between cards against the black page. No other outer margin between cards.

---

## 1. SOLO POST CARD

Vertical stack: **Header → Caption → Photo (with overlays) → Reactions strip (conditional) → Comment card.**

### 1.1 Header row
- Container: `display:flex; align-items:center; justify-content:space-between; padding:12px 14px 11px;`
- **Left author group:** `display:flex; align-items:center; gap:11px; min-width:0;`
  - Avatar: `42×42px`, `border-radius:50%`, solid color placeholder.
  - Name row: `display:flex; align-items:center; gap:5px;`
    - Username — **Nunito**, `font-size:15.5px; font-weight:700; color:#fff;` truncates with ellipsis.
    - Verified badge (optional): `15×15px` seal, fill `#3897f0`, inner check `#fff`.
  - Date line: `color:rgba(255,255,255,.5); font-size:12.5px; font-weight:500; margin-top:1px;`
- **Right cluster:** `display:flex; align-items:center; gap:12px;`
  - **Live "N here" pill** (see §3.1).
  - **More (⋯) button:** transparent, `padding:4px`; icon three dots `22×22px` viewBox, `fill:#fff`. Opens the more-menu (§3.6).

### 1.2 Caption
- `padding:0 14px 10px; color:#fff; font-size:15px; font-weight:500; line-height:1.4;`
- Only rendered when caption text exists AND the `showCaption` toggle is on.

### 1.3 Photo block
Two nested divs — an **outer unclipped wrapper** (holds overlays that must escape the frame, like dropdowns) and an **inner clipped frame** (rounds the image):
- Outer wrapper: `position:relative; margin:0 12px;` (so photo is inset 12px from each column edge → photo width = 430 − 24 = **406px**).
- Inner frame: `border-radius:26px; aspect-ratio:4/5; overflow:hidden;`
  - `photoRadius` is tweakable (range 0–40px, step 2, default **26px**). Solo photo aspect is **4/5 portrait** (the app's only camera ratio). *(Post "b" in the mock uses 1/1 only to demonstrate flexibility; production is always 4/5.)*
  - Image: `<img>`/slot filling the frame, `object-fit:cover`.
  - **Scrim overlay** (non-interactive): `position:absolute; inset:0; pointer-events:none;`
    `background: linear-gradient(to bottom, rgba(0,0,0,.22) 0%, transparent 18%, transparent 60%, rgba(0,0,0,.42) 100%);`
  - **Picture-in-picture inset** (top-left, optional via `showPiP`): `position:absolute; top:14px; left:14px; width:34%; aspect-ratio:3/4; border-radius:14px; overflow:hidden; border:2px solid rgba(255,255,255,.9); box-shadow:0 6px 18px -6px rgba(0,0,0,.7);`

### 1.4 Photo overlays (all positioned against the outer wrapper)
- **Live dropdown** (when open) — §3.1.
- **Right action rail** — vertical, `position:absolute; right:13px; bottom:14px; display:flex; flex-direction:column; align-items:center; gap:22px;`
  - **Ping button** (top): `34×34px` circle, `background:#131315;` `box-shadow:0 2px 8px rgba(0,0,0,.4);` Icon = circled-figure "ping" glyph (see §4, Ping icon), `24×24px` viewBox, white strokes. Opens ping dropdown (§3.4).
  - **RealMoji button** (bottom): `34×34px` circle, `background:#fff; box-shadow:0 2px 8px rgba(0,0,0,.35); overflow:hidden;`
    - Default (not reacted): dark outline smiley, stroke `#1a1a1a`, `stroke-width:1.9`, `21×21px`.
    - Reacted: the button fills with the picked RealMoji color (`{{pickedColor}}`, a `34×34` circle).
    - Opens the RealMoji picker (§3.3).
- **Reactions cluster** (reaction VIEWING, bottom-LEFT): `position:absolute; left:13px; bottom:14px;` a button, `display:flex; align-items:center;`
  - Two overlapping avatars: `34×34px` circles, `border:2px solid rgba(0,0,0,.55);` second has `margin-left:-13px`. Colors `#b9ad97`, `#9db29a`.
  - Count chip: `height:34px; padding:0 10px 0 17px; margin-left:-13px; border-radius:17px; background:rgba(0,0,0,.5); border:2px solid rgba(0,0,0,.55); color:#fff; font-size:13px; font-weight:700;` text `+{count}`.
  - Tapping expands the reactions strip (§1.5).

### 1.5 Reactions strip (expands below photo when cluster tapped)
- Wrapper: `padding:12px 0 2px;`
- Heading: `color:rgba(255,255,255,.45); font-size:9.5px; font-weight:700; letter-spacing:.08em; text-transform:uppercase; padding:0 14px 9px;` text `RealMojis · {count}`.
- Horizontal rail: `display:flex; gap:16px; overflow-x:auto; padding:2px 14px 4px;`
  - Each reactor: column, `width:56px; gap:7px; align-items:center;`
    - Selfie avatar `56×56px` circle, `border:2px solid rgba(255,255,255,.12);`
    - Name: `max-width:56px; color:rgba(255,255,255,.72); font-size:10.5px; font-weight:600;` truncated.

### 1.6 Comment card (solo)
- Container: `margin:10px 8px 0 8px; border-radius:18px; background:#18181a; overflow:visible;`
- **Toggle header button:** `display:flex; align-items:center; gap:7px; padding:9px 14px 6px;`
  - Speech-bubble icon `15×15`, stroke `rgba(255,255,255,.4)`.
  - Label: `color:rgba(255,255,255,.4); font-size:12px; font-weight:600;` — reads `View all {N} comments` collapsed, `Hide comments` expanded.
  - Chevron `12×12`, stroke `rgba(255,255,255,.35)`, rotates `0deg → 180deg` on expand.
- **Collapsed preview:** `padding:0 14px 2px; display:flex; flex-direction:column; gap:3px;` shows the top **2** comments, each a single truncated line: username `font-weight:700`, body `rgba(255,255,255,.75)`, `font-size:12.5px; line-height:1.4;`
- **Expanded body:**
  - RealMoji rail (mini): `padding:2px 0 8px;` heading `RealMojis · {count}` (`font-size:9px`, same uppercase style, padding `0 14px 7px`), rail `gap:9px; padding:1px 14px;` avatars `42×42px`, names `font-size:9px; color:rgba(255,255,255,.55);`.
  - Full comment list: `max-height:200px; overflow-y:auto; display:flex; flex-direction:column; gap:9px; padding:10px 14px 4px; border-top:1px solid rgba(255,255,255,.05);`
    - Each: avatar `24×24px`, gap `9px`; username `700` + body `rgba(255,255,255,.78)` at `12.5px/1.4`; timestamp below `color:rgba(255,255,255,.28); font-size:10px; font-weight:600; margin-top:2px;`
- **Composer row:** `display:flex; align-items:center; gap:8px; padding:7px 12px 9px;`
  - **Identity avatar (anon toggle):** `27×27px`, `position:relative;`
    - Real: `27×27` circle, `background:linear-gradient(140deg,#b9ad97,#a79bbf);`
    - Anon: `27×27` circle `background:#2a2a2e` with a `14×14` domino-mask icon (`#cfcfd4`).
    - Swap badge (always shown, bottom-right): `13×13px` circle `background:#3a3a40; border:1.5px solid #18181a;` with a `7×7` swap-arrows glyph `rgba(255,255,255,.85)`. Indicates tap-to-switch identity.
  - **Input pill:** `flex:1; height:28px; padding:0 12px; border-radius:14px; background:rgba(255,255,255,.055);` placeholder text `color:rgba(255,255,255,.32); font-size:12.5px; font-weight:500;` — reads `Add a comment…` (real) / `Comment anonymously…` (anon).
  - **Send button:** `26×26px` circle `background:rgba(255,255,255,.08);` paper-plane icon `13×13`, fill `rgba(255,255,255,.55)`.

---

## 2. GROUP POST CARD

Same widget system, four photo layouts (`glayout`: `single | collage | deck | split`). Header + comment card are shared; only the photo region differs.

### 2.1 Group header
- Container: `display:flex; align-items:center; justify-content:space-between; gap:10px; padding:14px 14px 12px;`
- **Left:** `display:flex; align-items:center; gap:12px; min-width:0;`
  - Group glyph: `44×44px` circle, `background:linear-gradient(150deg,#3ddc97,#10b981); color:#fff; font-size:17px; font-weight:700;` centered initial.
  - Group name — **Nunito**, `font-size:17.5px; font-weight:800; letter-spacing:-.2px; color:#fff;` truncated.
  - Meta line — **monospace**, `color:rgba(255,255,255,.4); font-size:12.5px; margin-top:2px;` e.g. `5 members · 2h ago`.
- **Right:** Live "N here" pill (compact variant, §3.2).

### 2.2 Layout — SINGLE (photo + member tile)
- Wrapper: `position:relative; margin:0 12px;`
- Photo: `border-radius:20px; aspect-ratio:4/5; overflow:hidden; background:#1a1a1e;`
- Member tile overlay: `position:absolute; top:5%; left:5%; width:29%; aspect-ratio:175/220; border-radius:19px; background:linear-gradient(160deg,#3ddc97,#10b981); border:3px solid rgba(255,255,255,.22); box-shadow:0 10px 26px -8px rgba(0,0,0,.6); color:#fff; font-size:24px; font-weight:700;` centered initial.
- **Reactions cluster** bottom-LEFT (`left:16px; bottom:16px`) — same build as §1.4 cluster (34px avatars, `+{count}` chip).
- **Action buttons** bottom-RIGHT (`right:16px; bottom:16px; display:flex; gap:14px;`): **Wave** then **RealMoji**, each `44×44px` white circle (`#f7f7f5`), `box-shadow:0 3px 10px rgba(0,0,0,.35);`, dark `#2a2a2e` icons `24×24`.

### 2.3 Layout — COLLAGE (staggered tiles)
- Row: `display:flex; align-items:flex-start; gap:8px; padding:0 0 0 12px; overflow:hidden; height:262px;`
  - Tile 1: `width:33%; aspect-ratio:230/340; margin-top:52px; border-radius:11px;`
  - Tile 2: `width:33%; aspect-ratio:227/425; border-radius:11px;`
  - Tile 3 (member): `width:25%; aspect-ratio:170/290; margin-top:85px; border-radius:11px;` green gradient, initial `font-size:22px`.
- Action row below: `display:flex; align-items:center; gap:14px; padding:14px 12px 4px;`
  - **Reactions cluster first (LEFT)**, then a `margin-left:auto` group holding **Wave + RealMoji** (`44×44` white circles) pushed RIGHT. Cluster chip background here uses `rgba(255,255,255,.1)` and `border:2px solid #000` (on-card, not on-photo).

### 2.4 Layout — DECK (carousel with tilted side cards)
- Stage: `position:relative; height:400px; display:flex; align-items:center; justify-content:center;`
  - Left card: `position:absolute; left:14px; top:42px; width:26%; height:310px; border-radius:14px; transform:rotate(-4deg);`
  - Right card: mirror, `right:14px; transform:rotate(4deg);`
  - Center card: `position:relative; width:66%; height:385px; border-radius:18px; box-shadow:0 14px 34px -10px rgba(0,0,0,.7);`
    - Count badge top-right: `top:14px; right:14px; height:32px; padding:0 14px; border-radius:16px; background:rgba(20,20,22,.72); backdrop-filter:blur(12px); color:#fff; font-size:13.5px; font-weight:600; letter-spacing:.06em;` e.g. `1 / 9`.
    - **Reactions cluster** bottom-LEFT (`left:14px; bottom:14px`) — smaller: `30×30` avatars, `margin-left:-12px`, chip `height:30px; border-radius:15px; font-size:12px;`.
    - **Wave + RealMoji** bottom-RIGHT (`right:14px; bottom:14px; gap:12px`), `40×40px` white circles, `22×22` icons.
- Dots row: `display:flex; justify-content:center; gap:7px; padding:12px 0 4px;` active dot `22×5px` radius 3 `#fff`; inactive `5×5px` circle `rgba(255,255,255,.24)`.

### 2.5 Layout — SPLIT (two-up)
- Wrapper: `position:relative; margin:0 12px;`
- Grid: `display:flex; gap:3px; aspect-ratio:406/640; border-radius:20px; overflow:hidden;`
  - Left pane: photo, `flex:1`.
  - Right pane: `flex:1; background:linear-gradient(165deg,#3ddc97,#10b981); color:#fff; font-size:30px; font-weight:700;` centered initial.
- **Reactions cluster** bottom-LEFT (`left:16px; bottom:16px`), **Wave + RealMoji** bottom-RIGHT (`right:16px; bottom:16px; gap:14px`), `44×44` white circles.

### 2.6 Group reactions strip & RealMoji picker
- **Reactions strip** (expands): identical spec to §1.5 (heading `RealMojis · {count}`, `56×56` avatars, `gap:16px`).
- **RealMoji picker** (group, inline card): `display:flex; align-items:center; gap:8px; margin:12px 12px 0; padding:8px 10px; border-radius:32px; background:rgba(24,24,26,.95); border:1px solid rgba(255,255,255,.08); overflow-x:auto;` — options `44×44` circles + a dashed "new RealMoji" camera button.

### 2.7 Group comment card
**Identical structure and sizing to the solo comment card (§1.6)** — same `#18181a`/`#101012` surface, toggle header, 2-line collapsed preview, expanded RealMoji rail + comment list, and the compact composer (27px identity avatar, 28px input pill, 26px send). Group and solo comment sections must match exactly.

---

## 3. Shared widgets — exact specs

### 3.1 Live "N here" pill (solo)
- `display:flex; align-items:center; gap:7px; height:34px; padding:0 13px 0 5px; border-radius:17px; background:#faf8f4; color:#2e2a22;` **Nunito** `font-size:13px; font-weight:700; box-shadow:0 5px 10px rgba(0,0,0,.35);`
- Avatar cluster: three `22×22px` circles, `border:1.5px solid #faf8f4`, 2nd/3rd `margin-left:-9px`. Colors `#b9ad97`, `#9db29a`, `#a79bbf`.
- Live dot: `8×8px` circle `#37c9e6`, `box-shadow:0 0 7px 1px rgba(55,201,230,.8);`
- Label: `{count} here`.

### 3.2 Live "N here" pill (group — reduced)
- `height:29px; gap:6px; padding:0 11px 0 4px; border-radius:14.5px; background:#faf8f4; color:#17171a;` **Nunito** `font-size:11.5px; font-weight:800;`
- Avatar cluster: three `18×18px` circles, `border:1.5px solid #faf8f4`, 2nd/3rd `margin-left:-7px`. Colors `#e8dfd6`, `#cfc6dd`, `#a79bbf`.
- Live dot: `7×7px` `#22c9e8`. Label `{count} here`.

### 3.3 Live presence dropdown (both)
- `position:absolute; width:158px (solo) / 160px (group); z-index:6–9; border-radius:13–14px; background:rgba(22,22,24,.9); backdrop-filter:blur(20px); border:1px solid rgba(255,255,255,.09); box-shadow:0 12px 28px -10px rgba(0,0,0,.7); padding:8px 10px 9px;`
- Anchored top-right of the photo (`top:10px; right:12px` solo).
- Header: `color:rgba(255,255,255,.42); font-size:9.5px; font-weight:700; letter-spacing:.07em; text-transform:uppercase; padding-bottom:7px;` text `here now`.
- List rows: `display:flex; flex-direction:column; gap:7px;` each row `gap:7px`, `5×5px` color dot + name `color:rgba(255,255,255,.85); font-size:12px; font-weight:600;` truncated.

### 3.3b RealMoji picker (selfie reactions, solo)
- `position:absolute; right:13px; bottom:58px; display:flex; align-items:center; gap:7px; padding:7px 9px; border-radius:32px; background:rgba(20,20,22,.9); backdrop-filter:blur(20px); box-shadow:0 10px 26px -6px rgba(0,0,0,.6);`
- Options: 5 saved selfies as `42×42px` circles, `border:2px solid` — ring `rgba(255,255,255,.28)` default, `#fff` when selected. Colors `#c9b79c #9db29a #a79bbf #d5a8a0 #8fa8bd`.
- **Camera / new-RealMoji button:** `42×42px` circle, `border:1.5px dashed rgba(255,255,255,.35); background:rgba(255,255,255,.06);` camera icon `19×19`, stroke `rgba(255,255,255,.75)`.
- Tapping a selfie sets it as your reaction (fills the RealMoji button) and closes the picker; tapping the same one again removes the reaction.

### 3.4 Ping prompt dropdown
- `position:absolute; bottom:0; right:42px; width:186px; border-radius:14px; background:rgba(20,20,22,.92); backdrop-filter:blur(22px); border:1px solid rgba(255,255,255,.09); box-shadow:0 14px 34px -10px rgba(0,0,0,.7); padding:5px; z-index:9;`
- Each prompt: `display:flex; align-items:center; gap:9px; width:100%; padding:9px 10px; border-radius:10px;` hover `background:rgba(255,255,255,.08);` — emoji `font-size:15px` + label `color:rgba(255,255,255,.85); font-size:13px; font-weight:600;`.
- Default prompts: `👋 Say hi · 📸 Post a photo · 👀 What's up? · 🔥 That's fire`. Selecting one sends the ping and closes.

### 3.6 More (⋯) menu
- `position:absolute; top:32px; right:0; width:180px; border-radius:14px; background:rgba(28,28,30,.88); backdrop-filter:blur(22px); border:1px solid rgba(255,255,255,.08); box-shadow:0 16px 36px -10px rgba(0,0,0,.7); padding:5px; z-index:8;`
- **Block** row: `16×16` no-entry icon stroke `rgba(255,255,255,.7)`, label `rgba(255,255,255,.85); font-size:13.5px; font-weight:600;`
- **Report** row: `16×16` flag icon stroke `#ff453a`, label `#ff453a`, same size. Rows `padding:10px 11px; border-radius:10px;` hover `rgba(255,255,255,.08)`.

---

## 4. Icons (all inline SVG, 24×24 viewBox unless noted)
- **Ping (circled figure):** 32×32 viewBox — outer `circle r=13.2 stroke rgba(255,255,255,.9) stroke-width 1.5`; head `circle cy=10.6 r=1.9 fill #fff`; shoulders/arms/legs strokes `#fff stroke-width 1.8`.
- **RealMoji (smiley outline):** circle + smile arc + two dot eyes, stroke `#1a1a1a` (on white) or `#2a2a2e` (group white buttons).
- **Wave (hand/person):** stick-figure waving, stroke `#2a2a2e stroke-width 1.9`.
- **Send (paper plane):** filled triangle path `M2.2 21.3 22.5 12 2.2 2.7l.1 7.3 12 1.9-12 2z`.
- **Anon (domino mask):** `rect x3 y9 w18 h6.5 rx3.25` + two cutout eyes.
- **Identity swap badge:** double arrows `M17 2.5 21 6.5 17 10.5M21 6.5H9M7 13.5 3 17.5 7 21.5M3 17.5h12`.
- **Verified seal, comment bubble, chevron, more-dots, block, report, camera** — as described in their sections.

---

## 5. Color tokens

| Token | Hex / value | Usage |
|---|---|---|
| Page black | `#000000` | background + inter-card gap |
| Comment surface (solo) | `#18181a` | solo comment card |
| Comment surface (group) | `#101012` | group comment card |
| Input pill (solo) | `rgba(255,255,255,.055)` | composer field |
| Input pill (group) | `#1a1a1e` | group composer field / tiles |
| Ping button | `#131315` | ping circle |
| Dark chip | `#1c1c1e` / `#2a2a2e` | anon avatar, dark surfaces |
| Light pill | `#faf8f4` | live pill |
| White button | `#f7f7f5` / `#fff` | group action buttons, RealMoji |
| Text primary | `#fff` | names, comments |
| Text 50% | `rgba(255,255,255,.5)` | dates |
| Text 40% | `rgba(255,255,255,.4)` | comment toggle, meta |
| Text 32–35% | `rgba(255,255,255,.28–.35)` | placeholders, timestamps |
| Live label dark | `#2e2a22` / `#17171a` | text on light pill |
| Accent cyan | `#37c9e6` / `#22c9e8` | live dot, send (group), links |
| Accent red | `#ff453a` | report |
| Verified blue | `#3897f0` | verified seal |
| Group gradient | `#3ddc97 → #10b981` | group glyph/tiles/panes |
| Identity gradient | `#b9ad97 → #a79bbf` (140–150deg) | real-identity avatar |
| Reactor pastels | `#b9ad97 #9db29a #a79bbf #ddd6c8 #d9e0d4 #e2ddec #eadfe0 #d7e2e6 #e6ddc9 #e6d9d4 #d3ddd9 #e6d9d4` | avatar placeholders |
| RealMoji selfies | `#c9b79c #9db29a #a79bbf #d5a8a0 #8fa8bd` | your saved reactions |
| Hairline | `rgba(255,255,255,.05–.09)` | borders, dividers |

---

## 6. Typography summary
- **Nunito:** author name (15.5px/700 solo), group name (17.5px/800), live pill label (13px/800 solo · 11.5px/800 group).
- **Inter:** everything else. Sizes used: 15px (caption) · 15.5px (username) · 14px · 13.5px · 13px · 12.5px · 12px · 11.5px · 10.5px · 10px · 9.5px · 9px. Weights 800/700/600/500/400.
- **Monospace:** group meta line (12.5px).
- Line-height 1.3–1.45 for comment/caption text. Uppercase micro-labels use `letter-spacing:.07–.08em`.

---

## 7. Interactions & state

Per-card state (keyed by post id): `live`, `reactions`, `emojiPicker`, `ping`, `more`, `cmts` (comments expanded), `anonMap` (per-post identity), `pickedEmojiMap` (per-post RealMoji selection).

- **Live pill → dropdown** (§3.3). One open at a time.
- **Reactions cluster (left) → strip** expands below the photo (§1.5).
- **RealMoji button (right) → selfie picker** (§3.3b); pick fills the button, re-pick removes.
- **Ping button → prompt dropdown** (§3.4); pick sends + closes.
- **Comment toggle → expand/collapse** the comment card, chevron rotates.
- **Identity avatar → toggle anon/real** for that post's composer (swaps avatar, placeholder text).
- **More (⋯) → block/report menu.**
- **Dismiss rules (all panels):**
  - Capture-phase `pointerdown` anywhere outside the open panel or its trigger closes it. Each panel/trigger tags itself with a keep-attribute (`data-live-keep`, `data-rx-keep`, `data-emoji-keep`, `data-ping-keep`, `data-more-keep`, `data-cmt-keep`); the handler closes any panel whose target isn't inside its matching keep element.
  - **Window scroll** closes live / reactions / emoji / ping / more panels.
- **No entrance animations** — panels appear/disappear instantly (matches production).

---

## 8. Tweakable props (design-time)
- `photoRadius` — range 0–40px, step 2, default **26** (solo photo corner radius).
- `cardGap` — range 0–24px, step 2, default **8** (black gap between cards).
- `showComments` — boolean, default **true**.
- `showCaption` — boolean, default **true**.
- `showPiP` — boolean, default **true** (solo picture-in-picture inset).

---

## 9. Notes for the developer
- Photo is **always 4:5 portrait** for solo posts — build every measurement around a 406px-wide, 507.5px-tall frame (at the 430px column). Group layouts derive their heights from the aspect ratios given (they scale with column width; no fixed pixel heights except the collage `262px` and deck `400px` stage which are tuned to the 430px column — convert to relative units if supporting other widths).
- All overlay dropdowns must escape the photo's clip — keep the outer wrapper `overflow:visible` and only the inner image frame `overflow:hidden`.
- Reaction VIEWING is always **bottom-left**; the react/action buttons are always **bottom-right** — consistent across solo and all four group layouts.
- No raster assets ship here — photos and selfies are user content (`object-fit:cover`); emoji in ping prompts are native Unicode.
