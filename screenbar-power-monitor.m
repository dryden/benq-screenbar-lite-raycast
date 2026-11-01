#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOKit/IOMessage.h>
#include <signal.h>

static io_connect_t root_port = MACH_PORT_NULL;
static NSString *lastEvent = @"";
static NSTimeInterval lastEventTime = 0;

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

static void runPowerScript(NSString *event, NSString *source) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if ([event isEqualToString:lastEvent] && (now - lastEventTime) < 2.0) {
        logMessage([NSString stringWithFormat:@"Ignored duplicate '%@' from %@", event, source]);
        return;
    }
    lastEvent = [event copy];
    lastEventTime = now;
    logMessage([NSString stringWithFormat:@"Triggering '%@' from %@", event, source]);

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[getPowerEventScriptPath(), event];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *e) {
        logMessage([NSString stringWithFormat:@"Error launching script: %@", e]);
    }
}

static void displayCallback(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo) {
    if (CGDisplayIsAsleep(CGMainDisplayID())) {
        runPowerScript(@"sleep", @"CGDisplayIsAsleep");
    }
}

static void powerCallback(void *refCon, io_service_t service, natural_t messageType, void *messageArgument) {
    switch (messageType) {
        case kIOMessageCanSystemSleep:
            IOAllowPowerChange(root_port, (long)messageArgument);
            break;
        case kIOMessageSystemWillSleep:
            runPowerScript(@"sleep", @"kIOMessageSystemWillSleep");
            IOAllowPowerChange(root_port, (long)messageArgument);
            break;
        case kIOMessageSystemHasPoweredOn:
            if (!CGDisplayIsAsleep(CGMainDisplayID())) {
                runPowerScript(@"wake", @"kIOMessageSystemHasPoweredOn");
            } else {
                logMessage(@"Ignored kIOMessageSystemHasPoweredOn during DarkWake (display is asleep)");
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
    runPowerScript(@"wake", @"NSWorkspaceScreensDidWakeNotification");
}
- (void)willSleep:(NSNotification *)note {
    runPowerScript(@"sleep", @"NSWorkspaceWillSleepNotification");
}
- (void)didWake:(NSNotification *)note {
    if (!CGDisplayIsAsleep(CGMainDisplayID())) {
        runPowerScript(@"wake", @"NSWorkspaceDidWakeNotification");
    } else {
        logMessage(@"Ignored NSWorkspaceDidWakeNotification during DarkWake (display is asleep)");
    }
}
- (void)willPowerOff:(NSNotification *)note {
    runPowerScript(@"shutdown", @"NSWorkspaceWillPowerOffNotification");
}
- (void)screenLocked:(NSNotification *)note {
    runPowerScript(@"sleep", @"com.apple.screenIsLocked");
}
- (void)screenUnlocked:(NSNotification *)note {
    runPowerScript(@"wake", @"com.apple.screenIsUnlocked");
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Catch SIGTERM / SIGINT (sent by launchd on shutdown / reboot / logout)
        signal(SIGTERM, SIG_IGN);
        signal(SIGINT, SIG_IGN);
        dispatch_source_t sigtermSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sigtermSource, ^{
            runPowerScript(@"shutdown", @"SIGTERM");
            exit(0);
        });
        dispatch_resume(sigtermSource);

        dispatch_source_t sigintSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sigintSource, ^{
            runPowerScript(@"shutdown", @"SIGINT");
            exit(0);
        });
        dispatch_resume(sigintSource);

        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
