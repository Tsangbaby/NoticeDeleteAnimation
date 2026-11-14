#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Called before a verified list removal, returns an opaque Swift effect handle.
typedef id _Nullable (^NDAPrepareEffect)(UIView *source, UIView *surface);
typedef void (^NDAFinishEffect)(id handle, BOOL committed);
FOUNDATION_EXPORT void NDARecordEvent(NSString *code);
/// First rejected ancestor only; fixed reason/state fields, no view retained.
FOUNDATION_EXPORT void NDARecordAncestorFailure(NSString *code, UIView *view, NSInteger depth, CGFloat effectiveAlpha);
/// Immutable clipping operands; signed bounded numeric data, no content or views retained.
FOUNDATION_EXPORT void NDARecordClippingFailure(UIView *source, UIView *view, NSInteger depth, CGFloat effectiveAlpha,
    CGRect sourceBounds, CGRect sourceInAncestor, CGRect ancestorBounds);
FOUNDATION_EXPORT BOOL NDAInstallHooks(NDAPrepareEffect prepare, NDAFinishEffect finish);
/// Exception-contained UIKit capture. Returns nil on unsupported/failed snapshots.
FOUNDATION_EXPORT UIImage * _Nullable NDACaptureView(UIView *view, CGFloat scale);
/// Capture only a contained source-local crop; never mutate or snapshot an ancestor.
FOUNDATION_EXPORT UIImage * _Nullable NDACaptureRegion(UIView *view, CGRect region, CGFloat scale);
/// Fixed bounded geometry of the last successfully prepared crop, no content retained.
FOUNDATION_EXPORT void NDARecordRegionPrepared(UIView *source, CGRect sourceRect, CGRect surfaceRect, CGRect clipRect, BOOL partial);
NS_ASSUME_NONNULL_END
