# T13 visual pilot provenance

## Generation

- Date: 2026-07-29
- Mode: Codex built-in `image_gen`
- Taxonomy: `stylized-concept` and `ui-mockup`
- Model-native seed: not exposed by the built-in tool
- Source identity: preserved by the SHA-256 inventory produced by
  `tools/validate-presentation-pilot.ps1`
- Originality constraints: no named artist, franchise, trademark, logo, or
  existing character reference was supplied; no watermark was requested.
- Initial visual review: no obvious logo, watermark, readable copied text, or
  direct franchise identifier is visible. This is not a reverse-image search
  or a legal originality opinion.

## Character sheet prompt

```text
Use case: stylized-concept
Asset type: original pixel-art tactical-fantasy game character pilot sprite sheet
Primary request: create one cohesive production pilot sheet containing exactly five original characters: a nimble cost-1 player scout, an armored cost-3 player warden, an arcane cost-5 player sovereign, one hostile forest monster, and one imposing three-phase boss. Each character must have four readable board directions (front, back, left, right) plus one larger portrait bust.
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background for local background removal; no floor plane, shadows, gradients, texture, lighting variation, or frame background.
Style/medium: crisp hand-authored high-readability pixel art, 32-bit tactical fantasy, strong silhouettes, restrained clustered pixels, no photorealism, no painterly blur, no references to existing game franchises or artists.
Composition/framing: exact clean contact sheet, five horizontal rows (one character per row), five columns (front/back/left/right/portrait); each directional sprite centered inside an implied square 64px board canvas with generous padding; portraits larger but aligned; consistent scale within columns; no overlap.
Color palette: cohesive dark navy, warm parchment, amber, teal and muted crimson; every character also distinguished by silhouette, shape, emblem and equipment, not color alone. Do not use #ff00ff anywhere in subjects.
Accessibility cues: player/enemy affiliation, rarity tier, damage role and boss danger must each have visible non-color shape/symbol cues integrated into costume or silhouette.
Constraints: exactly five characters and twenty direction sprites plus five portraits; original designs only; no text, labels, numbers, logos, trademarks, watermark, UI chrome, cast shadows, contact shadows, glow spilling into the background, semi-transparent smoke, fur wisps, or extra props. Pixel edges must be crisp and isolated for chroma-key removal.
```

Built-in output id: `call_pxuhVAmJNhtRY37cmNbqgNdI`.

## Camp prompt

```text
Use case: stylized-concept
Asset type: original pixel-art tactical-fantasy camp environment pilot
Primary request: a polished three-quarter-view camp corner for a roguelite auto-battler, showing one coherent playable hub corner with a forge, expedition planning table, compact training yard, supply chest, and lantern-lit path; no characters.
Scene/backdrop: self-contained camp environment at dusk, framed as a game scene tile, no transparent background.
Style/medium: crisp hand-authored 32-bit pixel art, high readability at 640x360 world scale, strong material clusters, original tactical fantasy design, no photorealism, no painterly blur, no references to existing franchises or artists.
Composition/framing: three-quarter top-down/isometric-ish view, wide 16:9 composition, clear walkable foreground and five visually distinct facility hotspots, uncluttered center space reserved for unit navigation.
Lighting/mood: warm amber lanterns against cool navy dusk, welcoming but expedition-ready.
Color palette: dark navy, warm parchment, amber, teal, muted crimson, stone gray and timber brown; facility identity must also use unique silhouettes and symbols, not color alone.
Accessibility cues: each facility has a distinct roofline/object silhouette and a simple non-text emblem; path edges and interactable zones remain readable in grayscale.
Constraints: original design only; no text, labels, numbers, logos, trademarks, watermark, characters, modern objects, excessive bloom, tiny decorative clutter, or UI overlay.
```

Built-in output id: `call_woJkh5Lv5QTiw63HrJl8HM8w`.

## Core UI prompt

```text
Use case: ui-mockup
Asset type: original pixel-art tactical-fantasy core game UI pilot
Primary request: a polished shippable 16:9 game interface mockup for a roguelite auto-battler at 1280x720 UI reference, with a central 8x8 tactical board view, top resource bar, left roster/shop panel, right encounter and trait panel, bottom action bar, one open two-level tooltip, a visible keyboard focus state, unit health/status, rarity and danger cues.
Style/medium: crisp pixel-art game UI, original dark tactical fantasy, practical readable hierarchy rather than concept-art decoration, sharp nearest-neighbor edges.
Composition/framing: full-screen landscape interface with safe margins; central board remains dominant; panels use modular 9-slice construction; buttons have clear idle/hover/focus/disabled states shown in a compact component strip.
Color palette: dark navy, warm parchment, amber, teal, muted crimson, off-white; high contrast. Every enemy/player, rarity, damage type, status and danger distinction must also use a unique shape, border pattern, icon or label-like glyph, never color alone.
Accessibility: clearly visible thick keyboard focus frame with corner notches; reduced-motion-friendly static state; tooltip nesting shown at no more than two levels; large readable CJK-capable text blocks represented by clean pseudo-glyph lines rather than real words; 100/125/150% scale-safe spacing.
Text: no real readable language, no letters, no numbers; use abstract pseudo-glyph bars only.
Constraints: original design only; no logos, trademarks, watermark, copyrighted character designs, tiny illegible text, excessive glow, photorealism, mobile UI, or decorative clutter that obscures controls.
```

Built-in output id: `call_NgWDANU9suQwTy9fMTv9p334`.

## Color-vision edit prompts

Each edit used `assets/pilot/core-ui.png` as the only target and preserved
layout, content, icons, focus, tooltips, pseudo-glyphs, spacing, scale, crop,
pixel sharpness, and non-color cues. Only the palette mapping changed.

- Protanopia: replace red/green distinctions with luminance-separated amber,
  cyan, blue-gray, white, and patterned borders. Output id
  `call_7pPZKBL59l0nYkjavrvybLMW`.
- Deuteranopia: replace red/green distinctions with luminance-separated warm
  gold, cool cyan, violet, off-white, and patterned borders. Output id
  `call_Gg1kuWTG69iFtnWgKDxN6PB7`.
- Tritanopia: replace blue/yellow distinctions with luminance-separated
  magenta, coral, teal-gray, off-white, and patterned borders. Output id
  `call_auKrjiEoXcEGnxVaEL2NrArK`.

All three prompts also required no new/removed objects, no text, and no
watermark.

## Processing

1. The character source used a flat magenta chroma background.
2. Installed helper:

   ```text
   remove_chroma_key.py
   --auto-key border
   --soft-matte
   --transparent-threshold 12
   --opaque-threshold 220
   --despill
   ```

   Detected key: `#f702f7`; transparent pixels:
   `1027460/1573044`; partially transparent pixels:
   `79993/1573044`.
3. `tools/render-presentation-pilot.ps1` divides the selected character sheet
   into a deterministic 5×5 grid, derives alpha bounds, and fits the first four
   cells of each row into transparent 64×64 board canvases. The fifth cell is
   fitted into a transparent 256×256 portrait.
4. The same script uses nearest-neighbor, no smoothing, pixel-offset half, and
   dark-navy letterboxing to create 720p/1080p/1440p, 4:3, and 16:10
   screenshots. Three generated color-mode sources are fitted to 1280×720 with
   the same parameters.

No discarded large source is stored in the project.
