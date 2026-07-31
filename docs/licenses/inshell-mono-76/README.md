# Inshell Mono 76 PATH glyph subset

PATH embeds only the nine Inshell Mono 76 Regular 400 outlines needed to render
`THOUGHT WILL AWA`: `T`, `H`, `O`, `U`, `G`, `W`, `I`, `L`, and `A`.

The canonical subset is `evm/glyphs/inshell-mono-76-path-400.json`. It pins the
font package release, upstream source, metrics, each SVG path, and each path
SHA-256. `evm/src/InshellMono76PathGlyphs.sol` is generated from that subset.

Verification:

```bash
npm run evm:glyphs:check
```

Refreshing from an explicitly supplied, exact local `@inshell/mono-76` v0.1.0
package checkout:

```bash
node evm/scripts/generate-path-glyphs.mjs \
  --import-from /absolute/path/to/@inshell/mono-76
```

The glyph geometry is Font Software under the SIL Open Font License 1.1. The
generator, layout, and Solidity integration code remain under the PATH MIT
license. Redistributed glyph geometry must retain `LICENSE-OFL.md` and
`NOTICE.md`.
