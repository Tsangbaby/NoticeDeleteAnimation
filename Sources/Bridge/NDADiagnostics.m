#import "NDABridge.h"
#import <objc/runtime.h>
#import <math.h>

static NSSet<NSString *> *allowed;
static NSSet<NSString *> *ancestorCodes;
static NSMutableDictionary<NSString *, NSNumber *> *counts;
static NSString *last;
static NSString *lastAncestor;
static BOOL pending;
static void NDAInitializeDiagnostics(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ancestorCodes = [NSSet setWithArray:@[@"ancestor.hidden", @"ancestor.alpha", @"ancestor.transform",
            @"ancestor.sublayer", @"ancestor.mask", @"ancestor.animations", @"ancestor.clipping",
            @"ancestor.depth", @"ancestor.hierarchy"]];
        NSMutableSet *keys = [NSMutableSet setWithArray:@[
            @"bootstrap", @"install.wait_request", @"install.wait_list", @"install.ready",
            @"install.top", @"install.group", @"install.list2", @"install.list3", @"install.retry_exhausted",
            @"request.top", @"request.group", @"request.off_main", @"request.nil", @"list.enter", @"list.no_scope", @"list.off_main", @"list.getter_abi", @"list.getter_exception",
            @"cell.missing", @"cell.duplicate", @"cell.controller", @"cell.request_mismatch", @"cell.source", @"cell.exception",
            @"capture.enter", @"capture.disabled", @"capture.reduce_motion", @"capture.window", @"capture.scene",
            @"capture.geometry", @"capture.ancestors", @"capture.capacity", @"capture.plan", @"capture.bitmap",
            @"capture.prepared", @"commit.failed", @"commit.source_attached", @"commit.surface", @"commit.shown"
        ]];
        [keys unionSet:ancestorCodes];
        allowed = [keys copy];
        counts = [NSMutableDictionary dictionary];
    });
}

// Fixed integer fields: nonfinite -> -1, otherwise clamped and rounded.
static NSInteger NDABounded(CGFloat value, CGFloat maximum) {
    return isfinite(value) ? (NSInteger)llround(MAX(0, MIN(maximum, value))) : -1;
}
static NSString *NDASystemClass(UIView *view) {
    Class cls = object_getClass(view);
    NSString *path = [NSBundle bundleForClass:cls].bundlePath;
    if (![path hasPrefix:@"/System/Library/"]) return @"non-system";
    NSString *name = NSStringFromClass(cls);
    if (!name.length || name.length > 80) return @"system-other";
    NSCharacterSet *chars = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"];
    if ([name rangeOfCharacterFromSet:chars.invertedSet].location != NSNotFound) return @"system-other";
    return name;
}

// Single synchronized bounded record, never a retained UIView or hierarchy.
// Off-main metadata is discarded: UIKit must not be read there.
void NDARecordAncestorFailure(NSString *code, UIView *view, NSInteger depth, CGFloat effectiveAlpha) {
    NDAInitializeDiagnostics();
    if (!NSThread.isMainThread || ![ancestorCodes containsObject:code]) return;
    NSString *record = [NSString stringWithFormat:
        @"Last ancestor: %@ class=%@ depth=%ld alpha_permille=%ld hidden=%d clips=%d mask=%d animated=%d width=%ld height=%ld",
        code, NDASystemClass(view), (long)MAX(1, MIN(64, depth)),
        (long)NDABounded(effectiveAlpha * 1000, 1000), view.isHidden, view.clipsToBounds,
        view.layer.mask != nil, (view.layer.animationKeys.count != 0),
        (long)NDABounded(view.bounds.size.width, 4096), (long)NDABounded(view.bounds.size.height, 4096)];
    @synchronized(allowed) { lastAncestor = record; }
    NDARecordEvent(code);
}

// Fixed-key accumulator schedules at most one pending main-thread flush.
void NDARecordEvent(NSString *code) {
    NDAInitializeDiagnostics();
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
        NSString *ancestor;
        @synchronized(allowed) {
            snapshot = [counts copy];
            lastEvent = last;
            ancestor = lastAncestor;
            pending = NO;
        }
        NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObjects:
            @"NoticeDeleteAnimation alpha5", [NSString stringWithFormat:@"SpringBoard PID: %d", NSProcessInfo.processInfo.processIdentifier],
            [@"Last event: " stringByAppendingString:lastEvent], nil];
        if (ancestor) [lines addObject:ancestor];
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
