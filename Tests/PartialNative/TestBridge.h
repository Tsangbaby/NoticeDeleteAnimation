#import "NDABridge.h"
#include <stdbool.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, NDATestAction) {
    NDATestActionRemoveSource, NDATestActionRemoveCell, NDATestActionKeepAttached,
    NDATestActionReparentSource, NDATestActionSurfaceBounds, NDATestActionAncestorBounds,
    NDATestActionReparentSurface, NDATestActionThrowOriginal
};
typedef struct {
    NSUInteger top, group, two, three, getters, index2, index3, getterIndex;
    bool animated2, animated3, displaced, identities, didThrow;
} NDATestTrace;
@interface NDATestFixture : NSObject { @public NDATestTrace trace; }
@property(nonatomic, strong, readonly) UIWindow *window;
@property(nonatomic, strong, readonly) UIView *host;
@property(nonatomic, strong, readonly) UIScrollView *list;
@property(nonatomic, strong, readonly) UIView *cell;
@property(nonatomic, strong, readonly, nullable) UIView *source;
@property(nonatomic, readonly) NSUInteger draws;
@end
FOUNDATION_EXPORT NDATestFixture *NDATestMakeFixture(void);
FOUNDATION_EXPORT void NDATestSettle(NDATestFixture *fixture);
// Catches only the deliberate fixture exception, so no ObjC exception crosses Swift.
FOUNDATION_EXPORT BOOL NDATestInvoke(NDATestFixture *fixture, BOOL three, BOOL nested,
    NDATestAction action, BOOL animated, BOOL displaced, NSUInteger index);
FOUNDATION_EXPORT void NDATestUnscoped(NDATestFixture *fixture, NSUInteger index, BOOL animated, BOOL displaced);
FOUNDATION_EXPORT NDATestTrace NDATestReadTrace(NDATestFixture *fixture);
FOUNDATION_EXPORT void NDATestMismatchRequest(NDATestFixture *fixture);
FOUNDATION_EXPORT void NDATestMutateDuringDraw(NDATestFixture *fixture);
FOUNDATION_EXPORT void NDATestOnDraw(NDATestFixture *fixture, void (^callback)(void));
FOUNDATION_EXPORT void NDATestForgetSource(NDATestFixture *fixture);
FOUNDATION_EXPORT NSUInteger NDATestHookCount(void);
// Test-host identity adapter; never changes CFBundle registration or production code.
FOUNDATION_EXPORT void NDATestUseSpringBoardIdentity(BOOL enabled);
FOUNDATION_EXPORT CGSize NDATestBackingSize(CALayer *tile);
FOUNDATION_EXPORT BOOL NDATestNoHiddenRed(CALayer *tile);
NS_ASSUME_NONNULL_END
