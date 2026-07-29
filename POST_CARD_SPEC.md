# Post Card — Final Spec

Reference image: `design-refs/Screenshot 2026-07-29 at 11.21.04 AM.png`

This spec applies to **anonymous posts only**.

## Structure, top to bottom

### 1. Text block (above the image, NOT overlapping it)
- The ghost prompt question the user answered (small, semi-bold, slightly emphasized).
- Below it: the user's typed caption about the image (regular weight, softer/dimmer color).
- Both left-aligned, padded consistently with the image's left edge.

### 2. Identity row
Matches the reference layout position — small circle + adjacent info, sitting above the image like the reference's "todd.curtis" row.

- Small circular avatar = the ANON PERSONA icon/logo — NEVER the real profile photo, NEVER a real name. If the user hasn't set a persona image, show the app's default anon mask/logo glyph.
- Next to the circle: NO name text. Instead show:
  a. Department/branch tag (e.g. "CSE") — small chip/tag style.
  b. The legend/tier indicator (the anon score tier treatment) — glow ring around the persona circle, or compact tier badge — reuse the existing tier-glow component. Must be visible and prominent (the status signal) but small, not a big number box.

### 3. Image
- Rounded corners (~16–20px), matching the reference's soft curve.
- Image fills the card width with a small inset gap on the left side (like the reference — not edge-to-edge full bleed).
- Full opacity — no dimming, no washed-out overlay.

### 4. Action icons
Bottom-right, on the image's lower-right corner area, exactly like the reference's send + heart placement.

- Two icons only: ping (send/paper-plane style) and reaction (heart).
- Positioned lower-right of the image, in that white rounded notch/corner cutout style the reference shows.
- Thin outline style, minimal.

### 5. Below the image
- Row 1: BeReal-style face reactions of others who reacted — horizontal row of small circular selfie thumbnails, each with a tiny emoji badge at its bottom-right (like BeReal RealMojis). Horizontally scrollable if many. If zero reactions, show nothing (no empty row).
- Row 2: Comment access — "View all X comments" text row, tapping opens the existing comment sheet.

## Hard rules — never violate

- NO real name anywhere on the card.
- NO real profile photo anywhere on the card. The circle is ALWAYS the anon persona icon or default logo glyph.
- NO timestamp anywhere on the card.
- NO song/audio bar.
- On the ANONYMOUS feed: face reactions are NOT shown (emoji-only reactions there, existing `allowFaceReactions=false` behavior). Face-reaction row applies to Friends/Everyone feeds only.
- Text-only posts (no image) use the separate compact `TextPostCard` — do not render an empty image area.
