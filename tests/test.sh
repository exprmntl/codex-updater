#!/bin/zsh

set -eu
setopt PIPE_FAIL
unsetopt BG_NICE

readonly PROJECT_ROOT=${0:A:h:h}
readonly HELPER="$PROJECT_ROOT/bin/codex-updater"
TEST_ROOT=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/codex-update-helper-tests.XXXXXX")

cleanup() {
  /bin/rm -rf "$TEST_ROOT"
}
trap cleanup EXIT INT TERM

fail() {
  /bin/echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ $haystack == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack=$1
  local needle=$2
  [[ $haystack != *"$needle"* ]] || fail "expected output not to contain: $needle"
}

make_app() {
  local app_path=$1
  local bundle_id=$2
  local version=$3
  local build=$4
  /bin/mkdir -p "$app_path/Contents"
  /usr/bin/plutil -create xml1 "$app_path/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string "$bundle_id" "$app_path/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleShortVersionString -string "$version" "$app_path/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleVersion -string "$build" "$app_path/Contents/Info.plist"
}

run_helper() {
  CODEX_UPDATE_HELPER_APP_PATH="$TEST_ROOT/Applications/ChatGPT.app" \
  CODEX_UPDATE_HELPER_BUNDLE_ID="dev.exprmntl.codex-update-helper.fixture" \
  CODEX_UPDATE_HELPER_PROCESS_NAME="codex-helper-no-process" \
  CODEX_UPDATE_HELPER_EXECUTABLE_PATH="${CODEX_UPDATE_HELPER_TEST_EXECUTABLE_PATH:-$TEST_ROOT/no-such-process}" \
  CODEX_UPDATE_HELPER_SPARKLE_DIR="$TEST_ROOT/Sparkle/Installation" \
  CODEX_UPDATE_HELPER_SKIP_SIGNATURE_CHECK=1 \
  CODEX_UPDATE_HELPER_SETTINGS_PATH="$TEST_ROOT/no-settings.plist" \
  CODEX_UPDATE_HELPER_START_HOUR="${CODEX_UPDATE_HELPER_START_HOUR:-0}" \
  CODEX_UPDATE_HELPER_END_HOUR="${CODEX_UPDATE_HELPER_END_HOUR:-24}" \
  CODEX_UPDATE_HELPER_QUIT_HELPER="$TEST_ROOT/missing-guard" \
  CODEX_UPDATE_HELPER_MAX_WAIT_SECONDS=1 \
  CODEX_UPDATE_HELPER_POLL_SECONDS=1 \
  "${CODEX_UPDATE_HELPER_TEST_HELPER:-$HELPER}" "$@"
}

/bin/echo "1..22"

/bin/zsh -n "$HELPER"
/bin/echo "ok 1 - zsh syntax"

[[ $("$HELPER" version) == 0.2.1 ]] || fail "unexpected version"
/bin/echo "ok 2 - version"

help_output=$("$HELPER" help)
assert_contains "$help_output" "run [--dry-run] [--force]"
/bin/echo "ok 3 - help"

make_app "$TEST_ROOT/Applications/ChatGPT.app" "dev.exprmntl.codex-update-helper.fixture" "1.0.0" "10"
/bin/mkdir -p "$TEST_ROOT/Sparkle/Installation"
status_output=$(run_helper status)
assert_contains "$status_output" "Installed: 1.0.0 (build 10)"
assert_contains "$status_output" "Staged: none"
/bin/echo "ok 4 - fixture status"

no_update_output=$(run_helper run --dry-run)
assert_contains "$no_update_output" "No staged update is newer"
/bin/echo "ok 5 - no-update dry run"

make_app "$TEST_ROOT/Sparkle/Installation/older/ChatGPT.app" "dev.exprmntl.codex-update-helper.fixture" "1.1.0" "11"
make_app "$TEST_ROOT/Sparkle/Installation/newer/ChatGPT.app" "dev.exprmntl.codex-update-helper.fixture" "1.2.0" "12"
staged_output=$(run_helper status)
assert_contains "$staged_output" "Staged: 1.2.0 (build 12)"
/bin/echo "ok 6 - newest staged build selected"

dry_run_output=$(run_helper run --dry-run --force)
assert_contains "$dry_run_output" "Would wait for Sparkle"
assert_not_contains "$dry_run_output" "Updated Codex"
/bin/echo "ok 7 - forced dry run remains non-mutating"

idle_output=$(CODEX_UPDATE_HELPER_RUNNING_OVERRIDE=1 \
  CODEX_UPDATE_HELPER_IDLE_SECONDS_OVERRIDE=0 run_helper run --dry-run)
assert_contains "$idle_output" "deferring until 900s"
/bin/echo "ok 8 - active app is protected by idle guard"

forced_running_output=$(CODEX_UPDATE_HELPER_RUNNING_OVERRIDE=1 \
  CODEX_UPDATE_HELPER_IDLE_SECONDS_OVERRIDE=0 run_helper run --dry-run --force)
assert_contains "$forced_running_output" "Would request a graceful Codex quit"
/bin/echo "ok 9 - force bypasses idle guard, retains guarded quit"

make_app "$TEST_ROOT/Sparkle/Installation/newer/ChatGPT.app" "dev.exprmntl.wrong" "1.3.0" "13"
if run_helper run --dry-run --force >"$TEST_ROOT/invalid.out" 2>&1; then
  fail "invalid staged bundle should fail"
fi
invalid_output=$(<"$TEST_ROOT/invalid.out")
assert_contains "$invalid_output" "expected 'dev.exprmntl.codex-update-helper.fixture'"
/bin/echo "ok 10 - invalid staged identity rejected"

