# Feed — Canonical Design Specification (pixel-for-pixel handoff)

Two matching sources of truth: **this document** and **`feed_export.html`** (static HTML/CSS in the same folder). Values are literal pixels at the reference column width **430px**. Reference frame background is pure black.

**Fonts:** Google Fonts — `Inter` (400,500,600,700,800) and `Nunito` (600,700,800). Body default `Inter`. Monospace stack `ui-monospace, SFMono-Regular, Menlo, monospace` (group meta line only). `* { box-sizing: border-box }`.

**Global links:** `a { color:#5ac8e0 }`, `a:hover { color:#7fdcf0 }`.

**Feed container:** outer `min-height:100vh; background:#000; display:flex; justify-content:center;`. Inner column `width:430px; max-width:100vw;`. Each card wrapper: `border-bottom: {cardGap} solid #000;` where **cardGap = 8px** (default; flexible 0–24, step 2). This black border IS the inter-card gap; there is no other card margin.

Two card types share the column: **SOLO** and **GROUP** (4 layouts). Order in the reference data: solo `a`, solo `b`, group single, group collage, group deck, group split.

---

# A. SOLO CARD

Vertical flow: Header → Caption → Photo(+overlays) → Reactions strip (conditional) → Comment card.

## A1. Header
`display:flex; align-items:center; justify-content:space-between; padding:12px 14px 11px;`

**Left group:** `display:flex; align-items:center; gap:11px; min-width:0;`
| Element | Spec |
|---|---|
| Avatar | `width:42px; height:42px; border-radius:50%;` background = post color (e.g. `#8a8f98`). `flex:0 0 auto`. |
| Name+badge row | `display:flex; align-items:center; gap:5px;` |
| Username | font `Nunito`; `font-size:15.5px; font-weight:700; color:#fff;` ellipsis truncation. |
| Verified badge (conditional) | shown only if `post.verified===true`. SVG `15×15px`, seal `fill:#3897f0`, inner check `fill:#fff`. `flex:0 0 auto`. |
| Date line | `color:rgba(255,255,255,.5); font-size:12.5px; font-weight:500; margin-top:1px;` |

**Right group:** `display:flex; align-items:center; gap:12px;`

**Live pill (button):** `display:flex; align-items:center; gap:7px; height:34px; padding:0 13px 0 5px; border-radius:17px; background:#faf8f4; color:#2e2a22; font-family:Inter; font-size:13px; font-weight:700; box-shadow:0 5px 10px rgba(0,0,0,.35);`
- Avatar cluster: three circles `width/height:22px; border-radius:50%; border:1.5px solid #faf8f4;` colors in order `#b9ad97`, `#9db29a`, `#a79bbf`; 2nd & 3rd `margin-left:-9px`.
- Live dot: `width/height:8px; border-radius:50%; background:#37c9e6; box-shadow:0 0 7px 1px rgba(55,201,230,.8);`
- Label: `{hereCount} here`.

**More (⋯) trigger:** `background:none; padding:4px;` icon SVG `22×22px; fill:#fff` (three dots r=2 at x=5,12,19).

## A2. Caption (conditional)
Rendered only if `showCaption===true` AND `post.caption` non-empty.
`padding:0 14px 10px; color:#fff; font-size:15px; font-weight:500; line-height:1.4;`

## A3. Photo block
Outer wrapper: `position:relative; margin:0 12px;` (→ media width = 430−24 = **406px**; `overflow:visible` so overlays escape).
Inner clip: `border-radius:{photoRadius}; aspect-ratio:{post.ratio}; overflow:hidden;`
- **photoRadius = 26px** default (flexible 0–40, step 2). `post.ratio` = `4 / 5` (post a) or `1 / 1` (post b). *Production intent: always 4/5; the 1/1 on post b is a demo of flexibility.*
- Image: `<image-slot>` fills, `object-fit:cover`.
- **Scrim** (child of clip, `position:absolute; inset:0; pointer-events:none;`): `background: linear-gradient(to bottom, rgba(0,0,0,.22) 0%, transparent 18%, transparent 60%, rgba(0,0,0,.42) 100%);`
- **PiP inset** (conditional: `showPiP===true` and solo): `position:absolute; top:14px; left:14px; width:34%; aspect-ratio:3 / 4; border-radius:14px; overflow:hidden; border:2px solid rgba(255,255,255,.9); box-shadow:0 6px 18px -6px rgba(0,0,0,.7);`

