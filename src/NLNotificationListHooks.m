//
//  NLNotificationListHooks.m
//  NoticeListTweak 1.0.1~test14
//
//  Reverse-reconstructed list-side hooks:
//    0x67b4  static void NLRemoveView(id, SEL, NSUInteger, BOOL)
//    0x693c  static void NLRemoveDisplacedView(id, SEL, NSUInteger, BOOL, BOOL)
//    0x6ad8  static void NLClearAll(id, SEL)
//    0x70b8  static void NLFindVisibleCards(UIView *, NSMutableArray *, Class)
//    0x7388  static id   NLPrepareSnapshot(id, unsigned long)
//    0x57b8  BOOL NLExistingNotificationSnapshotActive(id)
//
//  The hook entry points were installed with MSHookMessageEx from
//  -[NLNotificationHookLoader tryInstalling] @0x591c:
//    0x60b8  NCNotificationListView   -removeViewAtIndex:animated:              -> NLRemoveView
//    0x618c  NCNotificationListView   -removeViewAtIndex:animated:isHorizontallyDisplaced: -> NLRemoveDisplacedView
//    0x5ea8  NCNotificationMasterList -clearAll                                  -> NLClearAll
//  and the original IMPs were stored in NLOriginalRemove / NLOriginalRemoveDisplaced /
//  NLOriginalClearAll. Compile with -fobjc-arc (the original was ARC).
//

#import "NLNotificationDismissalSnapshot.h"
#import <objc/runtime.h>

// substrate.h is only needed for MSHookMessageEx; the hook installation itself
// lives in the loader unit. Declared here so this file stays self-contained.
extern void MSHookMessageEx(Class cls, SEL sel, IMP replacement, IMP *original);

#define NL_LOG(fmt, ...) NSLog((@"[NoticeListTweak] " fmt), ##__VA_ARGS__)

// ---------------------------------------------------------------------------
// File-scope state (all were __ZL... / local symbols of the single original TU)
// ---------------------------------------------------------------------------

// Animation defaults. NLLoadPreferences() @0x6290 re-writes all four on every
// call (defaults: enabled=YES, duration=1.3, distance=110.0, particles=14000),
// then applies the CFPreferences overrides from
// com.example.noticelisttweak: {Enabled, DustDuration, DustDistance, DustParticles}.
// 注：NLAnimationEnabled / NLAnimationDuration / NLDustDistance /
// NLDustParticleLimit / NLReservedParticles / NLBatchParticleLimit 定义在
// NLPreferences.m（声明见 NLPreferences.h），此处不再重复定义。

// Number of snapshots that are currently counted as live (guards against
// runaway effects). NOT a set, despite the name: it is compared to 5 and
// incremented/decremented.
NSUInteger  NLActiveSnapshots    = 0;          // 0x264b8

// Re-entrancy guard around the hooked removal call.
NSUInteger  NLRemovalDepth       = 0;          // 0x26500

// Diagnostics counter: how many removals have been animated.
NSUInteger  NLObservedRemovals   = 0;          // 0x26508

// 定义在 NLNotificationHookLoader.m（MSHookMessageEx 的 original 输出参数）
// NLOriginalRemove / NLOriginalRemoveDisplaced / NLOriginalClearAll
// 的定义在 NLNotificationHookLoader.m（声明见 NLNotificationListHooks.h）

// Private accessor of NCNotificationListView (validated in tryInstalling).
@interface NSObject (NLNotificationListViewPrivate)
- (UIView *)masterListView;
- (UIView *)_visibleViewAtIndex:(NSUInteger)index;
@end

#pragma mark - 0x57b8

// 0x57b8  BOOL NLExistingNotificationSnapshotActive(id view)
//
// Walks the view and all of its superviews looking for an attached dismissal
// snapshot. Used by the withdrawal-effect unit (@0x11ab4) to decide whether an
// incoming notification is "the same card that is already dissolving".
// NOTE: it does not consult -cleanedUp; it relies on cleanUp detaching the
// associated object.
// 0x57b8 is shared with withdrawal effects and defined exactly once in
// NLPreferences.m. Keeping a second external copy here breaks native linking.

#pragma mark - 0x7388

