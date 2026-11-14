#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Called before a verified list removal, returns an opaque Swift effect handle.
typedef id _Nullable (^NDAPrepareEffect)(UIView *source, UIView *surface);
typedef void (^NDAFinishEffect)(id handle, BOOL committed);
FOUNDATION_EXPORT void NDARecordEvent(NSString *code);
/// First rejected ancestor only; fixed reason/state fields, no view retained.
FOUNDATION_EXPORT void NDARecordAncestorFailure(NSString *code, UIView *view, NSInteger depth, CGFloat effectiveAlpha);
FOUNDATION_EXPORT BOOL NDAInstallHooks(NDAPrepareEffect prepare, NDAFinishEffect finish);
/// Exception-contained UIKit capture. Returns nil on unsupported/failed snapshots.
FOUNDATION_EXPORT UIImage * _Nullable NDACaptureView(UIView *view, CGFloat scale);
NS_ASSUME_NONNULL_END
