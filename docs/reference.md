# Setup and technical reference

[← Project overview](../README.md)

Detailed instructions for manual setup, agent-assisted installation, troubleshooting, and development. Run commands from the repository root unless a full path is shown.

## Install

From the repository on macOS (Xcode Command Line Tools are required to build):

```bash
zsh scripts/install-local.sh
open "$HOME/Applications/Codex Updater.app"
```

Enable **Codex Updater** once in **System Settings → Privacy & Security → Accessibility**. If it is not listed, use **+** and select the app in your home folder's Applications directory. The helper defers before requesting a quit until this permission is available. Rebuilding an ad-hoc signed helper may require re-enabling its permission.

### Verify background Accessibility permission

The settings window and a command launched from Codex can inherit Codex's own Accessibility access. Verify the installed helper from a standalone LaunchAgent before declaring unattended restarts ready; the foreground `doctor` result alone is insufficient.

Create a temporary, one-shot LaunchAgent with a unique label, `RunAtLoad` enabled, and these `ProgramArguments` (expand `~` to the actual home directory):

1. `~/Applications/Codex Updater.app/Contents/MacOS/codex-update-helper-quit`
2. `--check-accessibility`

Give it separate stdout/stderr files, load it with `launchctl bootstrap "gui/$(id -u)" /path/to/probe.plist`, and inspect its output and exit status. `ready` with exit 0 means access works; `needs-accessibility` with exit 2 means the permission still needs attention. This check never quits Codex. Unload the temporary job and remove its temporary files afterward.

If the toggle looks enabled but this check fails, remove the stale **Codex Updater** entry from Accessibility, add the currently installed app again using **+**, and enable it. Authenticate when macOS asks. Recheck from the background process. Avoid rebuilding after granting access: the changed ad-hoc signature can invalidate the grant again.

### Existing installations and scheduling

Codex Updater was previously named Codex Update Helper. The installer puts the renamed app in `~/Applications/Codex Updater.app` and moves the old app into the installer backup after the replacement service loads. Settings, logs, the LaunchAgent label, bundle identifier, update lock, and `CODEX_UPDATE_HELPER_*` environment overrides retain their existing names for compatibility. The old `codex-update-helper` command remains an alias for `codex-updater` in the repository and app bundle. Until you reinstall, the new command can still use the older installed app.

The local installer backs up and replaces the existing `dev.exprmntl.codex-update-helper` LaunchAgent, including an older Homebrew installation. It installs a self-contained app under `~/Applications`; no checkout is needed at runtime. Existing Homebrew files are preserved. Do not run `brew services restart codex-update-helper` afterward: that restores the older Homebrew service configuration. Use the local installer to reinstall this version.

By default, the service attempts updates every 15 minutes between **02:00 inclusive and 03:00 exclusive in `America/New_York`**, following daylight saving time independently of the Mac's timezone. It also requires 15 minutes of keyboard/mouse inactivity. A busy Mac is retried during that hour, then the following night. If the Mac sleeps through the window, the helper skips the daytime wake-up; it does not wake the Mac. The spring-forward date has no 2 a.m. hour, so that night's default update window is skipped.

Codex's own quit dialog distinguishes active local tasks and worktrees still starting from merely having scheduled tasks enabled. By default, the helper accepts only the exact English scheduled-tasks-only warning. It cancels a recognized quit dialog with any other warning, including active work, and never clicks an unrelated dialog. Unknown/localized dialog structures are left alone and time out without a forced quit.

## Settings

Open **Codex Updater** from your home folder's Applications directory, or run `./bin/codex-updater settings`. The settings window lets you change the schedule and restart behavior. Settings are stored in `~/Library/Application Support/Codex Update Helper/settings.plist` and survive reinstalls. The service reads them each minute; changes take effect on the next check without reinstalling or restarting the service.

Use the native time pickers for start/end times, the searchable timezone dropdown, and the idle/retry menus. The idle menu disables automatically when you choose to restart during active work. **Restore defaults** fills in the default choices; **Save** applies them. **Cancel** leaves saved settings unchanged.

