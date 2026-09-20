# Changelog

## 0.2.1 - 2026-09-20

- Rename the project, macOS app, and GitHub repository to Codex Updater (`exprmntl/codex-updater`).
- Add `codex-updater` as the primary command, retaining `codex-update-helper` as a compatibility alias.
- Preserve existing settings, logs, service and bundle identifiers, environment overrides, and the update lock. The installer backs up the old app after loading the renamed replacement.

## 0.2.0 - 2026-09-15

- Limit automatic update application to 02:00–03:00 America/New_York, with quarter-hour retries and no daytime catch-up after sleep.
- Add a dedicated native quit guard that defaults to accepting only Codex's scheduled-tasks-only warning and canceling warnings about active work or pending worktrees.
- Defer before quitting when the guard lacks Accessibility permission; retain signature verification, graceful shutdown, and relaunch recovery.
- Add a local app/LaunchAgent installer with backups, schedule and quit-flow tests, and real native-dialog fixture tests.
- Add a native settings window and persistent `config show/set/reset` commands for the time window, timezone, idle time, retry interval, restart policy, and reopening.
- Default to 02:00–03:00 Eastern, 15 minutes idle, 15-minute retries, no active work, and reopening; opt-in `always` allows graceful restarts during active work.
- Read settings on each minute tick so changes apply without reinstalling; validate settings atomically and support windows crossing midnight.
- Add native time pickers, a searchable timezone dropdown, duration menus, contextual restart guidance, and Restore defaults.
- Add an original moon/update-arrow app icon, including all macOS icon sizes and Retina variants.
- Simplify the icon to a flat, editable two-color SVG with no gradients; build the macOS icon directly from the vector source.
- Refresh the app bundle timestamp during installation so macOS picks up the current icon after an upgrade.
- Shorten the README with a copy-and-paste Codex setup prompt and settings table; retain detailed instructions in the technical reference.

## 0.1.1 - 2026-08-20

- Prevent an internal zsh loop variable from leaking into update logs.

## 0.1.0 - 2026-08-20

- Initial macOS release.
- Detect signed Codex updates staged by Sparkle.
- Gracefully quit and reopen Codex after installation.
- Add idle-time protection, dry-run, status, doctor, locking, and timeouts.
- Add Homebrew service support.
