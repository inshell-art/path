# scripts/ops/networks

Optional network-specific configs for ops scripts.

Keep secrets out of the repo. If you store network configs here, use
placeholders only and load real values from:

  ~/.config/inshell/path/env/<network>.env

Suggested pattern:
- scripts/ops/networks/<network>.env.example (placeholders)
- source ~/.config/inshell/path/env/<network>.env before running scripts
