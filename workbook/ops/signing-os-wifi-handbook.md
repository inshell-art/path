# Signing OS Wi‑Fi Handbook

## Purpose
Use network on the Signing OS as a controlled utility, not as normal internet access.

## Core rule
Default state: **Wi‑Fi off**.

Turn Wi‑Fi on only for a bounded task. Turn it off immediately after.

## Two allowed online modes

### 1) Maintenance mode
Use network only for:
- macOS updates
- tool updates
- Ledger firmware/app updates
- repo/bootstrap tasks

### 2) Run mode
Use network only for:
- fetching the exact pinned repo state
- fetching the exact bundle/artifact
- read-only RPC checks
- Safe/RPC signing and execution
- postconditions

## Never mix maintenance and a serious run
Do updates in a separate session.
Reboot.
Then do the real run later.

Do not install packages, patch tools, or modify the environment mid-run.

## Allowed network use during a serious run
Only:
- Git/GitHub fetch for the exact pinned commit or bundle
- RPC provider traffic
- Safe UI / Safe service, only if the run actually needs it

## Forbidden network use during a serious run
No:
- email
- chat
- social
- search
- docs browsing
- cloud storage
- random package installs
- "just checking something quickly"
- cloud agents / Codex cloud

## Trusted network discipline
Use only:
- your own WPA2/WPA3 Wi‑Fi, or
- your own hotspot

Never use:
- café Wi‑Fi
- hotel Wi‑Fi
- airport Wi‑Fi
- conference Wi‑Fi
- coworking Wi‑Fi

## Better home setup
Prefer:
- a dedicated SSID/VLAN for the Signing OS
- a strong unique Wi‑Fi password
- no guest devices on that segment

## Radios and sharing
Keep off unless specifically needed:
- Bluetooth
- AirDrop
- Handoff / Universal Clipboard
- file sharing
- screen sharing
- remote login / SSH

Keep firewall on.

For Ledger Nano S Plus specifically, Bluetooth is unnecessary.

## Cloud sync
Disable or avoid:
- iCloud Drive
- Desktop/Documents sync
- clipboard sync
- notes sync
- screenshot sync

## Browser discipline
If a browser is required:
- use one dedicated browser or one dedicated profile
- no personal login
- no extension sprawl
- no saved sessions
- no random tabs
- open only the exact URLs needed for the run

## Repo discipline while online
Do not `git pull main` and run blindly.

Do:
- fetch
- check out the exact pinned commit in detached HEAD
- keep the tree clean
- do not edit code during the run

## Treat everything fetched online as untrusted until verified locally
That includes:
- GitHub repo state
- CI bundles
- Safe payloads
- RPC-returned state

Verify locally before approval:
- commit
- run ID
- manifest/hash
- chain ID
- nonce
- addresses
- Safe tx hash / intent binding

## Secrets rule
Secrets never travel over the network as part of the run.

Keep local-only on the Signing OS:
- keystore
- password file or local vault DB
- mnemonic / recovery material
- secret `.env`

Online fetch is for code, bundles, and chain/service state, not privileged secret material.

## Keep the network-on window short
Good serious-run pattern:
1. Wi‑Fi on
2. fetch exact repo/bundle
3. verify
4. sign/apply
5. postconditions
6. Wi‑Fi off

## Log the online session
Record:
- date/time
- network used
- commit
- run ID
- bundle source
- RPC host
- what was signed/applied

## Hard-stop conditions
Stop immediately if:
- wrong chain ID
- wrong host/domain
- unexpected browser redirect
- unexpected Ledger prompt
- unexpected blind-signing request
- bundle/commit mismatch
- you feel the need to browse for help mid-run
- an agent suggests patching code during the run

## Human vs machine split
Human judgment is for:
- right machine
- right network
- right run
- right target
- right Ledger confirmation

Human improvisation is **not** for:
- patching scripts
- retyping high-entropy values
- browsing to figure things out during apply

## One-line policy
Use Wi‑Fi on the Signing OS only in short, trusted, purpose-limited sessions, and never let the Signing OS become a normal online computer.
