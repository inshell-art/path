// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Canonical on-chain PATH artwork renderer.
/// @dev Glyph paths are the exact Inshell Mono 76 Regular 400 v0.1.0 release.
library PathSvgRenderer {
    string internal constant RELEASE_COMMIT = "6fefbfaf762dce0148fe275baafb8e7dd2077beb";
    string internal constant MANIFEST_SHA256 = "14d734495a8bdc99a98fecbc4f9d76d315c9e2b9fc9b032d5a1fda567258ce11";

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
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 600 600' width='600' height='600' role='img' aria-label='PATH movement progress' data-renderer='path-text-status' data-family='Inshell Mono 76' data-face='Inshell Mono 76 Regular' data-weight='400' data-release-commit='",
            RELEASE_COMMIT,
            "' data-manifest-sha256='",
            MANIFEST_SHA256,
            "'>",
            "<rect width='600' height='600' fill='#000000'/>",
            "<defs>",
            _glyphDefs(),
            progressClip,
            "</defs>",
            "<g id='path-title' transform='translate(92.64 311.232) scale(0.0432 -0.0432)'>",
            "<g id='remaining' fill='#ffffff'>",
            phrase,
            "</g>",
            "<g id='consumed' fill='#00ff35' clip-path='url(#path-progress)'>",
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

    function _glyphDefs() private pure returns (string memory) {
        return string.concat(
            "<path id='g-T' d='M258 0L258 586L42 586L42 656L558 656L558 586L342 586L342 0Z'/>",
            "<path id='g-H' d='M79 0L79 656L163 656L163 381L437 381L437 656L521 656L521 0L437 0L437 309L163 309L163 0Z'/>",
            "<path id='g-O' d='M300 -12Q226 -12 169 29Q112 70 80 146.5Q48 223 48 331Q48 437 80 512.5Q112 588 169 628Q226 668 300 668Q374 668 431 628Q488 588 520 512.5Q552 437 552 331Q552 223 520 146.5Q488 70 431 29Q374 -12 300 -12ZM300 61Q375 61 420.5 133Q466 205 466 331Q466 455 420.5 525Q375 595 300 595Q225 595 179.5 525Q134 455 134 331Q134 205 179.5 133Q225 61 300 61Z'/>",
            "<path id='g-U' d='M301 -12Q237 -12 186.5 14Q136 40 107.5 97Q79 154 79 248L79 656L163 656L163 246Q163 178 181 137.5Q199 97 230.5 79Q262 61 301 61Q341 61 372 79Q403 97 421.5 137.5Q440 178 440 246L440 656L521 656L521 248Q521 154 492.5 97Q464 40 414.5 14Q365 -12 301 -12Z'/>",
            "<path id='g-G' d='M337 -12Q255 -12 190.5 28.5Q126 69 89.5 145Q53 221 53 328Q53 434 90.5 510Q128 586 193.5 627Q259 668 344 668Q409 668 453 642.5Q497 617 525 588L478 535Q454 561 422.5 578Q391 595 344 595Q283 595 237 562.5Q191 530 165.5 471Q140 412 140 330Q140 206 192.5 133.5Q245 61 342 61Q415 61 456 100L456 271L325 271L325 340L533 340L533 64Q502 33 451.5 10.5Q401 -12 337 -12Z'/>",
            "<path id='g-W' d='M110 0L10 657L104 657L152 245Q155 218 157.5 195.5Q160 173 162 149.5Q164 126 165 93L168 93Q174 126 179 149.5Q184 173 189 195Q194 217 200 244L264 488L344 488L406 244Q413 217 418 195Q423 173 427.5 149.5Q432 126 438 93L442 93Q444 126 445.5 149.5Q447 173 449 195Q451 217 454 244L500 657L590 657L494 0L390 0L326 264Q319 294 313 323Q307 352 302 382L299 382Q294 352 289 323Q284 294 276 264L212 0Z'/>",
            "<path id='g-I' d='M95 0L95 71L258 71L258 586L95 586L95 656L505 656L505 586L342 586L342 71L505 71L505 0Z'/>",
            "<path id='g-L' d='M134 0L134 656L216 656L216 71L541 71L541 0Z'/>",
            "<path id='g-A' d='M232 367L201 267L397 267L366 367Q349 422 332.5 476.5Q316 531 301 588L297 588Q281 531 265 476.5Q249 422 232 367ZM32 0L253 656L347 656L568 0L480 0L418 200L180 200L117 0Z'/>"
        );
    }
}
