//
//  NLNotificationDismissalSnapshot.h
//  NoticeListTweak 1.0.1~test14  (RootHide layout, arm64/arm64e)
//
//  Reverse-reconstructed from the shipped dylib. The original sources are lost;
//  everything here was recovered from the annotated disassembly in
//  work/listing.txt + work/objcdump.txt. Each declaration carries the address
//  it came from. Anything the disassembly does not prove is marked
//  "// REVERIFY:".
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Real shared renderer declaration. The reconstruction placeholder was only for
// isolated stub syntax checks; native production units must use one interface.
// ---------------------------------------------------------------------------
#import "NLDustRenderer.h"

// ---------------------------------------------------------------------------
// Shared file-scope state
//
// In the shipped binary every one of these is a *local* symbol (__ZL...) of a
// single translation unit, i.e. the tweak was one big .m file. They are exposed
// here as externs so the reconstruction can be split across files without
// changing behaviour. Definitions live in NLNotificationListHooks.m.
//
// NOTE for integration: NLAnimationEnabled / NLAnimationDuration / NLDustDistance
// / NLDustParticleLimit are (re)initialised on every call of NLLoadPreferences()
// @0x6290, which lives in the preferences unit. If that unit already defines
// them, delete the definitions in NLNotificationListHooks.m and keep only the
// externs below.
// ---------------------------------------------------------------------------
extern BOOL        NLAnimationEnabled;       // 0x263c8  default true
extern double      NLAnimationDuration;      // 0x263c0  default 1.3
extern double      NLDustDistance;           // 0x263b8  default 110.0
extern NSUInteger  NLDustParticleLimit;      // 0x263b0  default 14000 (0x36b0)
extern NSUInteger  NLActiveSnapshots;        // 0x264b8  live-snapshot COUNTER
extern char        NLDustSnapshotKey;        // 0x264c0  associated-object key byte
extern NSUInteger  NLReservedParticles;      // 0x264c8  particles handed out
extern NSUInteger  NLBatchParticleLimit;     // 0x264d0  per-batch cap (0 = none)
extern NSUInteger  NLRemovalDepth;           // 0x26500  re-entrancy guard
extern NSUInteger  NLObservedRemovals;       // 0x26508  logged-removals counter

extern IMP NLOriginalRemove;                                                 // 0x264e8
extern IMP NLOriginalRemoveDisplaced;                                        // 0x264f0
extern IMP NLOriginalClearAll;                                               // 0x264f8

void  NLLoadPreferences(void);                  // 0x6290  (preferences unit)
BOOL  NLLockScreenDustOwnsView(UIView *view);   // 0x16800 (lock-screen dust unit)

// ---------------------------------------------------------------------------
// NLNotificationDismissalSnapshot : UIView <CAAnimationDelegate>
//
// ivar layout is the exact class_ro ivar list (@0x24398, instance size 64).
// Do not reorder: the class is also reached reflectively at runtime.
// ---------------------------------------------------------------------------
@interface NLNotificationDismissalSnapshot : UIView <CAAnimationDelegate>
{
    BOOL            _counted;           // off  8
    BOOL            _cleanedUp;         // off  9
    BOOL            _waitingForRemoval; // off 10
    BOOL            _animationStarted;  // off 11
    NLDustRenderer *_dustRenderer;      // off 16  strong
    double          _effectDuration;    // off 24
    NSUInteger      _reservedParticles; // off 32
    __weak UIView  *_sourceView;        // off 40  weak  (property attr W)
    __weak UIView  *_sourceList;        // off 48  weak  (property attr W)
    double          _removalDeadline;   // off 56  CACurrentMediaTime() deadline
}

@property (nonatomic, assign) BOOL           counted;
@property (nonatomic, assign) BOOL           cleanedUp;
@property (nonatomic, strong) NLDustRenderer *dustRenderer;
@property (nonatomic, assign) double         effectDuration;
@property (nonatomic, assign) NSUInteger     reservedParticles;
@property (nonatomic, weak)   UIView        *sourceView;
@property (nonatomic, weak)   UIView        *sourceList;
@property (nonatomic, assign) double         removalDeadline;
@property (nonatomic, assign) BOOL           waitingForRemoval;
@property (nonatomic, assign) BOOL           animationStarted;

// 0x46e8. Returns nil whenever the dust effect cannot be prepared (not main
// thread, reduce-motion, too many live snapshots, view not visible / not in the
// same window as the list, no Metal renderer, particle budget too small, ...).
+ (instancetype)snapshotForList:(UIView *)list notificationView:(UIView *)view;

- (void)startRemovalAnimation;                                  // 0x4fa4
- (void)waitForNativeRemoval;                                   // 0x50c4
- (void)pollNativeRemoval;                                      // 0x51b8
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished; // 0x53ac
- (void)cleanUp;                                                // 0x53cc

@end
