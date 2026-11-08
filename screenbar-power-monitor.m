#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOKit/IOMessage.h>
#include <signal.h>

static io_connect_t root_port = MACH_PORT_NULL;
static NSString *lastEvent = @"";
static NSTimeInterval lastEventTime = 0;
static NSTimeInterval lastShutdownTime = 0;
static BOOL isScreenLocked = NO;
static BOOL isRunningScript = NO;
static BOOL pendingExitAfterScript = NO;
static NSString * const kSkipShutdownFlagPath = @"/tmp/screenbar-skip-shutdown";

static BOOL isSessionLocked(void) {
    if (isScreenLocked) return YES;
    CFDictionaryRef sessionDict = CGSessionCopyCurrentDictionary();
    if (sessionDict) {
        CFBooleanRef locked = CFDictionaryGetValue(sessionDict, CFSTR("CGSSessionScreenIsLocked"));
        BOOL result = (locked && CFBooleanGetValue(locked));
        CFRelease(sessionDict);
        return result;
    }
    return NO;
}

static NSString *getPowerEventScriptPath(void) {
    NSString *execPath = [[NSBundle mainBundle] executablePath];
    NSString *dirPath = [execPath stringByDeletingLastPathComponent];
    return [dirPath stringByAppendingPathComponent:@"_screenbar_power_event.sh"];
}

static void logMessage(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/screenbar-power.log"];
    if (!fh) {
        [line writeToFile:@"/tmp/screenbar-power.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

static BOOL shouldSkipShutdownOnReload(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:kSkipShutdownFlagPath]) {
        return NO;
    }
    NSDictionary *attrs = [fm attributesOfItemAtPath:kSkipShutdownFlagPath error:nil];
    NSDate *modDate = attrs[NSFileModificationDate];
    [fm removeItemAtPath:kSkipShutdownFlagPath error:nil];
    if (modDate && fabs([modDate timeIntervalSinceNow]) < 15.0) {
        return YES;
    }
    return NO;
}

static BOOL hasRecentShutdown(void) {
    if (lastShutdownTime <= 0) return NO;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    return (now - lastShutdownTime) < 15.0;
}

static void runPowerScript(NSString *event, NSString *source) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (hasRecentShutdown() && ([event isEqualToString:@"shutdown"] || [event isEqualToString:@"sleep"])) {
        logMessage([NSString stringWithFormat:@"Ignored '%@' from %@ (shutdown already handled)", event, source]);
        return;
    }
    if ([event isEqualToString:lastEvent] && (now - lastEventTime) < 2.0) {
        logMessage([NSString stringWithFormat:@"Ignored duplicate '%@' from %@", event, source]);
        return;
    }
    if ([event isEqualToString:@"shutdown"]) {
        lastShutdownTime = now;
    } else if ([event isEqualToString:@"wake"]) {
        lastShutdownTime = 0;
    }
    lastEvent = [event copy];
    lastEventTime = now;
    logMessage([NSString stringWithFormat:@"Triggering '%@' from %@", event, source]);

    isRunningScript = YES;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    task.arguments = @[getPowerEventScriptPath(), event];
    NSError *error = nil;
    if ([task launchAndReturnError:&error]) {
        [task waitUntilExit];
    } else {
        logMessage([NSString stringWithFormat:@"Error launching script: %@", error]);
    }
    isRunningScript = NO;

    if (pendingExitAfterScript) {
        logMessage(@"Power script completed, exiting after deferred termination signal");
        exit(0);
    }
}

static void handleTerminationSignal(NSString *sigName) {
    if (shouldSkipShutdownOnReload()) {
        logMessage([NSString stringWithFormat:@"Received %@ during service reload, exiting without powering off", sigName]);
        exit(0);
    }
    if (isRunningScript) {
        logMessage([NSString stringWithFormat:@"Received %@ while power script is in flight, deferring exit until completion", sigName]);
        pendingExitAfterScript = YES;
        return;
    }
    runPowerScript(@"shutdown", sigName);
    exit(0);
}

static void displayCallback(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo) {
    if (CGDisplayIsAsleep(CGMainDisplayID())) {
        runPowerScript(@"sleep", @"CGDisplayIsAsleep");
    }
}

