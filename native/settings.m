#import "settings.h"
#import <ApplicationServices/ApplicationServices.h>

NSDictionary<NSString *, NSString *> *defaultSettings(void) {
    return @{@"start-time": @"02:00", @"end-time": @"03:00", @"timezone": @"America/New_York",
             @"idle-minutes": @"15", @"restart-policy": @"idle-only", @"reopen": @"true", @"retry-minutes": @"15"};
}

static NSString *settingsPath(void) {
    const char *override = getenv("CODEX_UPDATE_HELPER_SETTINGS_PATH");
    if (override && *override) return [NSString stringWithUTF8String:override];
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Codex Update Helper/settings.plist"];
}

static BOOL reject(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"CodexUpdateHelper" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

static BOOL matches(NSString *value, NSString *pattern) {
    return [value isKindOfClass:NSString.class] && [value rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

static BOOL validate(NSDictionary *settings, NSError **error) {
    NSDictionary *defaults = defaultSettings();
    for (id key in settings) {
        if (!defaults[key] || ![settings[key] isKindOfClass:NSString.class])
            return reject(error, @"Unknown setting or non-string value.");
    }
    for (NSString *key in @[@"start-time", @"end-time"])
        if (!matches(settings[key], @"^([01][0-9]|2[0-3]):[0-5][0-9]$"))
            return reject(error, @"Start and end times must be HH:MM in 24-hour time.");
    if ([settings[@"start-time"] isEqual:settings[@"end-time"]])
        return reject(error, @"Start and end times must differ.");
    NSString *zone = settings[@"timezone"];
    if (!matches(zone, @"^[A-Za-z0-9_+/-]+$") || ![NSTimeZone timeZoneWithName:zone])
        return reject(error, @"Enter a valid timezone, such as America/New_York.");
    for (NSString *key in @[@"idle-minutes", @"retry-minutes"]) {
        NSString *value = settings[key];
        NSInteger minimum = [key isEqual:@"idle-minutes"] ? 0 : 1;
        if (!matches(value, @"^[0-9]{1,4}$") || value.integerValue < minimum || value.integerValue > 1440)
            return reject(error, @"Idle minutes must be 0–1440; retry minutes must be 1–1440.");
    }
    if (![@[@"idle-only", @"always"] containsObject:settings[@"restart-policy"]])
        return reject(error, @"Restart policy must be idle-only or always.");
    if (![@[@"true", @"false"] containsObject:settings[@"reopen"]])
        return reject(error, @"Reopen must be true or false.");
    return YES;
}

NSDictionary<NSString *, NSString *> *loadSettings(NSError **error) {
    NSMutableDictionary *values = [defaultSettings() mutableCopy];
    NSString *path = settingsPath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
        if (!data) return nil;
        id stored = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
        if (![stored isKindOfClass:NSDictionary.class]) {
            reject(error, @"Settings file must contain a property-list dictionary.");
            return nil;
        }
        [values addEntriesFromDictionary:stored];
    }
    return validate(values, error) ? values : nil;
}

static BOOL saveSettings(NSDictionary *values, NSError **error) {
    if (!validate(values, error)) return NO;
    NSString *path = settingsPath();
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:values format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (!data || ![[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

int settingsCommand(int argc, const char *argv[]) {
    NSString *operation = argc > 0 ? [NSString stringWithUTF8String:argv[0]] : @"show";
    NSError *error = nil;
    NSDictionary *settings = [operation isEqual:@"reset"] ? defaultSettings() : loadSettings(&error);
    if (!settings) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 2; }
    if ([operation isEqual:@"set"]) {
        if (argc < 3 || argc % 2 != 1) { fputs("Usage: config set KEY VALUE [KEY VALUE ...]\n", stderr); return 2; }
        NSMutableDictionary *updated = [settings mutableCopy];
        for (int i = 1; i < argc; i += 2) updated[[NSString stringWithUTF8String:argv[i]]] = [NSString stringWithUTF8String:argv[i + 1]];
        settings = updated;
    } else if (![@[@"show", @"reset", @"values"] containsObject:operation] || argc > 1) {
        fputs("Usage: config show | config set KEY VALUE ... | config reset\n", stderr); return 2;
    }
    if (([operation isEqual:@"set"] || [operation isEqual:@"reset"]) && !saveSettings(settings, &error)) {
        fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 2;
    }
    if ([operation isEqual:@"values"]) {
        for (NSString *key in @[@"timezone", @"start-time", @"end-time", @"idle-minutes", @"restart-policy", @"reopen", @"retry-minutes"])
            puts([settings[key] UTF8String]);
    } else {
        NSData *json = [NSJSONSerialization dataWithJSONObject:settings options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (!json) return 2;
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
    }
    return 0;
}

static void permissionSetup(void) {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

@interface SettingsForm : NSObject
@property NSDatePicker *start;
@property NSDatePicker *end;
@property NSDateFormatter *timeFormat;
@property NSComboBox *timezone;
@property NSArray<NSString *> *zoneIDs;
@property NSPopUpButton *idle;
@property NSPopUpButton *retry;
@property NSPopUpButton *policy;
@property NSButton *reopen;
@property NSTextField *policyDetail;
- (void)apply:(NSDictionary *)settings;
- (void)policyChanged:(id)sender;
- (void)restoreDefaults:(id)sender;
- (NSDictionary *)values;
@end

static void selectMinutes(NSPopUpButton *popup, NSString *value) {
    for (NSMenuItem *item in popup.itemArray) {
        if ([item.representedObject isEqual:value]) { [popup selectItem:item]; return; }
    }
    [popup addItemWithTitle:[NSString stringWithFormat:@"%@ minutes", value]];
    popup.lastItem.representedObject = value; [popup selectItem:popup.lastItem];
}

@implementation SettingsForm
- (void)apply:(NSDictionary *)settings {
    self.start.dateValue = [self.timeFormat dateFromString:settings[@"start-time"]];
    self.end.dateValue = [self.timeFormat dateFromString:settings[@"end-time"]];
    NSUInteger zone = [self.zoneIDs indexOfObject:settings[@"timezone"]];
    if (zone != NSNotFound) [self.timezone selectItemAtIndex:(NSInteger)zone];
    else self.timezone.stringValue = settings[@"timezone"];
    selectMinutes(self.idle, settings[@"idle-minutes"]); selectMinutes(self.retry, settings[@"retry-minutes"]);
    [self.policy selectItemAtIndex:[settings[@"restart-policy"] isEqual:@"always"] ? 1 : 0];
    self.reopen.state = [settings[@"reopen"] isEqual:@"true"] ? NSControlStateValueOn : NSControlStateValueOff;
    [self policyChanged:nil];
}
- (void)policyChanged:(id)sender {
    (void)sender;
    BOOL always = self.policy.indexOfSelectedItem == 1;
    self.idle.enabled = !always;
    self.policyDetail.stringValue = always ? @"May interrupt tasks. Mac idle time is ignored." : @"Running tasks and worktrees being created are protected.";
    self.policyDetail.textColor = always ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor;
}
- (void)restoreDefaults:(id)sender { (void)sender; [self apply:defaultSettings()]; }
- (NSDictionary *)values {
    NSInteger zone = [self.timezone.objectValues indexOfObject:self.timezone.stringValue];
    NSString *zoneID = zone == NSNotFound ? self.timezone.stringValue : self.zoneIDs[zone];
    return @{@"start-time": [self.timeFormat stringFromDate:self.start.dateValue],
             @"end-time": [self.timeFormat stringFromDate:self.end.dateValue], @"timezone": zoneID,
             @"idle-minutes": self.idle.selectedItem.representedObject, @"retry-minutes": self.retry.selectedItem.representedObject,
             @"restart-policy": self.policy.indexOfSelectedItem == 1 ? @"always" : @"idle-only",
             @"reopen": self.reopen.state == NSControlStateValueOn ? @"true" : @"false"};
}
@end

static NSTextField *addLabel(NSView *view, NSString *text, CGFloat y, BOOL heading) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = NSMakeRect(0, y, 170, 22);
    if (heading) label.font = [NSFont boldSystemFontOfSize:13];
    [view addSubview:label]; return label;
}

static void centerLabel(NSTextField *label, NSView *control) {
    // Intrinsic label height avoids the extra top/bottom space of a fixed-height
    // text field. Align to AppKit's control alignment rectangle, including its
    // native bezel insets, instead of eyeballing each label's y coordinate.
    CGFloat x = label.frame.origin.x, width = label.frame.size.width;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:label.superview.leadingAnchor constant:x],
        [label.widthAnchor constraintEqualToConstant:width],
        [label.centerYAnchor constraintEqualToAnchor:control.centerYAnchor]
    ]];
}

static NSDatePicker *timePicker(NSView *view, CGFloat x) {
    NSDatePicker *picker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(x, 292, 132, 28)];
    picker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    picker.datePickerElements = NSDatePickerElementFlagHourMinute;
    picker.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    picker.locale = NSLocale.currentLocale;
    [view addSubview:picker]; return picker;
}

static NSPopUpButton *minutePicker(NSView *view, CGFloat y, BOOL allowZero) {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(174, y, 320, 26) pullsDown:NO];
    if (allowZero) { [popup addItemWithTitle:@"No idle requirement"]; popup.lastItem.representedObject = @"0"; }
    for (NSString *minutes in @[@"5", @"15", @"30", @"60"]) {
        [popup addItemWithTitle:[minutes isEqual:@"60"] ? @"1 hour" : [NSString stringWithFormat:@"%@ minutes", minutes]];
        popup.lastItem.representedObject = minutes;
    }
    [view addSubview:popup]; return popup;
}

int showSettings(void) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
    NSString *iconPath = [NSBundle.mainBundle pathForResource:@"AppIcon" ofType:@"icns"];
    NSImage *appIcon = iconPath ? [[NSImage alloc] initWithContentsOfFile:iconPath] : nil;
    if (appIcon) NSApp.applicationIconImage = appIcon;
    [NSApp activateIgnoringOtherApps:YES];
    NSError *error = nil;
    NSDictionary *settings = loadSettings(&error);
    if (!settings) {
        NSAlert *invalid = [NSAlert new]; invalid.messageText = @"Settings could not be read";
        invalid.informativeText = error.localizedDescription;
        [invalid addButtonWithTitle:@"Use defaults"]; [invalid addButtonWithTitle:@"Cancel"];
        if ([invalid runModal] != NSAlertFirstButtonReturn) return 2;
        settings = defaultSettings();
    }
    SettingsForm *form = [SettingsForm new];
    form.timeFormat = [NSDateFormatter new]; form.timeFormat.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    form.timeFormat.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0]; form.timeFormat.dateFormat = @"HH:mm";
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 358)];
    addLabel(view, @"Schedule", 332, YES);
    NSTextField *windowLabel = addLabel(view, @"Update between", 294, NO);
    form.start = timePicker(view, 174); form.end = timePicker(view, 362);
    [form.start setAccessibilityLabel:@"Start time"]; [form.end setAccessibilityLabel:@"End time"];
    NSTextField *andLabel = [NSTextField labelWithString:@"and"]; andLabel.frame = NSMakeRect(321, 294, 33, 22); [view addSubview:andLabel];
    centerLabel(windowLabel, form.start); centerLabel(andLabel, form.start);
    NSTextField *timezoneLabel = addLabel(view, @"Time zone", 258, NO);
    form.timezone = [[NSComboBox alloc] initWithFrame:NSMakeRect(174, 256, 320, 28)];
    form.timezone.completes = YES; form.timezone.numberOfVisibleItems = 10;
    [form.timezone setAccessibilityLabel:@"Time zone"];
    NSMutableArray *zoneIDs = [NSMutableArray arrayWithArray:@[@"America/New_York", @"America/Chicago", @"America/Denver", @"America/Los_Angeles", @"UTC", @"Europe/London", @"Europe/Paris", @"Asia/Shanghai", @"Asia/Tokyo", @"Asia/Kolkata", @"Australia/Sydney"]];
    NSMutableArray *zoneLabels = [NSMutableArray arrayWithArray:@[@"Eastern Time (New York)", @"Central Time (Chicago)", @"Mountain Time (Denver)", @"Pacific Time (Los Angeles)", @"UTC", @"London", @"Paris", @"China (Shanghai)", @"Japan (Tokyo)", @"India (Kolkata)", @"Sydney"]];
    for (NSString *zone in [NSTimeZone.knownTimeZoneNames sortedArrayUsingSelector:@selector(compare:)]) {
        if (![zoneIDs containsObject:zone]) { [zoneIDs addObject:zone]; [zoneLabels addObject:[zone stringByReplacingOccurrencesOfString:@"_" withString:@" "]]; }
    }
    form.zoneIDs = zoneIDs; [form.timezone addItemsWithObjectValues:zoneLabels]; [view addSubview:form.timezone];
    centerLabel(timezoneLabel, form.timezone);
    NSTextField *retryLabel = addLabel(view, @"Try again every", 222, NO); form.retry = minutePicker(view, 220, NO);
    centerLabel(retryLabel, form.retry);
    [form.retry setAccessibilityLabel:@"Retry interval"];
    addLabel(view, @"Restart behavior", 180, YES);
    form.policy = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 146, 494, 26) pullsDown:NO];
    [form.policy addItemsWithTitles:@[@"Only when no tasks are active", @"Even when tasks are active"]];
    form.policy.target = form; form.policy.action = @selector(policyChanged:); [view addSubview:form.policy];
    [form.policy setAccessibilityLabel:@"Restart policy"];
    form.policyDetail = [NSTextField labelWithString:@""]; form.policyDetail.frame = NSMakeRect(2, 121, 492, 20);
    form.policyDetail.font = [NSFont systemFontOfSize:12]; [view addSubview:form.policyDetail];
    NSTextField *idleLabel = addLabel(view, @"Mac must be idle for", 90, NO); form.idle = minutePicker(view, 88, YES);
    centerLabel(idleLabel, form.idle);
    [form.idle setAccessibilityLabel:@"Mac idle time"];
    form.reopen = [NSButton checkboxWithTitle:@"Reopen Codex after updating if it was already open" target:nil action:nil];
    form.reopen.frame = NSMakeRect(0, 53, 494, 24); [view addSubview:form.reopen];
    NSTextField *permission = [NSTextField labelWithString:AXIsProcessTrusted() ? @"Accessibility: enabled" : @"Accessibility: required for unattended restarts"];
    permission.frame = NSMakeRect(0, 13, 335, 22); permission.font = [NSFont systemFontOfSize:11]; permission.textColor = NSColor.secondaryLabelColor; [view addSubview:permission];
    NSButton *defaults = [NSButton buttonWithTitle:@"Restore defaults" target:form action:@selector(restoreDefaults:)];
    defaults.frame = NSMakeRect(346, 10, 148, 28); [view addSubview:defaults];
    [form apply:settings];
    NSAlert *alert = [NSAlert new]; alert.messageText = @"Codex Updater settings";
    if (appIcon) alert.icon = appIcon;
    alert.informativeText = @"Choose when updates happen and how Codex restarts. Changes apply on the next check.";
    alert.accessoryView = view;
    [alert addButtonWithTitle:@"Save"]; [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Accessibility…"];
    while (YES) {
        NSModalResponse response = [alert runModal];
        if (response == NSAlertThirdButtonReturn) { permissionSetup(); return 0; }
        if (response != NSAlertFirstButtonReturn) return 0;
        NSDictionary *updated = [form values];
        if (saveSettings(updated, &error)) return 0;
        NSAlert *invalid = [NSAlert new]; invalid.messageText = @"Check these settings";
        invalid.informativeText = error.localizedDescription; [invalid runModal];
    }
}
