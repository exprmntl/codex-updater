#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#include <signal.h>
#import "settings.h"

// Codex's native quit confirmation is the authority on active local work.
// The default accepts only the exact English scheduled-tasks-only warning.
// The explicit always policy also accepts known warnings about active work.
// Changes to the wording or structure fail closed, including other locales.
static int dialogDecision(NSArray<NSString *> *texts, NSArray<NSString *> *buttons, BOOL allowActive) {
    if (buttons.count != 2 || ![buttons containsObject:@"Quit"] || ![buttons containsObject:@"Cancel"])
        return -1;
    for (NSString *name in @[@"ChatGPT", @"Codex"]) {
        NSString *title = [NSString stringWithFormat:@"Quit %@?", name];
        if (![texts containsObject:title]) continue;
        NSString *detail = [NSString stringWithFormat:@"Scheduled tasks won't run while %@ is closed", name];
        // Unknown extra text might describe work at risk; never accept it.
        if (texts.count == 2 && [texts containsObject:detail]) return 0;
        if (allowActive && texts.count == 2) {
            NSArray *activeWarnings = @[
                @"Active local chats on this machine will be interrupted",
                [NSString stringWithFormat:@"Active local chats on this machine will be interrupted and scheduled tasks won't run while %@ is closed", name],
                @"Chats still starting in new worktrees may be lost, including on remote hosts",
                @"Chats still starting in new worktrees may be lost, including on remote hosts. Active local chats will be interrupted",
                [NSString stringWithFormat:@"Chats still starting in new worktrees may be lost, including on remote hosts. Scheduled tasks won't run while %@ is closed", name],
                [NSString stringWithFormat:@"Chats still starting in new worktrees may be lost, including on remote hosts. Active local chats will be interrupted and scheduled tasks won't run while %@ is closed", name]
            ];
            for (NSString *warning in activeWarnings) if ([texts containsObject:warning]) return 0;
        }
        return 1;
    }
    return -1;
}

static id attribute(AXUIElementRef element, CFStringRef key) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, key, &value) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}

static void collect(AXUIElementRef element, NSMutableArray *texts, NSMutableArray *buttons,
                    NSMutableArray *buttonElements, int depth, int *remaining) {
    if (depth > 5 || --*remaining < 0) return;
    NSString *role = attribute(element, kAXRoleAttribute);
    if ([role isEqualToString:(__bridge NSString *)kAXStaticTextRole]) {
        id value = attribute(element, kAXValueAttribute);
        if ([value isKindOfClass:NSString.class] && [value length] > 0) [texts addObject:value];
    } else if ([role isEqualToString:(__bridge NSString *)kAXButtonRole]) {
        id title = attribute(element, kAXTitleAttribute);
        if ([title isKindOfClass:NSString.class] && [title length] > 0) {
            [buttons addObject:title];
            [buttonElements addObject:(__bridge id)element];
        }
    }
    id children = attribute(element, kAXChildrenAttribute);
    if ([children isKindOfClass:NSArray.class]) {
        for (id child in children) collect((__bridge AXUIElementRef)child, texts, buttons, buttonElements, depth + 1, remaining);
    }
}

// Returns 0 after accepting, 1 after canceling, -1 if no known quit dialog,
// and -2 for an accessibility failure. Never clicks a generic "Quit" button.
static int handleDialog(AXUIElementRef app, BOOL cancelOnly, BOOL allowActive) {
    id windows = attribute(app, kAXWindowsAttribute);
    if (![windows isKindOfClass:NSArray.class]) return -2;
    for (id window in windows) {
        NSMutableArray *texts = [NSMutableArray array], *buttons = [NSMutableArray array];
        NSMutableArray *elements = [NSMutableArray array];
        int remaining = 256;
        collect((__bridge AXUIElementRef)window, texts, buttons, elements, 0, &remaining);
        int decision = dialogDecision(texts, buttons, allowActive);
        if (decision < 0) continue;
        NSString *target = decision == 0 && !cancelOnly ? @"Quit" : @"Cancel";
        NSUInteger index = [buttons indexOfObject:target];
        AXError result = AXUIElementPerformAction((__bridge AXUIElementRef)elements[index], kAXPressAction);
        if (result != kAXErrorSuccess) return -2;
        return [target isEqualToString:@"Quit"] ? 0 : 1;
    }
    return -1;
}

static volatile sig_atomic_t interrupted = 0;
static void stopGuard(int signalNumber) { interrupted = signalNumber; }

