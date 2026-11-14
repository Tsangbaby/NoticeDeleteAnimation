#import "NDABridge.h"
#import <objc/runtime.h>
#import <TargetConditionals.h>
#import <math.h>

static NSSet<NSString *> *allowed;
static NSSet<NSString *> *ancestorCodes;
static NSMutableDictionary<NSString *, NSNumber *> *counts;
static NSString *last;
static NSString *lastAncestor;
static NSString *lastClipping;
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
    BOOL system = [path hasPrefix:@"/System/Library/"];
#if TARGET_OS_SIMULATOR
    // Simulator framework bundle paths include the host's runtime-root prefix.
    // This normalization is never compiled into the device package.
    system = system || (path.length && [path rangeOfString:@"/System/Library/"].location != NSNotFound);
#endif
    if (!system) return @"non-system";
    NSString *name = NSStringFromClass(cls);
    if (!name.length || name.length > 80) return @"system-other";
    NSCharacterSet *chars = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"];
    if ([name rangeOfCharacterFromSet:chars.invertedSet].location != NSNotFound) return @"system-other";
    return name;
}

// Single synchronized bounded record, never a retained UIView or hierarchy.
// Off-main metadata is discarded: UIKit must not be read there.
static NSString *NDAAncestorRecord(NSString *code, UIView *view, NSInteger depth,
                                  CGFloat effectiveAlpha, CGRect bounds) {
    return [NSString stringWithFormat:
        @"Last ancestor: %@ class=%@ depth=%ld alpha_permille=%ld hidden=%d clips=%d mask=%d animated=%d width=%ld height=%ld",
        code, NDASystemClass(view), (long)MAX(1, MIN(64, depth)),
        (long)NDABounded(effectiveAlpha * 1000, 1000), view.isHidden, view.clipsToBounds,
        view.layer.mask != nil, (view.layer.animationKeys.count != 0),
        (long)NDABounded(bounds.size.width, 4096), (long)NDABounded(bounds.size.height, 4096)];
}
void NDARecordAncestorFailure(NSString *code, UIView *view, NSInteger depth, CGFloat effectiveAlpha) {
    NDAInitializeDiagnostics();
    if (!NSThread.isMainThread || ![ancestorCodes containsObject:code]) return;
    NSString *record = NDAAncestorRecord(code, view, depth, effectiveAlpha, view.bounds);
    @synchronized(allowed) { lastAncestor = record; lastClipping = nil; }
    NDARecordEvent(code);
}

// Fixed 0.01pt output, independent of locale. Negative coordinates are valid;
// 'invalid' is not a numeric sentinel. Never use NSStringFromCGRect/description.
static NSString *NDAGeometryNumber(CGFloat value, BOOL *clamped) {
    if (!isfinite(value)) return @"invalid";
    CGFloat bounded = MAX(-32768, MIN(32768, value));
    if (bounded != value) *clamped = YES;
    long long hundredths = llround(bounded * 100);
    unsigned long long magnitude = (unsigned long long)(hundredths < 0 ? -hundredths : hundredths);
    return [NSString stringWithFormat:@"%@%llu.%02llu", hundredths < 0 ? @"-" : @"",
        magnitude / 100, magnitude % 100];
}
static NSString *NDAGeometryRect(CGRect rect, BOOL *clamped) {
    return [NSString stringWithFormat:@"(%@,%@,%@,%@)",
        NDAGeometryNumber(rect.origin.x, clamped), NDAGeometryNumber(rect.origin.y, clamped),
        NDAGeometryNumber(rect.size.width, clamped), NDAGeometryNumber(rect.size.height, clamped)];
}
static BOOL NDAFiniteRect(CGRect rect) {
    return isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
        isfinite(rect.size.width) && isfinite(rect.size.height) &&
        rect.size.width >= 0 && rect.size.height >= 0 &&
        isfinite(CGRectGetMaxX(rect)) && isfinite(CGRectGetMaxY(rect));
}