### Overlays on the outer wrapper (z-order bottom→top: scrim < action buttons/clusters < live dropdown(z6) < emoji picker < ping dropdown(z9))

**Live dropdown (conditional `isLiveOpen`):** `position:absolute; top:10px; right:12px; width:158px; z-index:6; border-radius:13px; background:rgba(22,22,24,.9); backdrop-filter:blur(20px); border:1px solid rgba(255,255,255,.09); box-shadow:0 12px 28px -10px rgba(0,0,0,.7); padding:8px 10px 9px;`
- Header: `color:rgba(255,255,255,.42); font-size:9.5px; font-weight:700; letter-spacing:.07em; text-transform:uppercase; padding-bottom:7px;` text `here now`.
- Rows: `display:flex; flex-direction:column; gap:7px;` each `display:flex; align-items:center; gap:7px;` dot `5×5px` circle (per-person color) + name `color:rgba(255,255,255,.85); font-size:12px; font-weight:600;` ellipsis.

**Action rail (right):** `position:absolute; right:13px; bottom:14px; display:flex; flex-direction:column; align-items:center; gap:22px;`
- **Ping button:** `width:34px; height:34px; border-radius:50%; background:#131315; box-shadow:0 2px 8px rgba(0,0,0,.4);` icon SVG `24×24` (viewBox 32) white strokes (`stroke:rgba(255,255,255,.9)` circle r=13.2 sw1.5; head fill `#fff`; body `stroke:#fff` sw1.8).
- **RealMoji button:** `width:34px; height:34px; border-radius:50%; overflow:hidden; background:#fff; box-shadow:0 2px 8px rgba(0,0,0,.35);`
  - `notReacted`: smiley SVG `21×21`, `stroke:#1a1a1a; stroke-width:1.9` (circle r=9.2, smile arc, two eyes r=.9 `fill:#1a1a1a`).
  - `hasReacted`: fills with a `34×34` circle `background:{pickedColor}` (the picked selfie color; default `#c9b79c`).

**Ping dropdown (conditional `isPingOpen`):** anchored to ping button, `position:absolute; bottom:0; right:42px; width:186px; border-radius:14px; background:rgba(20,20,22,.92); backdrop-filter:blur(22px); border:1px solid rgba(255,255,255,.09); box-shadow:0 14px 34px -10px rgba(0,0,0,.7); padding:5px; z-index:9;`
- Each prompt (button): `display:flex; align-items:center; gap:9px; width:100%; padding:9px 10px; border-radius:10px; background:transparent;` hover `background:rgba(255,255,255,.08);` — emoji `font-size:15px` + label `color:rgba(255,255,255,.85); font-size:13px; font-weight:600;`.
- Prompts: `👋 Say hi` · `📸 Post a photo` · `👀 What's up?` · `🔥 That's fire`.

**RealMoji picker (conditional `isEmojiOpen`):** `position:absolute; right:13px; bottom:58px; display:flex; align-items:center; gap:7px; padding:7px 9px; border-radius:32px; background:rgba(20,20,22,.9); backdrop-filter:blur(20px); box-shadow:0 10px 26px -6px rgba(0,0,0,.6);`
- Selfie options: 5 buttons `width:42px; height:42px; border-radius:50%; border:2px solid {ring}; background:{color};` colors `#c9b79c #9db29a #a79bbf #d5a8a0 #8fa8bd`; ring default `rgba(255,255,255,.28)`, selected `#fff`.
- Camera button: `42×42px; border-radius:50%; border:1.5px dashed rgba(255,255,255,.35); background:rgba(255,255,255,.06);` camera icon `19×19`, `stroke:rgba(255,255,255,.75); stroke-width:1.9`.

