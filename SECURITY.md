# Security

## Trust model

Codex Updater does not download, extract, copy, or replace application code. It delegates installation to the Sparkle framework bundled with Codex.

Before requesting a quit, it verifies both the installed application and staged update using:

- bundle ID `com.openai.codex`
- Apple Developer team ID `2DC432GLL2`
- `codesign --verify --deep --strict`

The helper never uses `sudo`, never force-kills Codex, and makes no network requests.

The local native guard requires Accessibility permission to read and act on Codex's quit dialog. It verifies the target PID's executable path and bundle ID, then requests a normal application termination. The default `idle-only` policy accepts only an exact known English dialog stating that scheduled tasks will not run while Codex is closed. The explicit `always` policy also accepts known warnings about active tasks and pending worktrees; this can interrupt work. Unexpected text in a recognized quit dialog is canceled under either policy. It does not disable Codex's quit confirmation globally. Missing permission defers before requesting a quit. Other dialog structures/locales remain unapproved.

Settings are a validated property-list dictionary, never shell code. Invalid files prevent automatic updates; changes are validated before an atomic write. The `always` setting does not bypass the update window, app identity checks, code signatures, or the prohibition on force-killing the app.

The test-only native guard accepts a separate fixture bundle ID instead of Codex's bundle ID. Production builds do not enable this test mode.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for `exprmntl/codex-updater`. Do not open a public issue for an unpatched security problem.
