# Inshell Mono 76 provenance

## Upstream

- Project: Adobe Source Code Pro
- Repository: https://github.com/adobe-fonts/source-code-pro
- Pinned release commit: `803b7e23ec97ae58b6232ea76519a76d428ba268`
- Release package version: `2.42.0`
- Font version: `2.042`
- Input: `SourceCodePro-Regular.ttf`
- PostScript name: `SourceCodePro-Regular`
- Weight: `400`
- TTF SHA-256:
  `74bd80d3e42a08517cd7e1108ba3d86f2da29ac0f3065be95e0357956ab9db37`
- Restricted path-stream SHA-256:
  `e90b269f15f3c5f6ac6e71244f2120198d4b7196010b158a51b43a1ea4409d05`

## Transformation

The extraction selects the declared 76 Unicode characters and converts their
native TrueType outlines into absolute SVG `M`, `L`, `Q`, `C`, and `Z`
commands.

The following are preserved:

- native outline coordinates;
- native weight geometry;
- 1000 units per em;
- baseline `0`;
- fixed advance `600`;
- metrics-only SPACE.

The following are not performed:

- 8×8 cell fitting;
- horizontal or vertical scaling;
- baseline translation in canonical data;
- synthetic emboldening;
- quantization;
- path simplification.

SVG rendering performs only the necessary placement, uniform size scaling,
and y-axis flip in the wrapper transform. The canonical glyph paths remain
y-up native font data.

## Naming and ownership

`Inshell Mono 76` is the primary name of this restricted, format-converted
Modified Version. `Source Code Pro` and Adobe are used only for factual
provenance and attribution.

Inshell owns the package name, repertoire contract, encoding, renderer,
verification system, and original integration code. The Source Code Pro
letterform geometry remains font software governed by the SIL Open Font
License 1.1.