**Reactions cluster (left, view reactions):** `position:absolute; left:13px; bottom:14px; display:flex; align-items:center;` button.
- Two avatars `34×34px; border-radius:50%; border:2px solid rgba(0,0,0,.55);` colors `#b9ad97`, `#9db29a`; 2nd `margin-left:-13px`.
- Count chip: `height:34px; padding:0 10px 0 17px; margin-left:-13px; border-radius:17px; background:rgba(0,0,0,.5); border:2px solid rgba(0,0,0,.55); color:#fff; font-size:13px; font-weight:700;` text `+{reactions}`.

## A4. Reactions strip (conditional `isReactionsOpen`) — below photo
`padding:12px 0 2px;`
- Heading: `color:rgba(255,255,255,.45); font-size:9.5px; font-weight:700; letter-spacing:.08em; text-transform:uppercase; padding:0 14px 9px;` text `RealMojis · {reactions}`.
- Rail: `display:flex; gap:16px; overflow-x:auto; padding:2px 14px 4px;` (scrollbar hidden). Each item: `width:56px; display:flex; flex-direction:column; align-items:center; gap:7px;`
  - Selfie `56×56px; border-radius:50%; background:{color}; border:2px solid rgba(255,255,255,.12);`
  - Name `max-width:56px; color:rgba(255,255,255,.72); font-size:10.5px; font-weight:600;` ellipsis.

## A5. Comment card (conditional `showComments`)
Container: `margin:10px 8px 0 8px; border-radius:18px; background:#18181a; overflow:visible;`

**Toggle header (button):** `display:flex; align-items:center; gap:7px; padding:9px 14px 6px; background:none;`
- Bubble icon `15×15`, `stroke:rgba(255,255,255,.4); stroke-width:2`.
- Label `color:rgba(255,255,255,.4); font-size:12px; font-weight:600;` — `View all {commentCount} comments` (collapsed) / `Hide comments` (expanded).
- Chevron `12×12`, `stroke:rgba(255,255,255,.35); stroke-width:2.6;` `transform:rotate(0deg)` collapsed → `rotate(180deg)` expanded.

**Collapsed preview (conditional `commentsCollapsed`):** `padding:0 14px 2px; display:flex; flex-direction:column; gap:3px;` — top 2 comments, each one truncated line: username `font-weight:700`, body `rgba(255,255,255,.75)`, `font-size:12.5px; line-height:1.4;`.

**Expanded body (conditional `commentsOpen`):**
- Mini RealMoji rail: `padding:2px 0 8px;`; heading `RealMojis · {reactions}` (`font-size:9px`, same uppercase micro-label style, `padding:0 14px 7px`); rail `display:flex; gap:9px; overflow-x:auto; padding:1px 14px;` items `width:42px; gap:5px;` avatar `42×42px; border:1.5px solid rgba(255,255,255,.14);` name `font-size:9px; color:rgba(255,255,255,.55);`.
- Comment list: `max-height:200px; overflow-y:auto; display:flex; flex-direction:column; gap:9px; padding:10px 14px 4px; border-top:1px solid rgba(255,255,255,.05);` each row: avatar `24×24px; margin-top:1px;`, gap `9px`; username `700` + body `rgba(255,255,255,.78)` at `12.5px/1.4`; timestamp `color:rgba(255,255,255,.28); font-size:10px; font-weight:600; margin-top:2px;`.

**Composer:** `display:flex; align-items:center; gap:8px; padding:7px 12px 9px;`
- Identity avatar (button): `position:relative; width:27px; height:27px;`
  - `isReal`: circle `27×27; background:linear-gradient(140deg,#b9ad97,#a79bbf);`
  - `isAnon`: circle `27×27; background:#2a2a2e;` centered domino-mask SVG `14×14` (`rect fill:#cfcfd4`, eyes `fill:#2a2a2e`).
  - Swap badge (always): `position:absolute; right:-3px; bottom:-3px; width:13px; height:13px; border-radius:50%; background:#3a3a40; border:1.5px solid #18181a;` swap-arrows SVG `7×7` `stroke:rgba(255,255,255,.85); stroke-width:3.6`.
- Input pill: `flex:1; height:28px; padding:0 12px; border-radius:14px; background:rgba(255,255,255,.055);` placeholder `color:rgba(255,255,255,.32); font-size:12.5px; font-weight:500;` — `Add a comment…` (real) / `Comment anonymously…` (anon).
- Send button: `width:26px; height:26px; border-radius:50%; background:rgba(255,255,255,.08);` plane icon `13×13; fill:rgba(255,255,255,.55)`.