| Setting | Default | Behavior |
| --- | --- | --- |
| `start-time` | `02:00` | Start of the update window, in 24-hour HH:MM format. |
| `end-time` | `03:00` | End of the window, exclusive. Windows may cross midnight; start and end must differ. |
| `timezone` | `America/New_York` | Named timezone, including daylight saving changes. |
| `idle-minutes` | `15` | Keyboard/mouse inactivity required for `idle-only`; `0` disables this extra check. |
| `retry-minutes` | `15` | Time between update attempts within the window. |
| `restart-policy` | `idle-only` | Wait for no active local tasks or worktrees being created. `always` permits interrupting active work and ignores keyboard/mouse inactivity. |
| `reopen` | `true` | Reopen Codex if it was open before the update; `false` leaves it closed. |

The **always** policy still uses a graceful quit and Sparkle's installer. It approves known warnings about active local tasks and worktrees being created, which can interrupt or lose that work. It does not force-kill a hung app, bypass signature checks, or approve unknown warnings. The time window applies to both policies.

Command-line equivalents:

```bash
./bin/codex-updater config show
./bin/codex-updater config set start-time 01:30 end-time 03:00 timezone America/New_York
./bin/codex-updater config set restart-policy always
./bin/codex-updater config set restart-policy idle-only idle-minutes 15 reopen true
./bin/codex-updater config reset
```

Multiple values are validated and saved together. An invalid setting leaves the existing file unchanged. Missing settings use the defaults above; a malformed settings file blocks automatic updates until it is fixed or reset. Saved settings are data, never executable shell code. Legacy environment overrides for timezone, start/end hours, and idle seconds take precedence when explicitly supplied.

## Check it

```bash
./bin/codex-updater status
./bin/codex-updater doctor
./bin/codex-updater run --dry-run
```

The installed command is also available at `~/Applications/Codex Updater.app/Contents/Resources/codex-updater`. An older `codex-update-helper` on your PATH may still refer to the Homebrew release.

To install a waiting update immediately, bypassing the time window and keyboard/mouse idle guard:

```bash
./bin/codex-updater run --force
```

The configured restart policy, signature checks, bundle identity checks, graceful quitting, and timeouts still apply. `--force` only bypasses the schedule and keyboard/mouse idle guard; it does not change `idle-only` to `always` and never force-kills Codex.

## Exactly what it does

- Runs as your macOS user through a LaunchAgent; it never needs `sudo`.
- Enables Codex's automatic update checks and automatic downloads.
- Reads Codex's installed build from `/Applications/ChatGPT.app`.
- Reads updates already staged in Codex's Sparkle cache.
- Verifies the installed and staged apps have bundle ID `com.openai.codex`, OpenAI team ID `2DC432GLL2`, and valid Apple code signatures.
- Uses Codex's native quit confirmation to protect active local tasks and worktrees being created under the default `idle-only` policy.
- Lets Sparkle perform the installation. The helper never downloads or copies Codex.
- Reopens Codex when it was open before the update and the `reopen` setting is enabled.

It leaves Sparkle's **Skip this version** preference unchanged.

## Uninstall

```bash
launchctl bootout "gui/$(id -u)/dev.exprmntl.codex-update-helper"
rm "$HOME/Library/LaunchAgents/dev.exprmntl.codex-update-helper.plist"
```

Then remove `~/Applications/Codex Updater.app` in Finder. This does not remove Codex, its preferences, or an older Homebrew package. Installer backups are in `~/Library/Application Support/Codex Update Helper/backups/`.

## Logs

The local service writes output to:

```text
~/Library/Logs/Codex Update Helper/service.log
~/Library/Logs/Codex Update Helper/service.error.log
```

## Requirements and scope

- macOS
- The Codex desktop app installed at `/Applications/ChatGPT.app`
- Xcode Command Line Tools to build the helper (no build tools needed at runtime)
- One-time Accessibility permission for the dedicated helper app

The implementation depends on Codex's current Sparkle staging layout. If that implementation changes, `doctor` should report the mismatch rather than attempting an unsafe installation.

## Development

```bash
zsh -n bin/codex-updater
./tests/test.sh
# Optional: briefly displays test dialogs in a disposable fixture app.
zsh tests/native-ui.sh
```

See [SECURITY.md](../SECURITY.md) for the trust model and vulnerability reporting.

The flat, two-color app icon is maintained as editable vector artwork in `assets/AppIcon.svg`. `scripts/build-icon.sh` uses macOS AppKit to render it and packages all icon sizes with `sips` and `iconutil`. `assets/AppIcon.png` is a portable preview.

## License

MIT
