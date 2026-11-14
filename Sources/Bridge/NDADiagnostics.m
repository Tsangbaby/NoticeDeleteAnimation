#import "NDABridge.h"

// Persist only allowlisted event names/counters, never notification data. Main
// A fixed-key synchronized accumulator schedules at most one pending main flush.
// No UI access or preferences I/O occurs on a hook's off-main thread.
void NDARecordEvent(NSString *code) {
    static NSSet<NSString *> *allowed;
    static NSMutableDictionary<NSString *, NSNumber *> *counts;
    static NSString *last;
    static BOOL pending = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSSet setWithArray:@[
            @"bootstrap", @"install.wait_request", @"install.wait_list", @"install.ready",
            @"install.top", @"install.group", @"install.list2", @"install.list3", @"install.retry_exhausted",
            @"request.top", @"request.group", @"request.off_main", @"request.nil", @"list.enter", @"list.no_scope", @"list.off_main", @"list.getter_abi", @"list.getter_exception",
            @"cell.missing", @"cell.duplicate", @"cell.controller", @"cell.request_mismatch", @"cell.source", @"cell.exception",
            @"capture.enter", @"capture.disabled", @"capture.reduce_motion", @"capture.window", @"capture.scene",
            @"capture.geometry", @"capture.ancestors", @"capture.capacity", @"capture.plan", @"capture.bitmap",
            @"capture.prepared", @"commit.failed", @"commit.source_attached", @"commit.surface", @"commit.shown"
        ]];
        counts = [NSMutableDictionary dictionary];
    });
    if (![allowed containsObject:code]) return;
    @synchronized(allowed) {
        counts[code] = @(MIN(1000000ULL, counts[code].unsignedLongLongValue + 1));
        last = code;
        if (pending) return;
        pending = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        NSDictionary *snapshot;
        NSString *lastEvent;
        @synchronized(allowed) {
            snapshot = [counts copy];
            lastEvent = last;
            pending = NO;
        }
        NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObjects:
            @"NoticeDeleteAnimation alpha2", [NSString stringWithFormat:@"SpringBoard PID: %d", NSProcessInfo.processInfo.processIdentifier],
            [@"Last event: " stringByAppendingString:lastEvent], nil];
        for (NSString *key in [[snapshot allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            [lines addObject:[NSString stringWithFormat:@"%@: %@", key, snapshot[key]]];
        }
        CFStringRef domain = CFSTR("com.tsangbaby.noticedeleteanimation");
        CFPreferencesSetAppValue(CFSTR("DiagnosticsSummary"), (__bridge CFStringRef)[lines componentsJoinedByString:@"\n"], domain);
        CFPreferencesSetAppValue(CFSTR("DiagnosticsUpdated"), (__bridge CFStringRef)NSDate.date.description, domain);
        CFPreferencesSetAppValue(CFSTR("DiagnosticsPID"), (__bridge CFNumberRef)@(NSProcessInfo.processInfo.processIdentifier), domain);
        CFPreferencesAppSynchronize(domain);
    });
}