---

# B. GROUP CARD

Flow: Group header → (live dropdown overlay) → one of 4 photo layouts → Reactions strip (conditional) → RealMoji picker (conditional) → Comment card.

## B1. Group header
`display:flex; align-items:center; justify-content:space-between; gap:10px; padding:14px 14px 12px;`
- Left `display:flex; align-items:center; gap:12px; min-width:0;`
  - Group glyph: `width:44px; height:44px; border-radius:50%; background:linear-gradient(150deg,#3ddc97,#10b981); color:#fff; font-size:17px; font-weight:700;` centered `groupInitial`.
  - Group name: `font-family:Nunito; color:#fff; font-size:17.5px; font-weight:800; letter-spacing:-.2px;` ellipsis.
  - Meta line: `font-family:monospace; color:rgba(255,255,255,.4); font-size:12.5px; margin-top:2px;` e.g. `5 members · 2h ago`.
- Right: **Live pill (compact)** `display:flex; align-items:center; gap:6px; height:29px; padding:0 11px 0 4px; border-radius:14.5px; background:#faf8f4; color:#17171a; font-family:Nunito; font-size:11.5px; font-weight:800;`
  - Cluster: three `18×18px` circles, `border:1.5px solid #faf8f4`, colors `#e8dfd6`,`#cfc6dd`,`#a79bbf`, 2nd/3rd `margin-left:-7px`.
  - Live dot `7×7px; background:#22c9e8`. Label `{hereCount} here`.

**Group live dropdown (conditional `isLiveOpen`):** `position:absolute; top:-4px; right:14px; width:160px; z-index:9; border-radius:14px; background:rgba(20,20,22,.93); backdrop-filter:blur(20px); border:1px solid rgba(255,255,255,.09); box-shadow:0 14px 30px -10px rgba(0,0,0,.75); padding:9px 11px 10px;` (rows identical to solo live dropdown; header alpha `.4`).

## B2. Layout SINGLE (`glayout:"single"`)
Wrapper `position:relative; margin:0 12px;`
- Photo: `border-radius:20px; aspect-ratio:4 / 5; overflow:hidden; background:#1a1a1e;`
- Member tile: `position:absolute; top:5%; left:5%; width:29%; aspect-ratio:175 / 220; border-radius:19px; background:linear-gradient(160deg,#3ddc97,#10b981); border:3px solid rgba(255,255,255,.22); box-shadow:0 10px 26px -8px rgba(0,0,0,.6); color:#fff; font-size:24px; font-weight:700;` centered initial.
- Reactions cluster **bottom-left** `left:16px; bottom:16px;` (34px avatars, `+{reactions}` chip — same as A3 cluster).
- Action buttons **bottom-right** `right:16px; bottom:16px; display:flex; align-items:center; gap:14px;`: **Wave** then **RealMoji**, each `44×44px; border-radius:50%; background:#f7f7f5; box-shadow:0 3px 10px rgba(0,0,0,.35);` icons `24×24; stroke:#2a2a2e` (Wave sw1.9, RealMoji sw1.8).

## B3. Layout COLLAGE (`glayout:"collage"`)
- Tile row: `display:flex; align-items:flex-start; gap:8px; padding:0 0 0 12px; overflow:hidden; height:262px;`
  - Tile 1: `width:33%; aspect-ratio:230 / 340; margin-top:52px; border-radius:11px; overflow:hidden; background:#1a1a1e;`
  - Tile 2: `width:33%; aspect-ratio:227 / 425; border-radius:11px; overflow:hidden; background:#1a1a1e;`
  - Tile 3 (member): `width:25%; aspect-ratio:170 / 290; margin-top:85px; border-radius:11px; background:linear-gradient(160deg,#3ddc97,#10b981); font-size:22px; font-weight:700; color:#fff;`
- Action row (on-card, below tiles): `display:flex; align-items:center; gap:14px; padding:14px 12px 4px;`
  - Reactions cluster **first (left)** — chip variant: `background:rgba(255,255,255,.1); border:2px solid #000;` (avatars `border:2px solid #000`).
  - `margin-left:auto` sub-group holding **Wave + RealMoji** (`44×44` white circles, no shadow) pushed **right**, `gap:14px`.

