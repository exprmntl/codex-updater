# Contributing

1. Open an issue describing the behavior or change.
2. Keep the helper dependency-free and macOS-only.
3. Run `zsh -n bin/codex-updater` and `./tests/test.sh`.
4. Include tests for behavior changes.

Changes must preserve these safety properties: no custom download path, no direct app replacement, no force-kill, no `sudo`, and signature verification before quitting Codex.
