# Friends Feed Post Card — Design Spec (Stage 1 extraction)

Source: the solo post card in the Friends feed design. Reference column width **430px**; treat 1px = 1dp. Card width is **screen width − 24dp** (content is inset 12dp per side). Photo is **always 4:5 portrait**.

> Scope note for the coder: this design INCLUDES a live-presence pill, a ping button, and a full comment card. The current Flutter pass is header → media → caption → reactions only; the extra widgets are documented here in §7 so they can be skipped or added later without a re-extraction.

---

## 1. LAYOUT HIERARCHY (top → bottom)

1. **Card content column** — no card chrome; elements sit directly on the black scaffold. Vertical separation between cards is an 8dp solid-black bottom border (not a margin).
2. **Header row** — `space-between`, full content width.
   - Left group (`align-items:center; gap:11dp`): Avatar → (Username row + Date line).
   - Right group (`align-items:center; gap:12dp`): Live pill → 3-dot dropdown trigger.
3. **Caption** — full width, left-aligned, below header.
4. **Media area** — inset 12dp each side; overlays positioned against it:
   - Scrim gradient (full bleed, non-interactive).
   - PiP inset (top-left, optional).
   - Live dropdown (top-right, when open).
   - Reaction-viewing cluster (bottom-left).
   - Action rail: Ping (top) + RealMoji (bottom), vertical (bottom-right).
5. **Reactions strip** — below media, only when the cluster is tapped.
6. **Comment card** — rounded surface below media (toggle header → collapsed preview / expanded list → composer).

Alignment: header/caption/comment card are flush to the 12dp content inset; media is inset 12dp; all on-photo overlays are absolutely positioned to the media's edges.

---

## 2. MEASUREMENTS

**Card / column**
- Card width: `screenWidth − 24dp` (12dp inset per side). *Relative.*
- Inter-card gap: **8dp** (black bottom border). *Fixed, tweakable 0–24.*
- No card corner radius (content is not boxed); the only rounded surfaces are the media and the comment card.

**Header** — padding `12 / 14 / 11dp` (top/side/bottom). *Fixed.*
- Avatar: **42dp**, circle. Username↔avatar gap: **11dp**.
- Username↔verified-badge gap: 5dp; verified badge **15dp**.
- Date line: `margin-top 1dp`.
- Right group gap: **12dp**; 3-dot icon **22dp** viewBox, tap target ~30dp.

**Caption** — padding `0 / 14 / 10dp`. *Fixed.*

**Media** — outer wrapper `margin: 0 12dp` → media width = `screenWidth − 24dp`. *Relative width.*
- Aspect ratio **4:5** → height = width × 1.25. *Relative.*
- Corner radius **26dp** (tweakable 0–40). *Fixed default.*
- PiP inset: `top 14 / left 14dp`, width **34%** of media, aspect 3:4, radius **14dp**, border **2dp** `rgba(255,255,255,.9)`.
- Scrim: full inset, gradient (see §3).

**Action rail (bottom-right)** — `right 13 / bottom 14dp; gap 22dp`, vertical.
- Ping button **34dp** circle; icon 24dp viewBox.
- RealMoji button **34dp** circle; smiley icon 21dp.

**Reaction-viewing cluster (bottom-left)** — `left 13 / bottom 14dp`.
- Two avatars **34dp**, 2dp border, overlap `−13dp`.
- Count chip: height **34dp**, `padding 0 10 0 17dp`, radius **17dp**, overlap `−13dp`.

**Reactions strip** — padding `12 / 0 / 2dp`; heading padding `0 14 9dp`; rail `gap 16dp; padding 2 14 4dp`; reactor selfie **56dp**, column gap 7dp; name max-width 56dp.

**Comment card** — `margin: 10 8 0 8dp`, radius **18dp**.
- Toggle header: `padding 9 14 6dp; gap 7dp`; bubble icon 15dp; chevron 12dp.
- Collapsed preview: `padding 0 14 2dp; gap 3dp` (top 2 comments, single line each).
- Expanded RealMoji rail: `padding 2 0 8dp`, rail `gap 9dp; padding 1 14dp`, avatars **42dp**.
- Expanded comment list: `max-height 200dp; overflow-y auto; gap 9dp; padding 10 14 4dp; border-top 1dp`. Row avatar **24dp**, gap 9dp; timestamp `margin-top 2dp`.
- Composer: `padding 7 12 9dp; gap 8dp`. Identity avatar **27dp** + swap badge **13dp** (offset `−3/−3dp`). Input pill `flex:1; height 28dp; padding 0 12dp; radius 14dp`. Send button **26dp** circle; plane icon 13dp.

**Live pill (header)** — height **34dp**, `padding 0 13 0 5dp`, radius **17dp**, gap 7dp. Cluster avatars **22dp** (border 1.5dp, overlap −9dp); live dot **8dp**; label 13dp.

---

## 3. COLORS