## B4. Layout DECK (`glayout:"deck"`)
- Stage: `position:relative; height:400px; display:flex; align-items:center; justify-content:center;`
  - Left card: `position:absolute; left:14px; top:42px; width:26%; height:310px; border-radius:14px; overflow:hidden; transform:rotate(-4deg); background:#1a1a1e;`
  - Right card: `position:absolute; right:14px; top:42px; width:26%; height:310px; border-radius:14px; overflow:hidden; transform:rotate(4deg); background:#1a1a1e;`
  - Center card: `position:relative; width:66%; height:385px; border-radius:18px; overflow:hidden; background:#1a1a1e; box-shadow:0 14px 34px -10px rgba(0,0,0,.7);`
    - Count badge: `position:absolute; top:14px; right:14px; height:32px; padding:0 14px; border-radius:16px; background:rgba(20,20,22,.72); backdrop-filter:blur(12px); color:#fff; font-size:13.5px; font-weight:600; letter-spacing:.06em;` text `1 / 9`.
    - Reactions cluster **bottom-left** `left:14px; bottom:14px;` — smaller: avatars `30×30px; margin-left:-12px;`, chip `height:30px; padding:0 9px 0 15px; border-radius:15px; font-size:12px;`.
    - Wave + RealMoji **bottom-right** `right:14px; bottom:14px; gap:12px;` `40×40px` white circles, icons `22×22`.
- Dots row: `display:flex; align-items:center; justify-content:center; gap:7px; padding:12px 0 4px;` — active `width:22px; height:5px; border-radius:3px; background:#fff;` then 8 inactive `5×5px; border-radius:50%; background:rgba(255,255,255,.24);`.

## B5. Layout SPLIT (`glayout:"split"`)
Wrapper `position:relative; margin:0 12px;`
- Grid: `display:flex; gap:3px; aspect-ratio:406 / 640; border-radius:20px; overflow:hidden;`
  - Left pane: `flex:1; overflow:hidden; background:#1a1a1e;` (photo).
  - Right pane: `flex:1; background:linear-gradient(165deg,#3ddc97,#10b981); font-size:30px; font-weight:700; color:#fff;` centered initial.
- Reactions cluster **bottom-left** `left:16px; bottom:16px;` (34px), Wave + RealMoji **bottom-right** `right:16px; bottom:16px; gap:14px;` (44px white circles).

## B6. Group reactions strip (conditional `isReactionsOpen`)
Identical to A4 (heading `RealMojis · {reactions}`, `56×56` avatars, `gap:16px; padding:2px 14px 4px`).

## B7. Group RealMoji picker (conditional `isEmojiOpen`)
Inline card: `display:flex; align-items:center; gap:8px; margin:12px 12px 0; padding:8px 10px; border-radius:32px; background:rgba(24,24,26,.95); border:1px solid rgba(255,255,255,.08); overflow-x:auto;`
- Options `44×44px` circles (`border:2px solid {ring}; background:{color}`), then camera button `44×44px; border:1.5px dashed rgba(255,255,255,.32); background:rgba(255,255,255,.05);` icon `20×20; stroke:rgba(255,255,255,.7)`.

## B8. Group comment card
`margin:12px 12px 0; border-radius:18px; background:#101012; border:1px solid rgba(255,255,255,.07); overflow:visible;` — internal structure, sizes, states, and composer are **identical to the solo comment card (A5)**, except header/preview horizontal padding is `16px` (vs `14px`) and the swap badge border color is `#101012`.

---

# C. Interactive states (all elements)

