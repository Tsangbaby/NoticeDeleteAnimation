// Renderer origin is LOCAL to its own viewport, never the overlay's coordinates.
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
static inline BOOL NLRenderRectValid(CGRect rect) {
    return !CGRectIsNull(rect) && !CGRectIsInfinite(rect) &&
        isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
        isfinite(rect.size.width) && isfinite(rect.size.height) &&
        rect.size.width > 0 && rect.size.height > 0 &&
        isfinite(CGRectGetMaxX(rect)) && isfinite(CGRectGetMaxY(rect));
}
static inline BOOL NLMakeRenderGeometry(CGRect card, CGRect viewport, CGFloat distance,
                                        CGRect *rendererFrame, CGRect *localCard) {
    if (!rendererFrame || !localCard || !NLRenderRectValid(card) ||
        !NLRenderRectValid(viewport) || !isfinite(distance) || distance < 0 || distance > 4096)
        return NO;
    CGFloat margin = distance * 2.2 + 10;
    CGRect frame = CGRectIntersection(CGRectInset(card, -margin, -margin), viewport);
    if (!NLRenderRectValid(frame)) return NO;
    CGRect local = CGRectOffset(card, -frame.origin.x, -frame.origin.y);
    if (!NLRenderRectValid(local)) return NO;
    *rendererFrame = frame;
    *localCard = local;
    return YES;
}
