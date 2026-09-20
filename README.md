# Codex Updater

<img src="assets/promo/social-card.png" alt="Codex Updater — Updates on your schedule. The mint crescent and update-arrow logo above a timeline highlighting 2–3 a.m." width="1200">

Keep Codex up to date overnight, even when you leave it open for days.

## Set up with Codex

Copy this into your Codex agent on the Mac you want to set up:

```text
Install and set up https://github.com/exprmntl/codex-updater on this Mac.
Read the repository instructions and docs/reference.md, check prerequisites,
and use scripts/install-local.sh. Preserve any existing settings; for a new
installation, use the defaults: updates between 2–3 a.m. America/New_York,
only when no local tasks are active and the Mac has been idle for 15 minutes,
retry every 15 minutes, and reopen Codex if it was open before.

Verify the installed service, saved settings, and Accessibility permission
from a standalone background process. Complete everything you can, then give
me clear steps only for anything I must do myself, such as macOS consent.
Don't quit or restart Codex to test the setup while I'm working.
```

Requires macOS, Codex at `/Applications/ChatGPT.app`, and Xcode Command Line Tools to build. Accessibility permission lets the helper handle Codex’s quit confirmation automatically.

## How it works

Codex downloads updates through its built-in updater, Sparkle. This helper enables automatic downloads and finishes waiting updates during your chosen window: it verifies the app signatures, asks Codex to quit gracefully, lets Sparkle install, and reopens Codex.

By default, it waits while local tasks are active. Having scheduled tasks enabled alone won’t block a restart. Your Mac must be awake during the window; the helper doesn’t wake it or catch up during the day. Automatic quit confirmation currently supports known English dialogs.

## Settings

Open **Codex Updater** in your home folder’s **Applications** directory. Use the time pickers, timezone dropdown, and other controls, then **Save**. Changes apply automatically and survive reinstalls; **Restore defaults** brings back these choices.

| Setting | Default | What you can change |
| --- | --- | --- |
| Update window | 2–3 a.m. | Choose start and end times, including overnight windows. |
| Timezone | America/New_York | Choose a timezone; daylight saving time is handled automatically. |
| Restart policy | Only when idle | Allow restarts during active work instead; this can interrupt tasks. Both policies quit gracefully. |
| Inactivity required | 15 minutes | Keyboard/mouse idle time for the default policy; 0 disables this extra check. |
| Retry interval | 15 minutes | How often to retry within the update window. |
| Reopen Codex | On | Reopen after updating if Codex was already open. |

[Manual setup, troubleshooting & technical reference](docs/reference.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [MIT license](LICENSE)

Unofficial community utility; not affiliated with or endorsed by OpenAI.