// 0x7388  static id NLPrepareSnapshot(id list, unsigned long index)
//
// Resolves the card at `index`, reuses an in-flight snapshot if there is one,
// otherwise builds a fresh one. Returns nil whenever the effect must be skipped
// (disabled, wrong thread, not a view, lock-screen dust already owns the view,
// or the snapshot factory refused).
static id NLPrepareSnapshot(id list, unsigned long index)
{
    NLLoadPreferences();                                        // 0x73b0

    if (!NLAnimationEnabled)                                    // 0x73b4
        return nil;
    if (![NSThread isMainThread])                               // 0x73c4
        return nil;
    if (![list isKindOfClass:[UIView class]])                   // 0x73dc
        return nil;

    @try {
        UIView *view = [(UIView *)list _visibleViewAtIndex:index];   // 0x7408
        if (NLLockScreenDustOwnsView(view))                          // 0x7424
            return nil;

        // Reuse the snapshot that is already dissolving this card: a second
        // removal request for the same row must not stack a second effect.
        NLNotificationDismissalSnapshot *existing =
            objc_getAssociatedObject(view, &NLDustSnapshotKey);      // 0x7434
        if (existing != nil &&
            !existing.cleanedUp &&
            !existing.animationStarted)                              // 0x7458, 0x746c
            return existing;

        return [NLNotificationDismissalSnapshot snapshotForList:list
                                               notificationView:view]; // 0x7480
    } @catch (NSException *exception) {                                // 0x74f8
        // REVERIFY: the binary logs `exception.name` from the catch pad and
        // returns nil; the @try span itself could not be recovered exactly, so
        // it is placed around the two throwing message sends.
        NL_LOG(@"snapshot skipped (%@)", exception.name);
        return nil;
    }
}

#pragma mark - 0x67b4

// 0x67b4  void NLRemoveView(id self, SEL _cmd, NSUInteger index, BOOL animated)
//
// Hook for -[NCNotificationListView removeViewAtIndex:animated:].
//
// If the dust effect can be prepared, the *native* removal is forced to be
// non-animated (`animated && snapshot == nil`) because the snapshot overlay
// covers the visual transition; the dust effect then plays on top of the
// already-vanished row.
void NLRemoveView(id self, SEL _cmd, NSUInteger index, BOOL animated)
{
    // Re-entrant or off-main call: behave exactly like the original.
    if (NLRemovalDepth != 0 || ![NSThread isMainThread]) {        // 0x67e4
        ((void (*)(id, SEL, NSUInteger, BOOL))NLOriginalRemove)(self, _cmd, index, animated);   // 0x680c
        return;
    }

    NLNotificationDismissalSnapshot *snapshot = nil;
    @try {
        NLRemovalDepth = 1;                                       // 0x682c
        snapshot = NLPrepareSnapshot(self, index);                // 0x6834
        ((void (*)(id, SEL, NSUInteger, BOOL))NLOriginalRemove)(
            self, _cmd, index, animated && (snapshot == nil));   // 0x6850
        NLRemovalDepth -= 1;                                      // 0x6870
    } @catch (id exception) {                                     // 0x68d8
        // REVERIFY: the landing pad is a catch-all (no type filter) that
        // decrements the depth, tears the snapshot down and rethrows. It is
        // reproduced verbatim, but the exact source construct that produced it
        // (a deliberate `@catch (id)` + @throw vs. a compiler cleanup pad) is
        // not provable from the disassembly.
        NLRemovalDepth -= 1;
        [snapshot cleanUp];
        @throw;
    }

    [snapshot startRemovalAnimation];                             // 0x6880

    if (snapshot != nil) {                                        // 0x688c
        NSUInteger observed = NLObservedRemovals;                  // 0x6890
        NLObservedRemovals = observed + 1;
        if (observed <= 2)                                        // 0x68a0
            NL_LOG(@"animated real notification removal");        // 0x20448
    }
}

#pragma mark - 0x693c

// 0x693c  static void NLRemoveDisplacedView(id self, SEL _cmd, NSUInteger index,
//                                           BOOL animated, BOOL displaced)
//
// Hook for -[NCNotificationListView
// removeViewAtIndex:animated:isHorizontallyDisplaced:]. Same handshake as
// NLRemoveView; `displaced` is forwarded untouched.
void NLRemoveDisplacedView(id self, SEL _cmd, NSUInteger index,
                           BOOL animated, BOOL displaced)
{
    if (NLRemovalDepth != 0 || ![NSThread isMainThread]) {        // 0x6974
        ((void (*)(id, SEL, NSUInteger, BOOL, BOOL))NLOriginalRemoveDisplaced)(
        self, _cmd, index, animated, displaced);                 // 0x69a0
        return;
    }

    NLNotificationDismissalSnapshot *snapshot = nil;
    @try {
        NLRemovalDepth = 1;                                       // 0x69c0
        snapshot = NLPrepareSnapshot(self, index);                // 0x69c8
        ((void (*)(id, SEL, NSUInteger, BOOL, BOOL))NLOriginalRemoveDisplaced)(
            self, _cmd, index, animated && (snapshot == nil), displaced); // 0x69e4
        NLRemovalDepth -= 1;                                      // 0x6a08
    } @catch (id exception) {                                     // 0x6a74
        NLRemovalDepth -= 1;                                      // REVERIFY: see NLRemoveView
        [snapshot cleanUp];
        @throw;
    }

    [snapshot startRemovalAnimation];                             // 0x6a18

    if (snapshot != nil) {                                        // 0x6a24
        NSUInteger observed = NLObservedRemovals;                  // 0x6a28
        NLObservedRemovals = observed + 1;
        if (observed <= 2)                                        // 0x6a38
            NL_LOG(@"animated real notification removal (displaced)"); // 0x20488
    }
}