static void powerCallback(void *refCon, io_service_t service, natural_t messageType, void *messageArgument) {
    switch (messageType) {
        case kIOMessageCanSystemSleep:
        case kIOMessageCanSystemPowerOff:
            IOAllowPowerChange(root_port, (long)messageArgument);
            break;
        case kIOMessageSystemWillSleep:
            runPowerScript(@"sleep", @"kIOMessageSystemWillSleep");
            IOAllowPowerChange(root_port, (long)messageArgument);
            break;
        case kIOMessageSystemWillPowerOff:
            runPowerScript(@"shutdown", @"kIOMessageSystemWillPowerOff");
            IOAllowPowerChange(root_port, (long)messageArgument);
            break;
        case kIOMessageSystemWillRestart:
            runPowerScript(@"shutdown", @"kIOMessageSystemWillRestart");
            IOAllowPowerChange(root_port, (long)messageArgument);
            break;
        case kIOMessageSystemHasPoweredOn:
            if (CGDisplayIsAsleep(CGMainDisplayID())) {
                logMessage(@"Ignored kIOMessageSystemHasPoweredOn during DarkWake (display is asleep)");
            } else if (isSessionLocked()) {
                logMessage(@"Ignored kIOMessageSystemHasPoweredOn while screen is locked (waiting for unlock)");
            } else {
                runPowerScript(@"wake", @"kIOMessageSystemHasPoweredOn");
            }
            break;
        default:
            break;
    }
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [[NSFileManager defaultManager] removeItemAtPath:kSkipShutdownFlagPath error:nil];
    [[NSProcessInfo processInfo] disableSuddenTermination];
    logMessage(@"screenbar-power-monitor started and connected to WindowServer");

    // 1. Register IOKit System Power Callback
    IONotificationPortRef notifyPortRef = NULL;
    io_object_t notifierObject = MACH_PORT_NULL;
    root_port = IORegisterForSystemPower(NULL, &notifyPortRef, powerCallback, &notifierObject);
    if (root_port != MACH_PORT_NULL && notifyPortRef != NULL) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           IONotificationPortGetRunLoopSource(notifyPortRef),
                           kCFRunLoopCommonModes);
    }

    // 2. Register CoreGraphics Display Reconfiguration Callback
    CGDisplayRegisterReconfigurationCallback(displayCallback, NULL);

    // 3. Register NSWorkspace notifications (now active because NSApp is connected to WindowServer!)
    NSNotificationCenter *wsCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [wsCenter addObserver:self selector:@selector(screensDidSleep:) name:NSWorkspaceScreensDidSleepNotification object:nil];
    [wsCenter addObserver:self selector:@selector(screensDidWake:) name:NSWorkspaceScreensDidWakeNotification object:nil];
    [wsCenter addObserver:self selector:@selector(willSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [wsCenter addObserver:self selector:@selector(didWake:) name:NSWorkspaceDidWakeNotification object:nil];
    [wsCenter addObserver:self selector:@selector(willPowerOff:) name:NSWorkspaceWillPowerOffNotification object:nil];

    // 4. Register Distributed Notifications for Screen Lock / Unlock
    NSDistributedNotificationCenter *distCenter = [NSDistributedNotificationCenter defaultCenter];
    [distCenter addObserver:self selector:@selector(screenLocked:) name:@"com.apple.screenIsLocked" object:nil];
    [distCenter addObserver:self selector:@selector(screenUnlocked:) name:@"com.apple.screenIsUnlocked" object:nil];
}

- (void)screensDidSleep:(NSNotification *)note {
    runPowerScript(@"sleep", @"NSWorkspaceScreensDidSleepNotification");
}
- (void)screensDidWake:(NSNotification *)note {
    if (isSessionLocked()) {
        logMessage(@"Ignored NSWorkspaceScreensDidWakeNotification while screen is locked (waiting for unlock)");
    } else {
        runPowerScript(@"wake", @"NSWorkspaceScreensDidWakeNotification");
    }
}
- (void)willSleep:(NSNotification *)note {
    runPowerScript(@"sleep", @"NSWorkspaceWillSleepNotification");
}
- (void)didWake:(NSNotification *)note {
    if (CGDisplayIsAsleep(CGMainDisplayID())) {
        logMessage(@"Ignored NSWorkspaceDidWakeNotification during DarkWake (display is asleep)");
    } else if (isSessionLocked()) {
        logMessage(@"Ignored NSWorkspaceDidWakeNotification while screen is locked (waiting for unlock)");
    } else {
        runPowerScript(@"wake", @"NSWorkspaceDidWakeNotification");
    }
}
- (void)willPowerOff:(NSNotification *)note {
    runPowerScript(@"shutdown", @"NSWorkspaceWillPowerOffNotification");
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (shouldSkipShutdownOnReload()) {
        logMessage(@"Received applicationShouldTerminate during service reload, exiting without powering off");
    } else {
        runPowerScript(@"shutdown", @"applicationShouldTerminate");
    }
    return NSTerminateNow;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    if (!hasRecentShutdown()) {
        runPowerScript(@"shutdown", @"applicationWillTerminate");
    }
}
- (void)screenLocked:(NSNotification *)note {
    isScreenLocked = YES;
    runPowerScript(@"sleep", @"com.apple.screenIsLocked");
}
- (void)screenUnlocked:(NSNotification *)note {
    isScreenLocked = NO;
    runPowerScript(@"wake", @"com.apple.screenIsUnlocked");
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Catch SIGTERM / SIGINT / SIGHUP sent by launchd/loginwindow during shutdown / reboot / logout.
        // When `_install.sh` reloads the LaunchAgent, it touches `/tmp/screenbar-skip-shutdown`
        // so that reinstalls do not turn the lamp off.
        signal(SIGTERM, SIG_IGN);
        signal(SIGINT, SIG_IGN);
        signal(SIGHUP, SIG_IGN);
        dispatch_source_t sigtermSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sigtermSource, ^{
            handleTerminationSignal(@"SIGTERM");
        });
        dispatch_resume(sigtermSource);

        dispatch_source_t sigintSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sigintSource, ^{
            handleTerminationSignal(@"SIGINT");
        });
        dispatch_resume(sigintSource);

        dispatch_source_t sighupSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGHUP, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sighupSource, ^{
            handleTerminationSignal(@"SIGHUP");
        });
        dispatch_resume(sighupSource);

        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