| Element | Default | Active/expanded | Hover/pressed | Dismiss |
|---|---|---|---|---|
| Live pill | closed | opens live dropdown for that card | — | outside-tap / scroll |
| More (⋯) | closed | opens block/report menu (`top:32px; right:0; width:180px; radius:14px; background:rgba(28,28,30,.88); blur(22px); shadow:0 16 36 -10 rgba(0,0,0,.7); padding:5px; z8`). Rows `padding:10px 11px; radius:10px; gap:9px;` hover `rgba(255,255,255,.08)`. **Block** icon `16` stroke `rgba(255,255,255,.7)`, label `rgba(255,255,255,.85) 13.5px/600`. **Report** icon+label `#ff453a`. | rows lighten on hover | outside-tap / scroll |
| Reactions cluster | shows `+N` | expands reactions strip | — | outside-tap / scroll |
| RealMoji button | smiley (notReacted) | fills with picked selfie color (hasReacted); opens picker | — | picker: outside-tap/scroll |
| RealMoji option | ring `rgba(255,255,255,.28)` | selected ring `#fff`; sets `pickedColor`, closes picker; re-pick clears reaction | — | — |
| Ping button | closed | opens prompt dropdown | prompt rows hover `rgba(255,255,255,.08)` | outside-tap / scroll |
| Ping prompt | — | tap sends ping, closes dropdown | hover bg | — |
| Comment toggle | collapsed (2-line preview, chevron 0°) | expanded (rail+list, chevron 180°) | — | outside-tap (cmts only) |
| Identity avatar | real (gradient) + "Add a comment…" | anon (`#2a2a2e` mask) + "Comment anonymously…" | — | — |
| Live/reactions/emoji/ping/more | — | only one of each open per card (state keyed by card id) | — | capture-phase outside `pointerdown`; window `scroll` closes live/reactions/emoji/ping/more (not cmts) |

No disabled states are defined. No focus styles beyond browser default.

# D. Conditional rendering
- Verified badge: only if `post.verified===true`.
- Caption: only if `showCaption===true` and `post.caption` non-empty.
- PiP inset: only if `showPiP===true` and card is solo.
- Comment card: only if `showComments===true`.
- Group vs solo chosen by `post.group`; group layout by `post.glayout` ∈ {single, collage, deck, split}.
- Reactions strip / RealMoji picker / live dropdown / ping dropdown / more menu / comment expansion: each rendered only when its per-card state id matches.

# E. Animation / transitions
- **None specified.** All panels appear/disappear instantly (no fade, no slide). The only transform is the comment chevron flip (`rotate 0°↔180°`), applied as a static state value with no transition declared — implement as instant unless you choose to add an ease (design does not require it).
- (Earlier iterations had `livePulse`/`ddIn` keyframes; they are **removed** in the current design — do not add entrance animations.)

# F. Flexible / intentionally non-fixed values
- **cardGap** (8px) and **photoRadius** (26px) are design-time tweakables — treat as configurable, not hard constants.
- **Column width 430px** is the reference; on device, derive `width = min(430, screenWidth)` and inset media by 12px per side (media = column − 24). Group `height:262px` (collage) and `height:400px`/`385`/`310` (deck) are tuned to the 430 column — convert to ratios if supporting other widths (aspect ratios given for each tile make this exact).
- `post.ratio` is `1/1` on post b only to demonstrate flexibility; production solo posts are always `4/5`.
- Reactor/comment/selfie **colors are placeholder data** standing in for user photos — replace with real images (`object-fit:cover`).

# G. Color reference (canonical)
`#000000` page/gap · `#18181a` solo comment surface · `#101012` group comment surface · `#1a1a1e` media/tile placeholder · `#131315` ping button · `#2a2a2e` anon avatar · `#3a3a40` swap badge · `#faf8f4` live pill · `#f7f7f5`/`#fff` white buttons · `#fff` primary text · `rgba(255,255,255,.5/.45/.4/.35/.32/.28)` text tiers · `#2e2a22`/`#17171a` text on light pill · `#37c9e6`/`#22c9e8` accent cyan · `#ff453a` report · `#3897f0` verified · gradient group `#3ddc97→#10b981` · gradient identity `#b9ad97→#a79bbf` · pastels `#b9ad97 #9db29a #a79bbf #ddd6c8 #d9e0d4 #e2ddec #eadfe0 #d7e2e6 #e6ddc9 #e6d9d4 #d3ddd9 #e8dfd6 #cfc6dd` · selfies `#c9b79c #9db29a #a79bbf #d5a8a0 #8fa8bd` · hairlines `rgba(255,255,255,.05–.14)`.