#pragma mark - 0x70b8

// 0x70b8  static void NLFindVisibleCards(UIView *view, NSMutableArray *cards, Class cardClass)
//
// Depth-first collection of the notification cards that are actually visible in
// the window. Hard cap: 8 cards (bail as soon as the array already holds more
// than 7). Hidden / near-invisible containers are pruned, and a card whose
// frame does not intersect the window is dropped.
static void NLFindVisibleCards(UIView *view, NSMutableArray *cards, Class cardClass)
{
    if (cards.count > 7)                                          // 0x7114
        return;
    if (view.isHidden)                                            // 0x712c
        return;
    if (view.alpha < 0.02)                                        // 0x7140 (0x195c0)
        return;

    if ([view isKindOfClass:cardClass]) {                          // 0x7160
        UIWindow *window = view.window;                            // 0x7178
        if (window != nil) {
            CGRect inWindow = [view convertRect:view.bounds toView:window];  // 0x7198
            if (CGRectIntersectsRect(inWindow, window.bounds))     // 0x71f8
                [cards addObject:view];                            // 0x7204
        }
        return;                                                    // cards are leaves here
    }

    for (UIView *subview in view.subviews)                         // 0x722c
        NLFindVisibleCards(subview, cards, cardClass);             // 0x72a0
}

#pragma mark - 0x6ad8

// 0x6ad8  void NLClearAll(id self, SEL _cmd)
//
// Hook for -[NCNotificationMasterList clearAll]. The visual effect has to be
// prepared *before* the real clear-all runs (the rows still exist), then the
// native clear-all is invoked, and only afterwards are the queued snapshots
// told to wait for / animate the native removal.
void NLClearAll(id self, SEL _cmd)
{
    if (![NSThread isMainThread]) {                                // 0x6b18
        ((void (*)(id, SEL))NLOriginalClearAll)(self, _cmd);                            // 0x6e38
        return;
    }

    NSMutableArray *snapshots = [NSMutableArray array];            // 0x6b38
    NLLoadPreferences();                                           // 0x6b58
    Class cellClass = NSClassFromString(@"NCNotificationListCell"); // 0x6b5c
    UIView *masterList = [self masterListView];                    // 0x6b70

    @try {
        // Everything below only prepares visuals; a failure here must not stop
        // the real clear-all from happening.
        if (NLAnimationEnabled && [NSThread isMainThread] &&
            cellClass != nil && [NLDustRenderer isReady] &&
            [masterList isKindOfClass:[UIView class]]) {           // 0x6b88..0x6bf8
            NSMutableArray *cards = [NSMutableArray array];        // 0x6bfc
            NLFindVisibleCards(masterList, cards, cellClass);      // 0x6c18

            // Split the global 42000-particle pool over the visible cards, but
            // never give a single batch less than 3000.
            NSUInteger visibleCount = cards.count;                 // 0x6c30
            if (visibleCount < 1)
                visibleCount = 1;
            NSUInteger perBatch = 42000 / visibleCount;            // 0x6c44
            if (perBatch < 3000)
                perBatch = 3000;                                   // 0x6c4c
            NLBatchParticleLimit = perBatch;                       // 0x6c58

            for (UIView *card in cards) {                          // 0x6c7c
                NLNotificationDismissalSnapshot *snapshot =
                    [NLNotificationDismissalSnapshot snapshotForList:masterList
                                                    notificationView:card]; // 0x6cf8
                if (snapshot != nil)                               // 0x6d14
                    [snapshots addObject:snapshot];                // 0x6d18
            }
        }
    } @catch (NSException *exception) {                            // 0x7008
        NL_LOG(@"clear-all visual skipped (%@)", exception.name);   // 0x20428
    } @catch (id exception) {                                      // 0x6eb4
        // REVERIFY: catch-all pad: every queued snapshot is torn down, the
        // batch limit is reset and the exception is rethrown (0x6f00 loads
        // @sel(cleanUp), 0x7070 stores 0 into NLBatchParticleLimit before
        // objc_exception_rethrow). Whether the source really had two @catch
        // clauses or one @catch plus a compiler cleanup pad is not provable.
        (void)exception;
        for (NLNotificationDismissalSnapshot *snapshot in snapshots)
            [snapshot cleanUp];
        NLBatchParticleLimit = 0;
        @throw;
    }

    NLBatchParticleLimit = 0;                                      // 0x6d64

    ((void (*)(id, SEL))NLOriginalClearAll)(self, _cmd);                                // 0x6d70

    // The native clear-all has happened; let each snapshot observe the actual
    // disappearance of its row and then play the dust.
    for (NLNotificationDismissalSnapshot *snapshot in snapshots)    // 0x6d80
        [snapshot waitForNativeRemoval];                            // 0x6dc8
}
