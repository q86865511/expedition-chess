# Presentation UI visual pilot

This directory contains the selected T13 candidate set only. It is not an
authorization to start production art or the `content-production` slice.

Status: `user_approved` on 2026-07-29. The user explicitly accepted the
`not_exposed_by_builtin_image_gen` seed provenance limitation.

Contents:

- five original character pilots: player cost 1/3/5, one monster, one boss;
- four 64×64 board directions and one 256×256 portrait for each character;
- one three-quarter camp corner;
- one core UI pilot;
- 720p/1080p/1440p plus 4:3 and 16:10 visual-fit screenshots;
- default/protanopia/deuteranopia/tritanopia UI screenshots;
- target palette, complete prompt provenance, and deterministic processing script.

The large chroma and color-mode sources are retained because every one is used
to derive a selected candidate. No discarded ImageGen variant is included.
The built-in image generator does not expose a seed; provenance records that
limitation explicitly and uses source/final SHA-256 identity instead.

T13 is complete. This approval authorizes wave6/T15 validation for the
`presentation-ui` slice; it does not authorize `content-production` or Git
operations.