static int selfTest(void) {
    NSArray *buttons = @[@"Quit", @"Cancel"];
    for (NSString *name in @[@"ChatGPT", @"Codex"]) {
        NSString *title = [NSString stringWithFormat:@"Quit %@?", name];
        NSString *scheduled = [NSString stringWithFormat:@"Scheduled tasks won't run while %@ is closed", name];
        if (dialogDecision(@[title, scheduled], buttons, NO) != 0) return 1;
        for (NSString *detail in @[@"Active local chats on this machine will be interrupted",
                                    @"Active local chats on this machine will be interrupted and scheduled tasks won't run while ChatGPT is closed",
                                    @"Chats still starting in new worktrees may be lost, including on remote hosts",
                                    @"New warning text"]) {
            if (dialogDecision(@[title, detail], buttons, NO) != 1) return 1;
            BOOL unknown = [detail isEqual:@"New warning text"];
            if (dialogDecision(@[title, detail], buttons, YES) != (unknown || ([name isEqual:@"Codex"] && [detail containsString:@"ChatGPT"]) ? 1 : 0)) return 1;
        }
        if (dialogDecision(@[title, scheduled, @"Additional active work"], buttons, YES) != 1) return 1;
        if (dialogDecision(@[title], buttons, YES) != 1) return 1;
        if (dialogDecision(@[title, scheduled], @[@"Quit"], YES) != -1) return 1;
        if (dialogDecision(@[title, scheduled], @[@"Quit", @"Cancel", @"Other"], YES) != -1) return 1;
    }
    if (dialogDecision(@[@"Quit another app?", @"Scheduled tasks won't run while Codex is closed"], buttons, YES) != -1) return 1;
    if (dialogDecision(@[@"Quitter Codex ?", @"Tâches planifiées"], @[@"Quitter", @"Annuler"], YES) != -1) return 1;
    puts("ok - idle-only and always policies recognize only the exact supported warnings");
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 1 || (argc == 2 && strcmp(argv[1], "--settings") == 0)) return showSettings();
        if (argc >= 2 && strcmp(argv[1], "--config") == 0) return settingsCommand(argc - 2, argv + 2);
        if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return selfTest();
        if (argc == 2 && strcmp(argv[1], "--check-accessibility") == 0) {
            puts(AXIsProcessTrusted() ? "ready" : "needs-accessibility");
            return AXIsProcessTrusted() ? 0 : 2;
        }
        if (argc == 2 && strcmp(argv[1], "--request-accessibility") == 0) {
            NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
            if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
                [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
                puts("Enable Codex Updater in Privacy & Security > Accessibility.");
                return 2;
            }
            puts("Unattended quit is ready.");
            return 0;
        }
        if ((argc != 5 && argc != 6) || strcmp(argv[1], "--quit") != 0) {
            fputs("Usage: codex-update-helper-quit --quit PID EXECUTABLE BUNDLE_ID [idle-only|always]\n", stderr);
            return 2;
        }
        NSString *policy = argc == 6 ? [NSString stringWithUTF8String:argv[5]] : @"idle-only";
        if (![@[@"idle-only", @"always"] containsObject:policy]) return 2;
        BOOL allowActive = [policy isEqual:@"always"];
        if (!AXIsProcessTrusted()) {
            puts("Accessibility permission is missing; no quit was requested.");
            return 2;
        }
        char *end = NULL;
        long pidValue = strtol(argv[2], &end, 10);
        if (*end || pidValue <= 0 || pidValue > INT_MAX) return 2;
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:(pid_t)pidValue];
        NSString *expectedPath = [NSString stringWithUTF8String:argv[3]];
        NSString *bundleID = [NSString stringWithUTF8String:argv[4]];
        NSString *allowedBundle = @"com.openai.codex";
#ifdef QUIT_GUARD_TESTING
        allowedBundle = @"dev.exprmntl.codex-update-helper.fixture";
#endif
        if (!app || !app.finishedLaunching || ![app.bundleIdentifier isEqualToString:bundleID]
            || ![bundleID isEqualToString:allowedBundle]
            || ![app.executableURL.path isEqualToString:expectedPath]) {
            puts("Process identity or readiness changed; no quit was requested.");
            return 3;
        }
        AXUIElementRef axApp = AXUIElementCreateApplication((pid_t)pidValue);
        AXUIElementSetMessagingTimeout(axApp, 2.0);
        // Do not approve a dialog left by a user or an older updater attempt.
        int previous = handleDialog(axApp, YES, NO);
        if (previous != -1) {
            CFRelease(axApp);
            puts("Existing quit dialog or unreadable app; deferring.");
            return 3;
        }
        signal(SIGINT, stopGuard);
        signal(SIGTERM, stopGuard);
        if (![app terminate]) {
            CFRelease(axApp);
            puts("Codex did not accept the graceful quit request; deferring.");
            return 3;
        }
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
        BOOL accepted = NO;
        while (!interrupted && [deadline timeIntervalSinceNow] > 0) {
            if (app.terminated || ![NSRunningApplication runningApplicationWithProcessIdentifier:(pid_t)pidValue]) {
                CFRelease(axApp);
                puts("Codex quit gracefully.");
                return 0;
            }
            int decision = handleDialog(axApp, NO, allowActive);
            if (decision == 0) {
                accepted = YES;
                puts(allowActive ? "Accepted a known Codex quit warning under the always restart policy." : "Accepted Codex's scheduled-tasks-only quit warning.");
            } else if (decision == 1) {
                CFRelease(axApp);
                puts("Codex reports active work or an unrecognized warning; canceled the quit.");
                return 3;
            }
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        handleDialog(axApp, YES, NO);
        CFRelease(axApp);
        // Once accepted, let the shell monitor Sparkle and restore the app even
        // if Codex's graceful shutdown takes longer than this dialog timeout.
        if (accepted && !interrupted) return 0;
        puts("Quit timed out or was interrupted; no forced termination.");
        return 3;
    }
}