| Element | Hex / value | Constant? |
|---|---|---|
| Page / scaffold + inter-card gap | `#000000` | theme (scaffold) |
| Comment card surface | `#18181A` | one-off |
| Composer input pill | `rgba(255,255,255,0.055)` | one-off |
| Ping button bg | `#131315` | one-off |
| Anon avatar bg | `#2A2A2E` | one-off |
| Swap badge bg | `#3A3A40` (border `#18181A`) | one-off |
| Live pill bg | `#FAF8F4` | theme (light-pill) |
| RealMoji button bg | `#FFFFFF` | one-off |
| Text primary | `#FFFFFF` | theme |
| Text — date | `rgba(255,255,255,0.5)` | theme (secondary) |
| Text — comment toggle / meta | `rgba(255,255,255,0.4)` | theme (tertiary) |
| Text — placeholder / timestamp | `rgba(255,255,255,0.28–0.35)` | one-off |
| Text on light pill | `#2E2A22` | one-off |
| Accent cyan (live dot, send) | `#37C9E6` | theme (accent) |
| Report / destructive | `#FF453A` | theme (danger) |
| Verified seal | `#3897F0` | theme |
| Identity gradient (real) | `linear-gradient(140deg,#B9AD97,#A79BBF)` | one-off |
| Cluster chip / dark scrim panels | `rgba(0,0,0,0.5)` | one-off |
| Reactor pastels | `#B9AD97 #9DB29A #A79BBF #DDD6C8 #D9E0D4 #E2DDEC #EADFE0 #D7E2E6 #E6DDC9` | data |
| RealMoji selfies | `#C9B79C #9DB29A #A79BBF #D5A8A0 #8FA8BD` | data |
| Hairline borders | `rgba(255,255,255,0.05–0.09)` | theme |
| Media scrim | `linear-gradient(to bottom, rgba(0,0,0,.22) 0%, transparent 18%, transparent 60%, rgba(0,0,0,.42) 100%)` | one-off |

---

## 4. TYPOGRAPHY

| Role | Family | Weight | Size | Tracking / line-height | Color |
|---|---|---|---|---|---|
| Username | **Nunito** | 700 | 15.5dp | −, 1.2 | `#FFF` |
| Date line | Inter | 500 | 12.5dp | −, 1.2 | `rgba(255,255,255,.5)` |
| Caption | Inter | 500 | 15dp | −, 1.4 | `#FFF` |
| Live pill label | **Nunito** | 700 | 13dp | − | `#2E2A22` |
| Comment toggle label | Inter | 600 | 12dp | − | `rgba(255,255,255,.4)` |
| Comment username | Inter | 700 | 12.5dp | −, 1.4 | `#FFF` |
| Comment body | Inter | 400 | 12.5dp | −, 1.4 | `rgba(255,255,255,.78)` |
| Comment timestamp | Inter | 600 | 10dp | − | `rgba(255,255,255,.28)` |
| Reactor name | Inter | 600 | 10.5dp | − | `rgba(255,255,255,.72)` |
| Strip / rail micro-label | Inter | 700 | 9–9.5dp | +0.08em, uppercase | `rgba(255,255,255,.45)` |
| Cluster count `+N` | Inter | 700 | 13dp | − | `#FFF` |
| Composer placeholder | Inter | 500 | 12.5dp | − | `rgba(255,255,255,.32)` |

Load Inter (400–800) and Nunito (600–800). Nunito is display-only (names, live label); Inter everywhere else.

---

## 5. COMPONENT STATES

**Media — loading:** shimmer/solid `#1A1A1E` placeholder at the same 4:5 frame and 26dp radius; fade image in on load. **Empty (no image):** same `#1A1A1E` fill.

**Reactions — empty (no reactors):** hide the bottom-left cluster; RealMoji action button still present. Strip is not openable until ≥1 reactor.

**Comment card — collapsed (default):** toggle header (`View all {N} comments`) + 2-line preview. **Expanded:** chevron rotates 0→180°, reveals RealMoji rail + scrollable list (max-height 200dp), instant (no animation).

**Identity — real vs anon:** real = gradient avatar + `Add a comment…`; anon = `#2A2A2E` domino-mask avatar + `Comment anonymously…`. Swap badge always visible to signal togglability.

**Dropdown (3-dot) — open:** `position:absolute; top:32dp; right:0; width:180dp; radius:14dp; background:rgba(28,28,30,.88); backdrop-filter:blur(22); border:1dp rgba(255,255,255,.08); box-shadow:0 16 36 −10 rgba(0,0,0,.7); padding:5dp.` Rows: `padding 10 11dp; radius 10dp; gap ~9dp`, icon 16dp + label 13.5dp/600; hover `rgba(255,255,255,.08)`.
- Own post: **Edit caption**, **Delete post** (red `#FF453A`), **Copy link** — divider 1dp `rgba(255,255,255,.06)` above destructive item.
- Others' post: **Report** (red), **Block user** (red), **Copy link**.
- *If implemented as a bottom sheet instead:* bg `#1A1A1A`, top corners 20dp, drag handle 36×4dp `#3A3A3A` 8dp from top, rows 52dp / 16dp side padding, destructive rows red with a divider above.

---

## 6. INTERACTION NOTES

- **Live pill** → opens presence dropdown (top-right of media), list of who's here now. One panel open at a time.
- **3-dot** → opens block/report (or edit/delete) menu.
- **Reaction cluster (left)** → expands the horizontal RealMoji strip below the media.
- **RealMoji button (right)** → opens the selfie picker (5 saved selfies + camera-capture button); tap fills the button with that selfie, re-tap removes.
- **Ping button (right)** → opens the prompt dropdown; picking a prompt sends the ping and closes.
- **Comment toggle** → expand/collapse; chevron rotates.
- **Identity avatar** → toggles anon/real for that composer.
- **Dismiss:** capture-phase outside-tap closes any open panel; window scroll closes live/reactions/ping/emoji/more.
- **Animations:** none beyond media fade-in (and chevron rotate). Panels appear instantly. *(A bottom-sheet dropdown may slide up per platform convention.)*

---

### Reference constants (for a 375dp frame)
- Screen 375 → card width **351dp** (375 − 24). Media 351 × 4:5 = **~439dp** tall.
- Avatar 42 · RealMoji/Ping/cluster 34 · reactor selfie 56 · card gap 8 · media radius 26 · comment card radius 18.
- Derive card/media width from `MediaQuery.of(context).size.width − 24`; keep all other values fixed dp.
