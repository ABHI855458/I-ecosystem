# Claude Code prompt — Group Post Cards + Reaction Capture (Flutter)

Copy everything below the line into Claude Code, with this folder attached.

---

Implement two things in our Flutter app from the attached design handoff package:

**A. Four group-post feed cards** — see `README.md` ("Screens / Cards" + "Interactions") and `reference.html` (working HTML/CSS/JS prototype, including the card-3 swipe transition).

**B. A "Send a reaction" camera screen** — see `README-camera.md` and `reference-camera.html` (working prototype of the camera, filter rail, fixed shutter, and both center-selection carousels).

Rules:
- The reference HTML files are the visual source of truth. Match spacing, radii, sizes, colors, and timing values exactly; do not redesign.
- Recreate as Flutter widgets using our existing theme/text styles where they map. Do not port the HTML/CSS literally.
- Photo and selfie areas in the card references are striped placeholders standing in for real user images — wire them to our actual image data at the same aspect ratios and container shapes.
- Get the two interactions exactly right: the card-3 photo swipe (drag threshold, rotation, the two cards behind un-stacking as a function of drag progress) and the center-selection carousels (selection follows the item nearest the center line; taps animate to center; rails rest centered on a middle item).
- Never fail silently on camera permission — render the in-viewfinder error states specified in `README-camera.md`.
- Keep it to: one widget file per card layout, one for the reaction screen, plus small models for filters/reactions.

Ask me before adding any screen, field, or copy that isn't in the specs.