make_app "$TEST_ROOT/Sparkle/Installation/newer/ChatGPT.app" "dev.exprmntl.codex-update-helper.fixture" "1.2.0" "12"
/bin/cat > "$TEST_ROOT/helper-at-hour" <<'SH'
#!/bin/zsh
source "$CODEX_TEST_HELPER_SOURCE"
current_update_time() { /bin/echo "$CODEX_TEST_HOUR:00"; }
main "$@"
SH
/bin/chmod +x "$TEST_ROOT/helper-at-hour"

at_hour() {
  CODEX_TEST_HELPER_SOURCE="$HELPER" CODEX_TEST_HOUR="$1" \
  CODEX_UPDATE_HELPER_TEST_HELPER="$TEST_ROOT/helper-at-hour" \
  CODEX_UPDATE_HELPER_START_HOUR=2 CODEX_UPDATE_HELPER_END_HOUR=3 \
  run_helper run --dry-run "${@:2}"
}

for hour in 00 01 03 08 14 23; do
  output=$(at_hour "$hour")
  assert_contains "$output" 'Outside update window'
  assert_not_contains "$output" 'Signed-update candidate'
done
/bin/echo "ok 11 - daytime, window boundaries, and late wake-ups defer before update work"
output=$(at_hour 02)
assert_contains "$output" 'Would wait for Sparkle'
/bin/echo "ok 12 - 2 a.m. is inside the update window"
output=$(at_hour 14 --force)
assert_contains "$output" 'Would wait for Sparkle'
/bin/echo "ok 13 - explicit force bypasses the time window"

if CODEX_UPDATE_HELPER_TIMEZONE='invalid/timezone' run_helper run --dry-run >"$TEST_ROOT/timezone.out" 2>&1; then
  fail 'invalid timezone must fail closed'
fi
assert_contains "$(<"$TEST_ROOT/timezone.out")" 'Invalid update timezone or window'
/bin/echo "ok 14 - invalid timezone cannot allow a restart"
if CODEX_UPDATE_HELPER_START_HOUR=2 CODEX_UPDATE_HELPER_END_HOUR=2 run_helper run --dry-run >"$TEST_ROOT/window.out" 2>&1; then
  fail 'invalid window must fail closed'
fi
/bin/echo "ok 15 - invalid window is rejected"

output=$(CODEX_UPDATE_HELPER_RUNNING_OVERRIDE=1 CODEX_UPDATE_HELPER_IDLE_SECONDS_OVERRIDE=2000 run_helper run --dry-run)
assert_contains "$output" 'Unattended quit is not ready'
assert_contains "$output" 'restart policy: idle-only; reopen: true'
/bin/echo "ok 16 - dry-run reports missing guard without prompting or quitting"

# A fresh process checks the configured timezone rather than inheriting TZ.
actual_hour=$(TZ=Pacific/Honolulu /bin/zsh -c 'source "$1"; current_update_time' test "$HELPER")
expected_hour=$(TZ=America/New_York /bin/date +%H:%M)
[[ $actual_hour == $expected_hour ]] || fail 'Eastern timezone was not used'
for stamp in '2026-01-15 07:00:00' '2026-07-15 06:00:00'; do
  epoch=$(TZ=UTC /bin/date -j -f '%Y-%m-%d %H:%M:%S' "$stamp" +%s)
  [[ $(TZ=America/New_York /bin/date -r "$epoch" +%H) == 02 ]] || fail 'DST conversion failed'
done
/bin/echo "ok 17 - Eastern time is independent of the Mac timezone and follows DST"

CODEX_UPDATE_HELPER_BUILD_ROOT="$TEST_ROOT/build" /bin/zsh "$PROJECT_ROOT/scripts/build-app.sh" >"$TEST_ROOT/build.out" 2>&1
"$TEST_ROOT/build/Codex Updater.app/Contents/MacOS/codex-update-helper-quit" --self-test
/bin/echo "ok 18 - native warning policy protects active work, worktrees, unknown text, and other dialogs"

# Mock only the OS interactions, exercising the actual update/reopen flow.
/bin/zsh "$PROJECT_ROOT/tests/update-flow.sh" "$TEST_ROOT" "$HELPER"
/bin/echo "ok 19 - successful update reopens; canceled quit, missing permission, and failed install stay safe"

/bin/zsh "$PROJECT_ROOT/tests/settings.sh" "$TEST_ROOT" "$HELPER" "$TEST_ROOT/build/Codex Updater.app/Contents/MacOS/codex-update-helper-quit"
/bin/echo "ok 20 - persistent settings, validation, time boundaries, retries, policy, and reopen options"

[[ $("$PROJECT_ROOT/bin/codex-update-helper" version) == $("$HELPER" version) ]] || fail "legacy command differs"
assert_contains "$("$PROJECT_ROOT/bin/codex-update-helper" help)" "codex-updater run"
/bin/zsh -c 'source "$1"; [[ $LOCK_DIR == "${TMPDIR:-/tmp}/codex-update-helper-${UID}.lock" ]]' test "$HELPER" || fail "update lock changed"
/bin/echo "ok 21 - legacy command remains usable and shares the existing update lock"

app="$TEST_ROOT/build/Codex Updater.app"
[[ $(/usr/bin/plutil -extract CFBundleDisplayName raw "$app/Contents/Info.plist") == 'Codex Updater' ]] || fail "wrong display name"
[[ $(/usr/bin/plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist") == dev.exprmntl.codex-update-helper.quit-guard ]] || fail "bundle identity changed"
[[ $("$app/Contents/Resources/codex-updater" version) == 0.2.1 ]] || fail "new bundled command is missing"
[[ $("$app/Contents/Resources/codex-update-helper" version) == 0.2.1 ]] || fail "legacy bundled command is missing"
/bin/echo "ok 22 - renamed app bundles both commands and preserves its identity"
