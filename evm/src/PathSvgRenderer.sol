// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {InshellMono76PathGlyphs} from "./InshellMono76PathGlyphs.sol";

/// @notice Canonical on-chain PATH artwork renderer.
/// @dev Layout mirrors the canonical 600x600 PATH text-status composition.
library PathSvgRenderer {
    uint256 private constant _THOUGHT_X = 0;
    uint256 private constant _THOUGHT_WIDTH = 4_200;
    uint256 private constant _WILL_X = 4_800;
    uint256 private constant _WILL_WIDTH = 2_400;
    uint256 private constant _AWA_X = 7_800;
    uint256 private constant _AWA_WIDTH = 1_800;

    function render(
        uint32 thoughtMinted,
        uint32 thoughtQuota,
        uint32 willMinted,
        uint32 willQuota,
        uint32 awaMinted,
        uint32 awaQuota
    ) internal pure returns (string memory) {
        string memory progressClip = string.concat(
            "<clipPath id='path-progress' clipPathUnits='userSpaceOnUse'>",
            _progressRect("thought-progress", _THOUGHT_X, _progressWidth(thoughtMinted, thoughtQuota, _THOUGHT_WIDTH)),
            _progressRect("will-progress", _WILL_X, _progressWidth(willMinted, willQuota, _WILL_WIDTH)),
            _progressRect("awa-progress", _AWA_X, _progressWidth(awaMinted, awaQuota, _AWA_WIDTH)),
            "</clipPath>"
        );
        string memory phrase = _phraseUses();

        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 600 600' width='600' height='600' role='img' aria-label='PATH movement progress' data-renderer='path-text-status' data-rendering='native-svg-paths' data-progress-model='text' data-family='Inshell Mono 76' data-face='Inshell Mono 76 Regular' data-weight='400' data-release-commit='",
            InshellMono76PathGlyphs.releaseCommit(),
            "' data-manifest-sha256='",
            InshellMono76PathGlyphs.manifestSha256(),
            "' data-glyph-json-sha256='",
            InshellMono76PathGlyphs.glyphJsonSha256(),
            "' data-glyph-slice-sha256='",
            InshellMono76PathGlyphs.glyphSliceSha256(),
            "' data-center-x='300' data-center-y='300'>",
            "<rect width='600' height='600' fill='#000000'/>",
            "<defs>",
            InshellMono76PathGlyphs.defs(),
            progressClip,
            "</defs>",
            "<g id='path-title' data-text-layout='centered-group' fill-rule='nonzero' transform='translate(92.64 311.232) scale(0.0432 -0.0432)'>",
            "<g id='remaining' data-status-layer='remaining' fill='#ffffff'>",
            phrase,
            "</g>",
            "<g id='consumed' data-status-layer='consumed' fill='#00ff35' clip-path='url(#path-progress)'>",
            phrase,
            "</g>",
            "</g>",
            "</svg>"
        );
    }

    function _progressWidth(uint32 minted, uint32 quota, uint256 wordWidth) private pure returns (uint256) {
        if (minted == 0 || quota == 0) {
            return 0;
        }

        uint256 cappedMinted = minted > quota ? quota : minted;
        return (wordWidth * cappedMinted) / uint256(quota);
    }

    function _progressRect(string memory id, uint256 x, uint256 width) private pure returns (string memory) {
        return string.concat(
            "<rect id='",
            id,
            "' x='",
            Strings.toString(x),
            "' y='-240' width='",
            Strings.toString(width),
            "' height='1000'/>"
        );
    }

    function _phraseUses() private pure returns (string memory) {
        return string.concat(
            "<use href='#g-T'/>",
            "<use href='#g-H' x='600'/>",
            "<use href='#g-O' x='1200'/>",
            "<use href='#g-U' x='1800'/>",
            "<use href='#g-G' x='2400'/>",
            "<use href='#g-H' x='3000'/>",
            "<use href='#g-T' x='3600'/>",
            "<use href='#g-W' x='4800'/>",
            "<use href='#g-I' x='5400'/>",
            "<use href='#g-L' x='6000'/>",
            "<use href='#g-L' x='6600'/>",
            "<use href='#g-A' x='7800'/>",
            "<use href='#g-W' x='8400'/>",
            "<use href='#g-A' x='9000'/>"
        );
    }

}