void NDARecordClippingFailure(UIView *source, UIView *view, NSInteger depth, CGFloat effectiveAlpha,
                              CGRect sourceBounds, CGRect sourceInAncestor, CGRect ancestorBounds) {
    NDAInitializeDiagnostics();
    if (!NSThread.isMainThread) return;
    // No later convert(_:to:) call: these are the saved predicate operands.
    BOOL clamped = NO;
    NSString *sourceText = NDAGeometryRect(sourceBounds, &clamped);
    NSString *ancestorText = NDAGeometryRect(ancestorBounds, &clamped);
    NSString *convertedText = NDAGeometryRect(sourceInAncestor, &clamped);
    BOOL valid = NDAFiniteRect(sourceBounds) && NDAFiniteRect(sourceInAncestor) &&
        NDAFiniteRect(ancestorBounds) && sourceBounds.size.width > 0 && sourceBounds.size.height > 0 &&
        sourceInAncestor.size.width > 0 && sourceInAncestor.size.height > 0;
    NSInteger contains = -1, overlap = -1;
    NSString *intersectionText = @"invalid", *edgeText = @"invalid";
    if (valid) {
        CGFloat left = MAX(0, CGRectGetMinX(ancestorBounds) - CGRectGetMinX(sourceInAncestor));
        CGFloat top = MAX(0, CGRectGetMinY(ancestorBounds) - CGRectGetMinY(sourceInAncestor));
        CGFloat right = MAX(0, CGRectGetMaxX(sourceInAncestor) - CGRectGetMaxX(ancestorBounds));
        CGFloat bottom = MAX(0, CGRectGetMaxY(sourceInAncestor) - CGRectGetMaxY(ancestorBounds));
        valid = isfinite(left) && isfinite(top) && isfinite(right) && isfinite(bottom);
        if (valid) {
            CGRect intersection = CGRectIntersection(ancestorBounds, sourceInAncestor);
            BOOL empty = CGRectIsNull(intersection) || CGRectIsEmpty(intersection);
            intersectionText = empty ? @"empty" : NDAGeometryRect(intersection, &clamped);
            contains = CGRectContainsRect(CGRectInset(ancestorBounds, -0.5, -0.5), sourceInAncestor);
            // Axis ratios are bounded before multiplication: avoid tiny/huge area
            // products underflowing/overflowing into a false 0 or invalid ratio.
            CGFloat fraction = empty ? 0 :
                (intersection.size.width / sourceInAncestor.size.width) *
                (intersection.size.height / sourceInAncestor.size.height);
            valid = empty || (NDAFiniteRect(intersection) && isfinite(fraction) && fraction >= 0 && fraction <= 1);
            if (valid) {
                overlap = NDABounded(fraction * 1000, 1000);
            } else {
                contains = -1;
                intersectionText = @"invalid";
            }
            edgeText = [NSString stringWithFormat:@"(%@,%@,%@,%@)",
                NDAGeometryNumber(left, &clamped), NDAGeometryNumber(top, &clamped),
                NDAGeometryNumber(right, &clamped), NDAGeometryNumber(bottom, &clamped)];
        }
    }
    NSString *geometry = [NSString stringWithFormat:
        @"Clip geometry: source_class=%@ valid=%d clamped=%d contains_half_pt=%ld local_overlap_permille=%ld\nsource_bounds=%@\nancestor_bounds=%@\nsource_in_ancestor=%@\nlocal_intersection=%@\nedge_overflow_ltrb=%@",
        NDASystemClass(source), valid, clamped, (long)contains, (long)overlap,
        sourceText, ancestorText, convertedText, intersectionText, edgeText];
    NSString *record = NDAAncestorRecord(@"ancestor.clipping", view, depth, effectiveAlpha, ancestorBounds);
    @synchronized(allowed) { lastAncestor = record; lastClipping = geometry; }
    NDARecordEvent(@"ancestor.clipping");
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
        NSString *clipping;
        @synchronized(allowed) {
            snapshot = [counts copy];
            lastEvent = last;
            ancestor = lastAncestor;
            clipping = lastClipping;
            pending = NO;
        }
        NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObjects:
            @"NoticeDeleteAnimation alpha6", [NSString stringWithFormat:@"SpringBoard PID: %d", NSProcessInfo.processInfo.processIdentifier],
            [@"Last event: " stringByAppendingString:lastEvent], nil];
        if (ancestor) [lines addObject:ancestor];
        if (clipping) [lines addObject:clipping];
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
